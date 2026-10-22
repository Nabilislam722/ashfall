// End-to-end test of the Hemi Exchange and on-chain saves: the real web/bridge.js,
// the real Worker API (cloudflare/) and the real contracts, against a local anvil
// chain. Nothing touches a real network.
//
//   anvil --chain-id 743111
//   cd contracts
//   REWARDS_SIGNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 forge script script/Deploy.s.sol \
//     --rpc-url http://127.0.0.1:8545 --broadcast \
//     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
//   cd .. && node tests/hemi-exchange.e2e.mjs <rewards contract> <test token> <saves contract> [player key] [cancel]
//
// (the keys above are anvil's public development keys, never use them elsewhere)
//
// Against a fork of Hemi mainnet with the real HEMI token instead:
//   anvil --fork-url https://rpc.hemi.network/rpc
//   deploy as above (REWARD_TOKEN defaults to HEMI on chain 43111), send the
//   rewards contract some HEMI from an impersonated holder, then
//   E2E_CHAIN_ID=43111 E2E_SYMBOL=HEMI node tests/hemi-exchange.e2e.mjs <rewards> 0x99e3dE3817F6081B2568208337ef83295b7f591D <saves>
//
// The Worker's clock is moved forward in-process to test that a run's gold only
// unlocks for exchange over time (GOLD_PER_MINUTE).
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const ROOT = new URL("../", import.meta.url).href;
const { createWalletClient, createPublicClient, http, parseAbi, formatUnits } = await import("viem");
const { privateKeyToAccount } = await import("viem/accounts");
const worker = (await import(ROOT + "cloudflare/worker.js")).default;
const { ExchangeLedger } = await import(ROOT + "cloudflare/ledger.js");

const RPC = "http://127.0.0.1:8545";
const CONTRACT = process.argv[2];
const TOKEN = process.argv[3];
const SAVES = process.argv[4];
const SIGNER_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const PLAYER_KEY = process.argv[5] || "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc79be2a6aecc8e1c8";
const CANCEL = process.argv[6] === "cancel";
const CHAIN_ID = Number(process.env.E2E_CHAIN_ID || 743111);
const SYMBOL = process.env.E2E_SYMBOL || "tHEMI";
assert.ok(CONTRACT && TOKEN && SAVES, "usage: node tests/hemi-exchange.e2e.mjs <rewards> <token> <saves> [player key] [cancel]");

const chain = { id: CHAIN_ID, name: "local", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } };
const realFetch = globalThis.fetch;
const publicClient = createPublicClient({ chain, transport: http(RPC, { fetchFn: realFetch }) });
const player = privateKeyToAccount(PLAYER_KEY);
const walletClient = createWalletClient({ account: player, chain, transport: http(RPC, { fetchFn: realFetch }) });
// give the test player some gas money from anvil's first dev account
{
  const funder = createWalletClient({ account: privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"), chain, transport: http(RPC, { fetchFn: realFetch }) });
  const hash = await funder.sendTransaction({ to: player.address, value: 10n ** 18n });
  await publicClient.waitForTransactionReceipt({ hash });
}
const erc20 = parseAbi(["function balanceOf(address) view returns (uint256)"]);

// the Worker's clock, moved forward to let a run's gold unlock
const realNow = Date.now;
let clockOffset = 0;
Date.now = () => realNow() + clockOffset;
const waitMinutes = (minutes) => { clockOffset += minutes * 60_000; };

// ------------------------------------------------------------ server side
// the ledger Durable Object, in memory: one request at a time, like the real one
function memoryDurableObject(Klass) {
  const data = new Map();
  const storage = {
    async get(key) { return data.has(key) ? structuredClone(data.get(key)) : undefined; },
    async put(key, value) { data.set(key, structuredClone(value)); },
    async delete(key) { return data.delete(key); },
  };
  const instance = new Klass({ storage }, {});
  let queue = Promise.resolve();
  const stub = {
    fetch(url, init) {
      const run = queue.then(() => instance.fetch(new Request(url, init)));
      queue = run.catch(() => {});
      return run;
    },
  };
  return { idFromName: () => "ledger", get: () => stub };
}

const env = {
  HEMI_CHAIN_ID: String(CHAIN_ID),
  HEMI_RPC_URL: RPC,
  REWARDS_CONTRACT: CONTRACT,
  SAVES_CONTRACT: SAVES,
  REWARD_TOKEN: TOKEN,
  REWARD_TOKEN_SYMBOL: SYMBOL,
  REWARD_TOKEN_DECIMALS: "18",
  GOLD_PER_TOKEN: "10",
  WALLET_CAP_GOLD: "300",
  DAILY_CAP_GOLD: "50000",
  RUN_GOLD_LIMIT: "200",
  GOLD_PER_MINUTE: "10",
  VOUCHER_TTL_SECONDS: "900",
  SIGNER_PRIVATE_KEY: SIGNER_KEY,
  LEDGER: memoryDurableObject(ExchangeLedger),
  ASSETS: { fetch: async () => new Response("asset") },
};

// the page lives at /game/, so relative "api/hemi/..." goes to the Worker;
// absolute URLs (the chain's RPC) go out for real
globalThis.fetch = async (url, options = {}) => {
  if (typeof url === "string" && /^https?:\/\//.test(url)) return realFetch(url, options);
  const request = new Request(new URL(url, "https://example.test/game/"), options);
  return worker.fetch(request, env);
};

// ------------------------------------------------------------ browser wallet
const walletLog = [];
let rejectNextTransaction = false;
let walletChain = 1; // start on the wrong network to exercise switching
const provider = {
  async request({ method, params = [] }) {
    walletLog.push(method);
    switch (method) {
      case "eth_requestAccounts":
        return [player.address];
      case "eth_accounts":
        return [player.address];
      case "eth_chainId":
        return "0x" + walletChain.toString(16);
      case "wallet_switchEthereumChain":
        if (walletChain !== CHAIN_ID && !provider.added) {
          const error = new Error("Unrecognized chain ID");
          error.code = 4902;
          throw error;
        }
        walletChain = parseInt(params[0].chainId, 16);
        return null;
      case "wallet_addEthereumChain":
        provider.added = params[0];
        walletChain = parseInt(params[0].chainId, 16);
        return null;
      case "personal_sign":
        return player.signMessage({ message: { raw: params[0] } });
      case "eth_sendTransaction": {
        if (rejectNextTransaction) {
          rejectNextTransaction = false;
          const error = new Error("User rejected the request.");
          error.code = 4001;
          throw error;
        }
        const tx = params[0];
        return walletClient.sendTransaction({ to: tx.to, data: tx.data });
      }
      case "eth_call": {
        const result = await publicClient.call({ to: params[0].to, data: params[0].data });
        return result.data || "0x";
      }
      case "eth_getTransactionReceipt": {
        const receipt = await publicClient.getTransactionReceipt({ hash: params[0] }).catch(() => null);
        if (!receipt) return null;
        return { status: receipt.status === "success" ? "0x1" : "0x0" };
      }
      default:
        throw new Error("mock wallet: unsupported " + method);
    }
  },
};

// ------------------------------------------------------------ load bridge.js as the browser would
const window = { ethereum: provider };
const context = vm.createContext({
  window, URLSearchParams, TextEncoder, TextDecoder, BigInt, Promise, setTimeout, console, fetch: globalThis.fetch,
});
vm.runInContext(readFileSync(new URL(ROOT + "web/bridge.js"), "utf8"), context);
const bridge = window.ashfallBridge;

const poll = () => Object.fromEntries(new URLSearchParams(bridge.poll()));
async function run(action, query = "") {
  assert.equal(bridge.start(action, query), "ok", action + " did not start");
  const start = realNow();
  while (realNow() - start < 60000) {
    const s = poll();
    if (s.state !== "working") return s;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error("bridge never settled: " + bridge.poll());
}
const balance = async () => formatUnits(await publicClient.readContract({ address: TOKEN, abi: erc20, functionName: "balanceOf", args: [player.address] }), 18);
const saveQuery = (earned, run) => new URLSearchParams({
  data: JSON.stringify({ v: 1, map: "village", cp: "village:plaza", gold: earned, earned, exchanged: 0 }),
  run: String(run),
}).toString();

let s;
if (CANCEL) {
  console.log("C1. connect, save 30 gold on-chain, wait, then cancel the claim transaction");
  await run("connect");
  s = await run("save", saveQuery(30, 0));
  assert.equal(s.state, "done");
  waitMinutes(5);
  rejectNextTransaction = true;
  s = await run("redeem", "gold=30");
  console.log("   ", s.state, "|", s.error, "| granted", s.granted, "seq", s.seq, "| balance", await balance());
  assert.equal(s.state, "error");
  assert.match(s.error, /Cancelled/);
  assert.equal(s.granted, "30");
  console.log("C2. reopen the exchange: the reserved tokens show as pending");
  s = await run("status");
  console.log("    pending", s.pending, s.symbol);
  assert.equal(s.pending, "3");
  console.log("C3. exchange 0 gold to claim what was reserved");
  s = await run("redeem", "gold=0");
  console.log("   ", s.state, "|", s.step, "| granted", s.granted, "seq", s.seq, "| balance", await balance());
  assert.equal(s.state, "done");
  assert.equal(await balance(), "3");
  console.log("CANCEL FLOW PASSED");
  process.exit(0);
}

console.log("1. status before connecting");
s = await run("status");
console.log("  ", s.state, "configured", s.configured, "saves", s.saves, "rate", s.rate, "cap", s.cap, "symbol", s.symbol);
assert.equal(s.configured, "1");
assert.equal(s.saves, "1");

console.log("2. connect (wallet starts on the wrong chain): no save yet");
s = await run("connect");
console.log("  ", s.state, s.address, "chain", s.walletChain, "| save read", s.saveRead, "data", JSON.stringify(s.saveData));
assert.equal(s.state, "connected");
assert.equal(walletChain, CHAIN_ID);
assert.equal(s.saveRead, "1");
assert.equal(s.saveData, "");

console.log("3. exchange without an on-chain save");
s = await run("redeem", "gold=50");
console.log("  ", s.state, "|", s.error, "| seq", s.seq);
assert.equal(s.state, "error");
assert.match(s.error, /checkpoint/);
assert.equal(s.seq, "0");

console.log("4. save on-chain at a checkpoint, claiming 250 gold (more than one run can give)");
s = await run("save", saveQuery(250, 0));
console.log("  ", s.state, "|", s.step, "| run", s.saveRunId, "saves", s.saveCount, "| earned (server)", s.earnedGold, "available", s.available);
assert.equal(s.state, "done");
assert.equal(s.saveRunId, "1");
assert.equal(JSON.parse(s.saveData).earned, 250);
assert.equal(s.earnedGold, "250");

console.log("5. exchange straight away: the run only just started");
s = await run("redeem", "gold=50");
console.log("  ", s.state, "|", s.error);
assert.equal(s.state, "error");
assert.match(s.error, /unlocks/);

console.log("6. six minutes later: 60 gold has unlocked");
waitMinutes(6);
s = await run("redeem", "gold=80");
console.log("  ", s.state, "|", s.step, "| granted", s.granted, "| balance", await balance());
assert.equal(s.state, "done");
assert.equal(s.granted, "60");
assert.equal(await balance(), "6");

console.log("7. much later, after saving again: the run is capped at 200 gold, 140 of it left");
waitMinutes(30);
s = await run("redeem", "gold=500");
console.log("   same save again:", s.state, "|", s.error || s.step);
assert.match(s.error || s.step, /Save at a checkpoint first/);
s = await run("save", saveQuery(250, 1));
assert.equal(s.state, "done");
s = await run("redeem", "gold=500");
console.log("  ", s.state, "|", s.step, "| granted", s.granted, "| balance", await balance());
assert.equal(s.granted, "140");
assert.equal(await balance(), "20");
s = await run("save", saveQuery(250, 1));
s = await run("redeem", "gold=10");
console.log("   again, after another save:", s.state, "|", s.error || s.step);
assert.match(s.error || s.step, /exchanged all the gold saved/);

console.log("8. New Game wipes the save and starts run 2; a stale save for run 1 is refused");
s = await run("newgame");
console.log("  ", s.state, "|", s.step, "| run", s.saveRunId, "data", JSON.stringify(s.saveData));
assert.equal(s.saveRunId, "2");
assert.equal(s.saveData, "");
s = await run("save", saveQuery(999, 1));
console.log("   stale save:", s.state, "|", s.error.slice(0, 80));
assert.equal(s.state, "error");

console.log("9. run 2 earns 150 gold, but the wallet cap (300 gold) still counts run 1");
s = await run("save", saveQuery(150, 2));
assert.equal(s.state, "done");
waitMinutes(20);
s = await run("redeem", "gold=150");
console.log("  ", s.state, "|", s.step, "| granted", s.granted, "| balance", await balance());
assert.equal(s.granted, "100");
assert.equal(await balance(), "30");
s = await run("redeem", "gold=20");
console.log("   again:", s.state, "|", s.error || s.step);
assert.match(s.error || s.step, /limit/);

console.log("10. the account endpoint reports the run");
const acct = await (await globalThis.fetch("api/hemi/account?address=" + player.address)).json();
console.log("    account:", JSON.stringify({ run: acct.runId, earned: acct.earnedGold, exchangedRun: acct.exchangedRunGold, available: acct.availableGold, limitedBy: acct.limitedBy }));
assert.equal(acct.runId, 2);
assert.equal(acct.earnedGold, 150);
assert.equal(acct.exchangedRunGold, 100);
assert.equal(acct.availableGold, 0);
assert.equal(acct.limitedBy, "wallet");

console.log("11. forged request straight to the API with a bad signature");
let response = await globalThis.fetch("api/hemi/challenge", { method: "POST", body: JSON.stringify({ address: player.address }) });
response = await globalThis.fetch("api/hemi/redeem", {
  method: "POST",
  body: JSON.stringify({ address: player.address, gold: 999999, signature: "0x" + "11".repeat(65) }),
});
console.log("  ", response.status, (await response.json()).error);
assert.equal(response.status, 401);

console.log("12. tampered voucher sent straight to the contract");
const callResult = await publicClient.call({
  account: player.address, to: CONTRACT,
  data: bridge._encodeClaim(TOKEN, (10n ** 24n).toString(), (2n ** 40n).toString(), "0x" + "22".repeat(65)),
}).then(() => "accepted?!", (e) => "rejected: " + (e.shortMessage || e.message).split("\n")[0]);
console.log("  ", callResult);
assert.match(callResult, /rejected/);

console.log("ALL E2E CHECKS PASSED");
