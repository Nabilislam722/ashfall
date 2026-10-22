// Wallet network switching and disconnecting in web/bridge.js, with a scripted
// wallet and no exchange server (offline or not set up yet). No chain needed:
//
//   node tests/wallet-network.test.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const BRIDGE = readFileSync(new URL("../web/bridge.js", import.meta.url), "utf8");
const ACCOUNT = "0x1234567890abcdef1234567890abcdef12345678";
const HEMI = 43111;

function makeWallet({ chain = 1, knowsHemi = true, rejectSwitch = false, revoke = true } = {}) {
  const listeners = {};
  const wallet = {
    chain, knowsHemi, rejectSwitch, revoke,
    calls: [],
    added: null,
    connected: false,
    emit(event, value) { (listeners[event] || []).forEach((fn) => fn(value)); },
    on(event, fn) { (listeners[event] = listeners[event] || []).push(fn); },
    async request({ method, params = [] }) {
      wallet.calls.push(method);
      switch (method) {
        case "eth_requestAccounts":
          wallet.connected = true;
          return [ACCOUNT];
        case "eth_accounts":
          return wallet.connected ? [ACCOUNT] : [];
        case "eth_chainId":
          return "0x" + wallet.chain.toString(16);
        case "wallet_switchEthereumChain": {
          if (wallet.rejectSwitch) throw Object.assign(new Error("User rejected the request."), { code: 4001 });
          const id = parseInt(params[0].chainId, 16);
          if (id === HEMI && !wallet.knowsHemi) throw Object.assign(new Error("Unrecognized chain ID"), { code: 4902 });
          wallet.chain = id;
          wallet.emit("chainChanged", params[0].chainId);
          return null;
        }
        case "wallet_addEthereumChain":
          wallet.added = params[0];
          wallet.knowsHemi = true;
          return null; // this wallet adds without switching, like some do
        case "wallet_revokePermissions":
          if (!wallet.revoke) throw Object.assign(new Error("unsupported"), { code: 4200 });
          wallet.connected = false;
          wallet.emit("accountsChanged", []);
          return null;
        default:
          throw Object.assign(new Error("unsupported " + method), { code: 4200 });
      }
    },
  };
  return wallet;
}

function makeStorage() {
  const data = new Map();
  return {
    getItem: (key) => (data.has(key) ? data.get(key) : null),
    setItem: (key, value) => data.set(key, String(value)),
    removeItem: (key) => data.delete(key),
  };
}

// the exchange server: "offline" (no API at all) or "closed" (up, but no contract yet)
function makeFetch(mode) {
  return async () => {
    if (mode === "offline") return new Response("<html>not found</html>", { status: 404 });
    return new Response(JSON.stringify({
      ok: true, configured: false, chainId: HEMI, chainName: "Hemi",
      rpcUrl: "https://rpc.hemi.network/rpc", explorerUrl: "https://explorer.hemi.xyz",
      symbol: "HEMI", decimals: 18, goldPerToken: 10, walletCapGold: 500,
    }), { headers: { "content-type": "application/json" } });
  };
}

function loadBridge(wallet, server, storage = makeStorage()) {
  const window = { ethereum: wallet, localStorage: storage };
  const context = vm.createContext({
    window, URLSearchParams, TextEncoder, BigInt, Promise, setTimeout, console, fetch: makeFetch(server),
  });
  vm.runInContext(BRIDGE, context);
  const bridge = window.ashfallBridge;
  bridge.run = async (action) => {
    assert.equal(bridge.start(action), "ok", action + " did not start");
    for (let i = 0; i < 400 && bridge.getState().state === "working"; i++) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    return bridge.getState();
  };
  return { bridge, storage };
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log("ok  " + name);
}

for (const server of ["offline", "closed"]) {
  await test(`connect switches an Ethereum wallet to Hemi (exchange ${server})`, async () => {
    const wallet = makeWallet({ chain: 1 });
    const { bridge } = loadBridge(wallet, server);
    const s = await bridge.run("connect");
    assert.equal(s.address, ACCOUNT);
    assert.equal(wallet.chain, HEMI);
    assert.equal(s.walletChain, "Hemi");
    assert.equal(s.rightChain, "1");
    assert.ok(wallet.calls.includes("wallet_switchEthereumChain"));
  });
}

await test("a wallet without Hemi gets it added with the right details", async () => {
  const wallet = makeWallet({ chain: 1, knowsHemi: false });
  const { bridge } = loadBridge(wallet, "offline");
  const s = await bridge.run("connect");
  // (JSON round trip: the object comes from the sandbox realm)
  assert.deepEqual(JSON.parse(JSON.stringify(
    { chainId: wallet.added.chainId, chainName: wallet.added.chainName, nativeCurrency: wallet.added.nativeCurrency,
      rpcUrls: wallet.added.rpcUrls, blockExplorerUrls: wallet.added.blockExplorerUrls })),
    { chainId: "0xa867", chainName: "Hemi", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: ["https://rpc.hemi.network/rpc"], blockExplorerUrls: ["https://explorer.hemi.xyz"] });
  assert.equal(wallet.chain, HEMI, "should switch after adding");
  assert.equal(s.rightChain, "1");
});

await test("declining the switch stays connected on Ethereum, Switch fixes it later", async () => {
  const wallet = makeWallet({ chain: 1, rejectSwitch: true });
  const { bridge } = loadBridge(wallet, "offline");
  let s = await bridge.run("connect");
  assert.equal(s.address, ACCOUNT);
  assert.equal(s.walletChain, "Ethereum");
  assert.equal(s.rightChain, "0");
  assert.match(s.exchange, /still on Ethereum/);

  wallet.rejectSwitch = false;
  s = await bridge.run("switch");
  assert.equal(s.state, "connected");
  assert.equal(wallet.chain, HEMI);
  assert.equal(s.rightChain, "1");
  assert.doesNotMatch(s.exchange, /still on/);
});

await test("switching networks in the wallet itself updates the state", async () => {
  const wallet = makeWallet({ chain: HEMI });
  const { bridge } = loadBridge(wallet, "offline");
  await bridge.run("connect");
  wallet.chain = 1;
  wallet.emit("chainChanged", "0x1");
  assert.equal(bridge.getState().walletChain, "Ethereum");
  assert.equal(bridge.getState().rightChain, "0");
});

await test("disconnect revokes the site permission and stays disconnected", async () => {
  const wallet = makeWallet({ chain: HEMI });
  const storage = makeStorage();
  const { bridge } = loadBridge(wallet, "offline", storage);
  await bridge.run("connect");
  let s = await bridge.run("disconnect");
  assert.ok(wallet.calls.includes("wallet_revokePermissions"));
  assert.equal(s.address, "");
  assert.equal(s.walletChain, "");
  assert.equal(s.state, "idle");
});

await test("a wallet without revoke support is still forgotten, also after a reload", async () => {
  const wallet = makeWallet({ chain: HEMI, revoke: false });
  const storage = makeStorage();
  let { bridge } = loadBridge(wallet, "offline", storage);
  await bridge.run("connect");
  let s = await bridge.run("disconnect");
  assert.equal(s.address, "");

  // the wallet still reports the account, but the page doesn't pick it back up
  s = await bridge.run("status");
  assert.equal(s.address, "", "status should not reconnect after Disconnect");
  wallet.emit("accountsChanged", [ACCOUNT]);
  assert.equal(bridge.getState().address, "", "account events should not reconnect either");

  ({ bridge } = loadBridge(wallet, "offline", storage)); // page reload
  s = await bridge.run("status");
  assert.equal(s.address, "", "reloading should not reconnect after Disconnect");

  s = await bridge.run("connect");
  assert.equal(s.address, ACCOUNT, "Connect works again");
  ({ bridge } = loadBridge(wallet, "offline", storage));
  s = await bridge.run("status");
  assert.equal(s.address, ACCOUNT, "after Connect, a reload picks the wallet up again");
});

console.log(`\n${passed} wallet network tests passed`);
