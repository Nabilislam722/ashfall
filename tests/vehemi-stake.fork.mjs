// Staking at the Mana Well against the real veHemi and HEMI contracts, on a
// local fork of Hemi mainnet (nothing touches the real network):
//
//   anvil --fork-url https://rpc.hemi.network/rpc
//   node tests/vehemi-stake.fork.mjs
//
// The test borrows HEMI from a large holder on the fork (anvil impersonation),
// then runs the real web/bridge.js: read veHEMI, refuse bad stakes, approve +
// createLock, and read the new veHEMI power.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const RPC = "http://127.0.0.1:8545";
const HEMI = "0x99e3dE3817F6081B2568208337ef83295b7f591D";
const VEHEMI = "0x371d3718D5b7F75EAb050FAe6Da7DF3092031c89";
const HOLDER = "0xea03D0E996D2C9546Da7400D8bDA9B84eE965782"; // large HEMI holder on mainnet
const PLAYER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; // anvil dev account 0 (unlocked on the fork)

async function rpc(method, params = []) {
  const response = await fetch(RPC, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const body = await response.json();
  if (body.error) throw Object.assign(new Error(body.error.message), { code: body.error.code });
  return body.result;
}

assert.equal(parseInt(await rpc("eth_chainId"), 16), 43111, "run anvil with --fork-url https://rpc.hemi.network/rpc");

// give the player 1,000 HEMI from the holder
await rpc("anvil_impersonateAccount", [HOLDER]);
await rpc("anvil_setBalance", [HOLDER, "0x56BC75E2D63100000"]);
const amount = (1000n * 10n ** 18n).toString(16).padStart(64, "0");
const transfer = "0xa9059cbb" + PLAYER.slice(2).toLowerCase().padStart(64, "0") + amount;
const hash = await rpc("eth_sendTransaction", [{ from: HOLDER, to: HEMI, data: transfer }]);
assert.equal((await rpc("eth_getTransactionReceipt", [hash])).status, "0x1");

// the page: real bridge.js, a wallet that forwards to the fork, a game server with the exchange closed
const wallet = {
  on() {},
  async request({ method, params = [] }) {
    if (method === "eth_requestAccounts" || method === "eth_accounts") return [PLAYER];
    if (method === "wallet_switchEthereumChain") return null;
    return rpc(method, params);
  },
};
const pageFetch = async (url, options) => {
  if (/^https?:\/\//.test(url)) return fetch(url, options);
  if (String(url).endsWith("config")) {
    return new Response(JSON.stringify({ ok: true, configured: false, chainId: 43111, chainName: "Hemi", rpcUrl: RPC,
      explorerUrl: "https://explorer.hemi.xyz", savesContract: null, veHemi: VEHEMI, symbol: "HEMI", decimals: 18 }));
  }
  return new Response(JSON.stringify({ ok: false, error: "closed" }), { status: 503 });
};
const window = { ethereum: wallet };
vm.runInContext(readFileSync(new URL("../web/bridge.js", import.meta.url), "utf8"), vm.createContext({
  window, URLSearchParams, TextEncoder, TextDecoder, BigInt, Promise, setTimeout, console, fetch: pageFetch,
}));
const bridge = window.ashfallBridge;
async function run(action, query = "") {
  assert.equal(bridge.start(action, query), "ok");
  for (let i = 0; i < 600 && bridge.getState().state === "working"; i++) await new Promise((r) => setTimeout(r, 50));
  return bridge.getState();
}

let s = await run("connect");
console.log("1. connected", s.address, "| staking", s.staking, "| veHEMI", s.vePower, "locks", s.veLocks, "| HEMI", s.hemiBalance);
assert.equal(s.staking, "1");
assert.equal(s.vePower, "0");
assert.equal(s.hemiBalance, "1000");

for (const [query, expected] of [["amount=5&days=365", /at least 10 HEMI/], ["amount=100&days=7", /13 days/],
                                 ["amount=5000&days=365", /only has 1000 HEMI/]]) {
  s = await run("stake", query);
  console.log("2. refused", query, "->", s.error);
  assert.equal(s.state, "error");
  assert.match(s.error, expected);
}

s = await run("stake", "amount=100&days=365");
console.log("3. staked:", s.state, "|", s.step || s.error, "| veHEMI", s.vePower, "locks", s.veLocks, "| HEMI left", s.hemiBalance);
assert.equal(s.state, "done");
assert.equal(s.veLocks, "1");
assert.equal(s.hemiBalance, "900");
const power = Number(s.vePower);
assert.ok(power > 20 && power < 25.1, "1 year of 100 HEMI is about 25 veHEMI, got " + power);

s = await run("stake", "amount=10&days=1461");
console.log("4. a second, 4-year lock:", s.state, "| veHEMI", s.vePower, "locks", s.veLocks);
assert.equal(s.veLocks, "2");
assert.ok(Number(s.vePower) > power + 9, "4 years of 10 HEMI adds about 10 veHEMI");

console.log("VEHEMI STAKING CHECKS PASSED");
