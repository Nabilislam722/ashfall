// The Hemi Exchange ledger against replay and double-spend attempts, with
// plain node (no chain: the save contract's getSave comes from a fake RPC, and
// the Durable Object runs in memory, one request at a time like the real one).
//
//   node tests/exchange-ledger.test.mjs
import assert from "node:assert/strict";
import { encodeAbiParameters, getAddress, recoverTypedDataAddress, stringToHex } from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const worker = (await import(new URL("../cloudflare/worker.js", import.meta.url).href)).default;
const { ExchangeLedger } = await import(new URL("../cloudflare/ledger.js", import.meta.url).href);

const RPC = "http://fake-rpc.test/";
const NOW = Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------- fake chain: one save per wallet
const saves = new Map(); // address -> { runId, startedAt, count, data }
function setSave(player, slot) {
  saves.set(player.address.toLowerCase(), slot);
}

// ---------------------------------------------------------------- in-memory Durable Object
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
      // a Durable Object handles one request at a time
      const run = queue.then(() => instance.fetch(new Request(url, init)));
      queue = run.catch(() => {});
      return run;
    },
  };
  return { idFromName: () => "ledger", get: () => stub };
}

const env = {
  HEMI_CHAIN_ID: "43111", HEMI_RPC_URL: RPC,
  REWARDS_CONTRACT: "0x00000000000000000000000000000000000000a1",
  SAVES_CONTRACT: "0x00000000000000000000000000000000000000a2",
  REWARD_TOKEN: "0x00000000000000000000000000000000000000a3",
  REWARD_TOKEN_SYMBOL: "HEMI", GOLD_PER_TOKEN: "10", WALLET_CAP_GOLD: "500", DAILY_CAP_GOLD: "20000",
  RUN_GOLD_LIMIT: "200", GOLD_PER_MINUTE: "10",
  SIGNER_PRIVATE_KEY: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  LEDGER: memoryDurableObject(ExchangeLedger),
  ASSETS: { fetch: async () => new Response("asset") },
};

const realFetch = globalThis.fetch;
globalThis.fetch = async (url, options = {}) => {
  if (String(url).startsWith(RPC)) {
    const body = JSON.parse(options.body);
    const calls = Array.isArray(body) ? body : [body];
    const answers = calls.map((call) => {
      if (call.params[0].to.toLowerCase() === env.REWARDS_CONTRACT) {
        // the rewards contract's eip712Domain()
        const result = encodeAbiParameters(
          [{ type: "bytes1" }, { type: "string" }, { type: "string" }, { type: "uint256" }, { type: "address" }, { type: "bytes32" }, { type: "uint256[]" }],
          ["0x0f", "AshfallRewards", "2", 43111n, env.REWARDS_CONTRACT, "0x" + "00".repeat(32), []]);
        return { jsonrpc: "2.0", id: call.id, result };
      }
      const address = "0x" + call.params[0].data.slice(-40);
      const s = saves.get(address.toLowerCase()) || { runId: 0, startedAt: 0, count: 0, data: null };
      const result = encodeAbiParameters(
        [{ type: "uint64" }, { type: "uint64" }, { type: "uint64" }, { type: "uint64" }, { type: "bytes" }],
        [BigInt(s.runId), BigInt(s.startedAt), BigInt(s.startedAt ? s.startedAt + 60 : 0), BigInt(s.count),
         s.data ? stringToHex(JSON.stringify(s.data)) : "0x"]);
      return { jsonrpc: "2.0", id: call.id, result };
    });
    return new Response(JSON.stringify(Array.isArray(body) ? answers : answers[0]));
  }
  return worker.fetch(new Request(new URL(url, "https://example.test/game/"), options), env);
};

const api = async (path, body) =>
  (await globalThis.fetch("api/hemi/" + path, body ? { method: "POST", body: JSON.stringify(body) } : {})).json();

async function signIn(player) {
  const { message } = await api("challenge", { address: player.address });
  return player.signMessage({ message });
}

async function exchange(player, gold) {
  const signature = await signIn(player);
  return api("redeem", { address: player.address, gold, signature });
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log("ok  " + name);
}

// ---------------------------------------------------------------- the reported exploit
await test("the reported loop: the same save can't be exchanged twice", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 160, gold: 160, exchanged: 0 } });
  const first = await exchange(player, 160);
  assert.equal(first.grantedGold, 160);
  for (let i = 0; i < 3; i++) {
    // "exit, rejoin at the checkpoint, exchange again": same on-chain save
    const again = await exchange(player, 160);
    assert.ok(!again.ok || again.grantedGold === 0, "a repeat must not grant more gold");
    if (again.ok) assert.equal(again.creditedGold, 160, "the total credit must not grow");
    assert.match(again.limitMessage || again.error, /Save at a checkpoint first/);
  }
});

await test("a newer save after the exchange still only holds what was earned", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 160, gold: 160, exchanged: 0 } });
  assert.equal((await exchange(player, 160)).grantedGold, 160);
  // saved again, nothing new earned
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 2, data: { v: 1, earned: 160, gold: 0, exchanged: 160 } });
  const nothing = await exchange(player, 160);
  assert.ok(!nothing.ok || nothing.grantedGold === 0);
  // earned 40 more and saved: exactly those 40 can be exchanged
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 3, data: { v: 1, earned: 200, gold: 40, exchanged: 160 } });
  const more = await exchange(player, 160);
  assert.equal(more.grantedGold, 40);
  assert.equal(more.creditedGold, 200);
});

await test("one signed request sent many times at once is booked once", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 160, gold: 160, exchanged: 0 } });
  const signature = await signIn(player);
  const results = await Promise.all(Array.from({ length: 8 }, () => api("redeem", { address: player.address, gold: 160, signature })));
  const granted = results.reduce((sum, r) => sum + (r.ok ? r.grantedGold : 0), 0);
  assert.equal(granted, 160, "only one of the parallel requests may count");
  assert.equal(results.filter((r) => r.ok).length, 1);
});

await test("a used sign-in can't be replayed later", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 100, gold: 100, exchanged: 0 } });
  const signature = await signIn(player);
  assert.equal((await api("redeem", { address: player.address, gold: 50, signature })).grantedGold, 50);
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 2, data: { v: 1, earned: 100, gold: 50, exchanged: 50 } });
  const replay = await api("redeem", { address: player.address, gold: 50, signature });
  assert.equal(replay.ok, false);
  assert.match(replay.error, /sign-in expired/);
});

await test("New Game opens a new journey, but the wallet cap still counts everything", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  let credited = 0;
  for (let run = 1; run <= 4; run++) {
    // a cheater writes the biggest save the rules allow, every journey
    setSave(player, { runId: run, startedAt: NOW - 7200, count: 1, data: { v: 1, earned: 999, gold: 999, exchanged: 0 } });
    const r = await exchange(player, 999);
    if (r.ok) credited = r.creditedGold;
  }
  assert.equal(credited, 500, "never more than WALLET_CAP_GOLD per wallet");
  const after = await exchange(player, 999);
  assert.ok(!after.ok || after.grantedGold === 0);
});

await test("gold unlocks with time since the journey began", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 120, count: 1, data: { v: 1, earned: 160, gold: 160, exchanged: 0 } });
  const early = await exchange(player, 160);
  assert.equal(early.grantedGold, 20, "two minutes in, only 20 gold has unlocked");
});

await test("the account view reports the save rule", async () => {
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 80, gold: 80, exchanged: 0 } });
  await exchange(player, 80);
  const account = await api("account?address=" + player.address);
  assert.equal(account.availableGold, 0);
  assert.equal(account.limitedBy, "stale");
  assert.equal(account.exchangedRunGold, 80);
});

await test("the signer key works pasted without 0x, and a broken one keeps the exchange closed", async () => {
  const key = env.SIGNER_PRIVATE_KEY;
  env.SIGNER_PRIVATE_KEY = key.slice(2);
  const player = privateKeyToAccount(generatePrivateKey());
  setSave(player, { runId: 1, startedAt: NOW - 3600, count: 1, data: { v: 1, earned: 30, gold: 30, exchanged: 0 } });
  const voucher = await exchange(player, 30);
  const signer = await recoverTypedDataAddress({
    domain: { name: "AshfallRewards", version: "2", chainId: 43111, verifyingContract: getAddress(env.REWARDS_CONTRACT) },
    types: { Claim: [{ name: "recipient", type: "address" }, { name: "token", type: "address" }, { name: "cumulativeAmount", type: "uint256" }, { name: "deadline", type: "uint256" }] },
    primaryType: "Claim",
    message: { recipient: player.address, token: getAddress(env.REWARD_TOKEN), cumulativeAmount: BigInt(voucher.cumulativeAmount), deadline: BigInt(voucher.deadline) },
    signature: voucher.signature,
  });
  assert.equal(signer, privateKeyToAccount(key).address);
  env.SIGNER_PRIVATE_KEY = "0x1234";
  const config = await api("config");
  assert.equal(config.configured, false);
  assert.deepEqual(config.missing, ["SIGNER_PRIVATE_KEY"]);
  env.SIGNER_PRIVATE_KEY = key;
});

globalThis.fetch = realFetch;
console.log(`\n${passed} exchange ledger tests passed`);
