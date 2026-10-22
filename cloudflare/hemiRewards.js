// Hemi Exchange API: turns in-game gold into signed claim vouchers for the
// AshfallRewards contract (contracts/src/AshfallRewards.sol).
//
// The game runs in the player's browser, so nothing it reports can be trusted.
// This API therefore:
//   - only signs for wallets that prove ownership by signing a one-time challenge,
//   - only pays gold that is in the wallet's on-chain save (AshfallSaves),
//     at most the gold earned in the current run (a run starts with New Game),
//     at most RUN_GOLD_LIMIT per run (everything the game can give in one run),
//     and unlocking at GOLD_PER_MINUTE from the run's start time, which the
//     chain stamps and players cannot backdate,
//   - caps how much gold one wallet can ever exchange (WALLET_CAP_GOLD), across
//     all runs: New Game never resets it,
//   - caps how much gold all wallets together can exchange per day (DAILY_CAP_GOLD),
//   - cashes each on-chain save in once: after an exchange, only a newer save counts,
//   - keeps every balance in one Durable Object, so checks and updates happen one
//     request at a time and a signed challenge works exactly once,
//   - signs the wallet's *cumulative* credit, so stale or duplicate vouchers can't pay twice.
// The contract can never pay out more than the token budget it holds.
//
// Configuration (wrangler.jsonc "vars"):
//   HEMI_CHAIN_ID          43111 (mainnet) or 743111 (Hemi Sepolia)
//   REWARDS_CONTRACT       deployed AshfallRewards address
//   SAVES_CONTRACT         deployed AshfallSaves address
//   REWARD_TOKEN           token paid out for gold (HEMI on mainnet, tHEMI on testnet)
//   REWARD_TOKEN_SYMBOL    shown to players, e.g. "HEMI"
//   REWARD_TOKEN_DECIMALS  18
//   GOLD_PER_TOKEN         game gold needed for 1 whole token
//   WALLET_CAP_GOLD        lifetime gold one wallet can exchange
//   DAILY_CAP_GOLD         gold all wallets together can exchange per UTC day
//   RUN_GOLD_LIMIT         most gold one run can exchange
//   GOLD_PER_MINUTE        how fast a run's gold unlocks for exchange
//   VEHEMI_CONTRACT        veHemi (staking) contract, passed to the game
//   VOUCHER_TTL_SECONDS    how long a voucher stays valid
// Secret:   SIGNER_PRIVATE_KEY (wrangler secret put SIGNER_PRIVATE_KEY)
// Binding:  LEDGER             (Durable Object, cloudflare/ledger.js: challenges and every balance)

import { createPublicClient, getAddress, hexToString, http, isAddress, isHex, parseAbi, verifyMessage } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const SAVES_ABI = parseAbi([
  "function getSave(address player) view returns (uint64 runId, uint64 runStartedAt, uint64 savedAt, uint64 saveCount, bytes data)",
]);

const EIP712_ABI = parseAbi([
  "function eip712Domain() view returns (bytes1 fields, string name, string version, uint256 chainId, address verifyingContract, bytes32 salt, uint256[] extensions)",
]);

// official veHemi (vote-escrowed HEMI) on Hemi mainnet
const VEHEMI = { 43111: "0x371d3718D5b7F75EAb050FAe6Da7DF3092031c89" };

const CHAINS = {
  43111: {
    name: "Hemi",
    rpcUrl: "https://rpc.hemi.network/rpc",
    explorerUrl: "https://explorer.hemi.xyz",
  },
  743111: {
    name: "Hemi Sepolia",
    rpcUrl: "https://testnet.rpc.hemi.network/rpc",
    explorerUrl: "https://testnet.explorer.hemi.xyz",
  },
};

const MAX_GOLD_PER_REQUEST = 1_000_000;

// the voucher signing key as 0x-prefixed hex, whether it was pasted with or
// without the 0x; null when it is missing or malformed
function signerKey(env) {
  const key = String(env.SIGNER_PRIVATE_KEY || "").trim();
  const hex = /^0x/i.test(key) ? key.slice(2) : key;
  return /^[0-9a-fA-F]{64}$/.test(hex) ? `0x${hex}` : null;
}

function readConfig(env) {
  const chainId = Number(env.HEMI_CHAIN_ID || 43111);
  const chain = CHAINS[chainId] || { name: `Chain ${chainId}`, rpcUrl: env.HEMI_RPC_URL || "", explorerUrl: "" };
  const address = (value) => (value && isAddress(value) ? getAddress(value) : null);
  const contract = address(env.REWARDS_CONTRACT);
  const savesContract = address(env.SAVES_CONTRACT);
  const token = address(env.REWARD_TOKEN);
  return {
    chainId,
    chainName: chain.name,
    rpcUrl: env.HEMI_RPC_URL || chain.rpcUrl,
    explorerUrl: chain.explorerUrl,
    contract,
    savesContract,
    veHemi: address(env.VEHEMI_CONTRACT) || VEHEMI[chainId] || null,
    token,
    symbol: env.REWARD_TOKEN_SYMBOL || "HEMI",
    decimals: Number(env.REWARD_TOKEN_DECIMALS || 18),
    goldPerToken: Math.max(1, Number(env.GOLD_PER_TOKEN || 10)),
    walletCapGold: Math.max(0, Number(env.WALLET_CAP_GOLD || 500)),
    dailyCapGold: Math.max(0, Number(env.DAILY_CAP_GOLD || 20000)),
    runGoldLimit: Math.max(0, Number(env.RUN_GOLD_LIMIT || 200)),
    goldPerMinute: Math.max(0, Number(env.GOLD_PER_MINUTE || 10)),
    voucherTtl: Math.max(60, Number(env.VOUCHER_TTL_SECONDS || 900)),
    // what the exchange still needs before it opens (names only, never values)
    missing: [
      !contract && "REWARDS_CONTRACT",
      !savesContract && "SAVES_CONTRACT",
      !token && "REWARD_TOKEN",
      !signerKey(env) && "SIGNER_PRIVATE_KEY",
      !env.LEDGER && "LEDGER",
    ].filter(Boolean),
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function fail(message, status = 400) {
  return json({ ok: false, error: message }, status);
}

function publicConfig(config) {
  return {
    ok: true,
    configured: config.missing.length === 0,
    missing: config.missing,
    chainId: config.chainId,
    chainName: config.chainName,
    rpcUrl: config.rpcUrl,
    explorerUrl: config.explorerUrl,
    contract: config.contract,
    savesContract: config.savesContract,
    veHemi: config.veHemi,
    token: config.token,
    symbol: config.symbol,
    decimals: config.decimals,
    goldPerToken: config.goldPerToken,
    walletCapGold: config.walletCapGold,
    runGoldLimit: config.runGoldLimit,
    goldPerMinute: config.goldPerMinute,
  };
}

// gold -> token base units, exact integer math
function goldToAmount(gold, config) {
  return (BigInt(gold) * 10n ** BigInt(config.decimals)) / BigInt(config.goldPerToken);
}

function challengeMessage(address, chainId, nonce, issuedAt) {
  return [
    "Ashfall - Hemi Exchange",
    "",
    "Sign to exchange your game gold for tokens. Signing is free and sends no transaction.",
    "",
    `Wallet: ${address}`,
    `Chain: ${chainId}`,
    `Nonce: ${nonce}`,
    `Issued: ${issuedAt}`,
  ].join("\n");
}

function randomNonce() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function wholeGold(value) {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? Math.min(n, 1_000_000_000) : 0;
}

// the exchange ledger (cloudflare/ledger.js): one Durable Object, so every
// balance check and update happens one request at a time, consistently
async function ledger(env, payload) {
  const stub = env.LEDGER.get(env.LEDGER.idFromName("ledger"));
  const response = await stub.fetch("https://ledger/", { method: "POST", body: JSON.stringify(payload) });
  return response.json();
}

// The rewards contract's signing domain, as the contract itself reports it
// (EIP-5267). Vouchers then match whichever deployment REWARDS_CONTRACT points
// at, whatever name it was deployed under. Kept for the life of the Worker.
const domains = new Map();
async function rewardsDomain(config) {
  const key = `${config.chainId}:${config.contract}`;
  if (!domains.has(key)) {
    const client = createPublicClient({ transport: http(config.rpcUrl) });
    const [, name, version, chainId, verifyingContract] = await client.readContract({
      address: config.contract,
      abi: EIP712_ABI,
      functionName: "eip712Domain",
    });
    if (Number(chainId) !== config.chainId || getAddress(verifyingContract) !== config.contract) {
      throw new Error("REWARDS_CONTRACT is not on HEMI_CHAIN_ID");
    }
    domains.set(key, { name, version, chainId: config.chainId, verifyingContract: config.contract });
  }
  return domains.get(key);
}

// the wallet's on-chain save, read straight from the chain
async function readSave(config, address) {
  const client = createPublicClient({ transport: http(config.rpcUrl) });
  const [runId, runStartedAt, savedAt, saveCount, data] = await client.readContract({
    address: config.savesContract,
    abi: SAVES_ABI,
    functionName: "getSave",
    args: [address],
  });
  let earned = 0;
  if (data && data !== "0x") {
    try {
      earned = wholeGold(JSON.parse(hexToString(data)).earned);
    } catch {
      earned = 0; // unreadable saves are worth nothing
    }
  }
  return {
    runId: Number(runId),
    runStartedAt: Number(runStartedAt),
    savedAt: Number(savedAt),
    saveCount: Number(saveCount),
    hasSave: Boolean(data && data !== "0x"),
    earned,
  };
}

// everything the ledger needs to decide how much gold this wallet may exchange
async function ledgerRequest(config, address) {
  const save = await readSave(config, address);
  const nowSeconds = Math.floor(Date.now() / 1000);
  const elapsed = save.runStartedAt ? Math.max(0, nowSeconds - save.runStartedAt) : 0;
  const unlocked = Math.floor((config.goldPerMinute * elapsed) / 60);
  return {
    save,
    elapsed,
    unlocked,
    payload: {
      address,
      token: config.token,
      runId: save.runId,
      earned: save.earned,
      saveCount: save.saveCount,
      hasSave: save.hasSave,
      unlocked,
      day: new Date().toISOString().slice(0, 10),
      now: Date.now(),
      caps: { run: config.runGoldLimit, wallet: config.walletCapGold, daily: config.dailyCapGold },
    },
  };
}

// seconds until the next gold unlocks, when time is what holds it back
function nextGoldIn(config, request, rooms) {
  if (config.goldPerMinute <= 0 || rooms.time >= rooms.run) return 0;
  return Math.max(1, Math.ceil(((request.unlocked + 1) * 60) / config.goldPerMinute - request.elapsed));
}

function limitMessage(reason, wait) {
  switch (reason) {
    case "save":
      return "Save your game at a checkpoint first: Nova only trades gold that's in your on-chain save.";
    case "stale":
      return "Save at a checkpoint first: each save can be exchanged once, so Nova needs a save made after your last exchange.";
    case "run":
      return "You've exchanged all the gold saved on this journey. Earn more, save at a checkpoint, and come back.";
    case "time":
      return wait
        ? `Easy there! Gold unlocks for exchange as you play. More in ${Math.ceil(wait / 60)} min.`
        : "Gold unlocks for exchange as you play. Come back a little later.";
    case "wallet":
      return "This wallet has reached its exchange limit.";
    case "daily":
      return "Today's exchange budget is used up. Come back tomorrow!";
    default:
      return "You have no gold to exchange.";
  }
}

// the tightest limit; on a tie the permanent ones win, then the ones a player can fix
function tightest(rooms, wanted) {
  let reason = null;
  let best = wanted;
  for (const name of ["wallet", "daily", "save", "stale", "run", "time"]) {
    if (rooms[name] !== null && rooms[name] !== undefined && rooms[name] < best) {
      best = rooms[name];
      reason = name;
    }
  }
  return reason;
}

async function handleChallenge(request, env, config) {
  const body = await readJson(request);
  if (!body || !isAddress(body.address || "")) return fail("A valid wallet address is required.");
  const address = getAddress(body.address);
  const message = challengeMessage(address, config.chainId, randomNonce(), new Date().toISOString());
  await ledger(env, { op: "challenge", address, message, now: Date.now() });
  return json({ ok: true, message });
}

async function handleAccount(url, env, config) {
  const address = url.searchParams.get("address") || "";
  if (!isAddress(address)) return fail("A valid wallet address is required.");
  let ask;
  try {
    ask = await ledgerRequest(config, getAddress(address));
  } catch {
    return fail("Couldn't read your save from the chain. Try again in a moment.", 503);
  }
  const account = await ledger(env, { op: "account", ...ask.payload });
  const reason = account.available > 0 ? null : tightest(account.rooms, Infinity);
  const wait = nextGoldIn(config, ask, account.rooms);
  return json({
    ok: true,
    creditedGold: account.credited,
    remainingGold: account.rooms.wallet,
    creditedAmount: goldToAmount(account.credited, config).toString(),
    runId: ask.save.runId,
    hasSave: ask.save.hasSave,
    earnedGold: ask.save.earned,
    exchangedRunGold: account.exchangedRun,
    availableGold: account.available,
    limitedBy: reason,
    limitMessage: reason ? limitMessage(reason, wait) : "",
    nextGoldIn: wait,
  });
}

async function handleRedeem(request, env, config) {
  const body = await readJson(request);
  if (!body) return fail("Invalid request.");
  if (!isAddress(body.address || "")) return fail("A valid wallet address is required.");
  if (!isHex(body.signature || "")) return fail("A wallet signature is required.");
  const gold = Number(body.gold);
  if (!Number.isInteger(gold) || gold < 0 || gold > MAX_GOLD_PER_REQUEST) return fail("Invalid gold amount.");

  const address = getAddress(body.address);
  const { message } = await ledger(env, { op: "getChallenge", address, now: Date.now() });
  if (!message) return fail("Your sign-in expired. Please try again.", 401);

  let valid = false;
  try {
    valid = await verifyMessage({ address, message, signature: body.signature });
  } catch {
    valid = false;
  }
  if (!valid) return fail("The wallet signature did not match.", 401);

  let ask;
  try {
    ask = await ledgerRequest(config, address);
  } catch {
    return fail("Couldn't read your save from the chain. Try again in a moment.", 503);
  }
  // before anything is booked: the voucher must be signable
  let domain;
  try {
    domain = await rewardsDomain(config);
  } catch {
    return fail("Couldn't reach the rewards contract. Try again in a moment.", 503);
  }

  // the ledger uses up the challenge and books the exchange in one step
  const result = await ledger(env, { op: "redeem", ...ask.payload, message, gold });
  if (!result.ok) return fail(result.error, result.status || 400);

  const grant = result.grant;
  const limitedBy = grant < gold ? tightest(result.rooms, gold) || "run" : null;
  const cumulativeGold = result.credited;
  if (cumulativeGold <= 0) {
    const reason = limitedBy || "none";
    const status = reason === "daily" ? 429 : reason === "wallet" ? 403 : 400;
    return fail(limitMessage(reason, nextGoldIn(config, ask, result.rooms)), status);
  }

  const cumulativeAmount = goldToAmount(cumulativeGold, config);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + config.voucherTtl);
  const signer = privateKeyToAccount(signerKey(env));
  const signature = await signer.signTypedData({
    domain,
    types: {
      Claim: [
        { name: "recipient", type: "address" },
        { name: "token", type: "address" },
        { name: "cumulativeAmount", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    },
    primaryType: "Claim",
    message: { recipient: address, token: config.token, cumulativeAmount, deadline },
  });

  return json({
    ok: true,
    grantedGold: grant,
    limitedBy,
    limitMessage: limitedBy ? limitMessage(limitedBy, nextGoldIn(config, ask, result.rooms)) : "",
    walletCapGold: config.walletCapGold,
    creditedGold: cumulativeGold,
    exchangedRunGold: result.exchangedRun,
    cumulativeAmount: cumulativeAmount.toString(),
    deadline: deadline.toString(),
    signature,
    contract: config.contract,
    token: config.token,
    chainId: config.chainId,
  });
}

// Routes: GET config, GET account?address=, POST challenge, POST redeem
export async function handleHemiApi(request, env, route) {
  const config = readConfig(env);
  const url = new URL(request.url);

  if (route === "config" && request.method === "GET") return json(publicConfig(config));
  if (config.missing.length) return fail("The Hemi Exchange is not configured on this server.", 503);

  if (route === "account" && request.method === "GET") return handleAccount(url, env, config);
  if (route === "challenge" && request.method === "POST") return handleChallenge(request, env, config);
  if (route === "redeem" && request.method === "POST") return handleRedeem(request, env, config);
  return fail("Not found", 404);
}
