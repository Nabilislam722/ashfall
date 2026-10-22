/* Browser side of the Lua <-> JavaScript bridge (see src/utilities/webBridge.lua).
 *
 * Lua cannot wait for promises, so it starts an action with
 *   ashfallBridge.start(action, "key=value&...")
 * and then polls
 *   ashfallBridge.poll()
 * which returns the current state as a URL-encoded string (no newlines).
 *
 * Actions:
 *   connect, status, switch, disconnect  wallet connection (status never pops up the wallet)
 *   redeem   gold=N        Hemi Exchange: sign a free challenge, get a voucher from the game
 *                          server, send the claim transaction to AshfallRewards
 *   loadsave               read the wallet's slot from AshfallSaves
 *   save     data=[, run=] write the game to the wallet's slot (a transaction); without
 *                          run= it saves into the wallet's current run
 *   newgame                wipe the slot and start a new run (a transaction)
 *   vepower                read the wallet's veHEMI power and HEMI balance
 *   stake    amount=, days=  lock HEMI in the official veHemi contract (approve + createLock)
 * No libraries are needed: contract calls are ABI-encoded by hand. Reads go to the
 * network's public RPC, so they work whatever network the wallet is on.
 */
(function (global) {
  "use strict";

  var API = "api/hemi/";
  var SEL = {
    claim: "0x2ada8a32",               // claim(address,uint256,uint256,bytes)
    claimed: "0x0c9cbf0e",             // claimed(address,address)
    save: "0x7aa49815",                // save(bytes,uint64)
    newGame: "0x7d03f5f3",             // newGame()
    getSave: "0x1b874df5",             // getSave(address)
    balanceOf: "0x70a08231",           // balanceOf(address)
    allowance: "0xdd62ed3e",           // allowance(address,address)
    approve: "0x095ea7b3",             // approve(address,uint256)
    createLock: "0xb52c05fe",          // createLock(uint256,uint256)
    tokenOfOwnerByIndex: "0x2f745c59", // tokenOfOwnerByIndex(address,uint256)
    balanceOfNFT: "0xe7e242d4"         // balanceOfNFT(uint256)
  };
  var RECEIPT_TIMEOUT_MS = 180000;
  var DISCONNECTED_KEY = "ashfall.walletDisconnected";
  var MAX_SAVE_BYTES = 4096;
  var MAX_VE_LOCKS = 30;               // locks summed for veHEMI power
  var MIN_STAKE_HEMI = 10;             // veHemi's MIN_LOCK_AMOUNT
  var MIN_LOCK_DAYS = 13;              // veHemi needs more than 12.2 days
  var MAX_LOCK_DAYS = 1461;            // 4 years of 365.25 days

  // Hemi mainnet. Lets the wallet switch to Hemi even when the exchange server
  // is offline or not set up yet; the server's /config takes over once loaded.
  var DEFAULT_NETWORK = {
    chainId: 43111,
    chainName: "Hemi",
    rpcUrl: "https://rpc.hemi.network/rpc",
    explorerUrl: "https://explorer.hemi.xyz"
  };
  // official contracts per network
  var KNOWN_CONTRACTS = {
    43111: {
      hemi: "0x99e3dE3817F6081B2568208337ef83295b7f591D",
      veHemi: "0x371d3718D5b7F75EAb050FAe6Da7DF3092031c89"
    }
  };

  var config = null;
  var busy = false;
  var state = {
    state: "idle",   // idle | working | connected | done | error
    action: "",      // the action running now, or the last one
    run: "0",        // counts started actions, so the game can tell its own apart
    step: "",
    error: "",
    wallet: global.ethereum ? "1" : "0",
    configured: "",
    exchange: "",    // why the exchange can't be used right now (wallet still works)
    address: "",
    chain: DEFAULT_NETWORK.chainName, // network the exchange runs on
    walletChain: "", // network the wallet is on
    walletChainId: "",
    rightChain: "",  // "1" when the wallet is on the exchange's network, "0" when not
    symbol: "",
    rate: "",
    cap: "",
    credited: "",
    remaining: "",
    available: "",   // gold the exchange would take right now
    limitMessage: "",
    earnedGold: "",
    exchangedRun: "",
    nextGoldIn: "",
    pending: "",
    seq: "0",
    granted: "0",
    amount: "",
    tx: "",
    txUrl: "",
    saves: "",       // "1" when on-chain saves are available
    saveRead: "",    // "1" once the slot of the current wallet has been read
    saveRunId: "",
    saveRunStartedAt: "",
    saveSavedAt: "",
    saveCount: "",
    saveData: "",
    veReady: "",     // "1" once veHEMI power has been read
    vePower: "",
    veLocks: "",
    hemiBalance: "",
    staking: ""      // "1" when staking works on this network
  };
  var seq = 0;
  var runs = 0;

  function set(fields) {
    for (var key in fields) {
      state[key] = fields[key] === undefined || fields[key] === null ? "" : String(fields[key]);
    }
  }

  function encodeState() {
    var params = new URLSearchParams();
    for (var key in state) params.set(key, state[key]);
    return params.toString();
  }

  function clearAccountData() {
    set({
      credited: "", remaining: "", pending: "", amount: "", tx: "", txUrl: "",
      available: "", limitMessage: "", earnedGold: "", exchangedRun: "", nextGoldIn: "",
      saveRead: "", saveRunId: "", saveRunStartedAt: "", saveSavedAt: "", saveCount: "", saveData: "",
      veReady: "", vePower: "", veLocks: "", hemiBalance: ""
    });
  }

  // ---------------------------------------------------------------- helpers

  function pad32(hex) {
    return hex.replace(/^0x/, "").toLowerCase().padStart(64, "0");
  }

  function uint(value) {
    return pad32(BigInt(value).toString(16));
  }

  function padRight(hex) {
    return hex + "0".repeat((64 - (hex.length % 64)) % 64);
  }

  function bytesHex(bytes) {
    var hex = "";
    for (var i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, "0");
    return hex;
  }

  function utf8Hex(text) {
    return "0x" + bytesHex(new TextEncoder().encode(text));
  }

  function encodeClaim(token, cumulativeAmount, deadline, signature) {
    var sig = signature.replace(/^0x/, "");
    // head: token, amount, deadline, offset of the bytes argument (4 words = 0x80)
    return SEL.claim + pad32(token) + uint(cumulativeAmount) + uint(deadline) + uint(128) +
      uint(sig.length / 2) + padRight(sig);
  }

  function encodeSave(text, runId) {
    var data = bytesHex(new TextEncoder().encode(text));
    // head: offset of the bytes argument (2 words = 0x40), runId
    return SEL.save + uint(64) + uint(runId) + uint(data.length / 2) + padRight(data);
  }

  function word(hex, index) {
    return BigInt("0x" + (hex.slice(index * 64, index * 64 + 64) || "0"));
  }

  function decodeSave(result) {
    var hex = result.replace(/^0x/, "");
    var offset = Number(word(hex, 4)) * 2;
    var length = Number(BigInt("0x" + (hex.slice(offset, offset + 64) || "0")));
    var dataHex = hex.slice(offset + 64, offset + 64 + length * 2);
    var bytes = new Uint8Array(length);
    for (var i = 0; i < length; i++) bytes[i] = parseInt(dataHex.slice(i * 2, i * 2 + 2), 16);
    return {
      runId: word(hex, 0),
      runStartedAt: word(hex, 1),
      savedAt: word(hex, 2),
      saveCount: word(hex, 3),
      data: new TextDecoder().decode(bytes)
    };
  }

  function formatUnits(value, decimals) {
    var negative = value < 0n;
    if (negative) value = -value;
    var base = 10n ** BigInt(decimals);
    var whole = value / base;
    var fraction = (value % base).toString().padStart(decimals, "0").slice(0, 4).replace(/0+$/, "");
    return (negative ? "-" : "") + whole.toString() + (fraction ? "." + fraction : "");
  }

  function wallet() {
    return global.ethereum;
  }

  var CHAIN_NAMES = { 1: "Ethereum", 11155111: "Sepolia", 43111: "Hemi", 743111: "Hemi Sepolia" };

  function chainName(id) {
    return CHAIN_NAMES[id] || ("Chain " + id);
  }

  function network() {
    if (config && config.chainId) {
      return {
        chainId: Number(config.chainId),
        chainName: config.chainName,
        rpcUrl: config.rpcUrl,
        explorerUrl: config.explorerUrl
      };
    }
    return DEFAULT_NETWORK;
  }

  function contracts() {
    var known = KNOWN_CONTRACTS[network().chainId] || {};
    return {
      saves: (config && config.savesContract) || "",
      veHemi: (config && config.veHemi) || known.veHemi || "",
      hemi: known.hemi || ""
    };
  }

  // "Disconnect" is remembered, so the page doesn't quietly reconnect on reload
  function rememberDisconnected(value) {
    try {
      if (value) global.localStorage.setItem(DISCONNECTED_KEY, "1");
      else global.localStorage.removeItem(DISCONNECTED_KEY);
    } catch (error) { /* storage blocked: only this visit is affected */ }
  }

  function wasDisconnected() {
    try { return global.localStorage.getItem(DISCONNECTED_KEY) === "1"; } catch (error) { return false; }
  }

  function rpc(method, params) {
    return wallet().request({ method: method, params: params || [] });
  }

  // read-only contract call through the network's public RPC
  async function readCall(to, data) {
    var response = await fetch(network().rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call", params: [{ to: to, data: data }, "latest"] })
    });
    var body = await response.json();
    if (body.error || typeof body.result !== "string") {
      throw new Error((body.error && body.error.message) || "The network didn't answer.");
    }
    return body.result;
  }

  async function readUint(to, data) {
    var result = await readCall(to, data);
    return result === "0x" ? 0n : BigInt(result);
  }

  function sleep(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function friendlyError(error) {
    if (!error) return "Something went wrong.";
    if (error.code === 4001) return "Cancelled in your wallet.";
    if (error.code === -32002) return "Your wallet already has a request open. Check the wallet window.";
    var message = error.shortMessage || error.message || String(error);
    if (/insufficient funds/i.test(message)) return "Your wallet needs a little ETH on Hemi to pay gas.";
    // custom errors from the game's contracts
    if (/0xc99860ec|WrongRun/.test(message)) return "This save belongs to an older journey. Reload the game to continue.";
    if (/0xbe20317e|SaveTooLarge/.test(message)) return "This save is too big to store on-chain.";
    if (/0x157fd87e|VoucherExpired/.test(message)) return "The exchange voucher expired. Please exchange again.";
    if (/0x94403b70|TokenNotAllowed/.test(message)) return "This token isn't being paid out right now.";
    return message.length > 140 ? message.slice(0, 137) + "..." : message;
  }

  async function api(path, body) {
    var options = body
      ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }
      : { method: "GET" };
    var response = await fetch(API + path, options);
    var data = await response.json().catch(function () { return { ok: false, error: "The exchange is offline." }; });
    if (!data.ok) throw new Error(data.error || "The exchange is offline.");
    return data;
  }

  // sends a transaction from the player's wallet and waits until it is mined
  async function sendTransaction(to, data, confirmStep) {
    set({ step: confirmStep });
    var tx = await rpc("eth_sendTransaction", [{ from: state.address, to: to, data: data }]);
    var explorer = network().explorerUrl;
    set({ tx: tx, txUrl: explorer ? explorer + "/tx/" + tx : "", step: "Waiting for the network..." });

    var started = Date.now();
    var receipt = null;
    while (!receipt && Date.now() - started < RECEIPT_TIMEOUT_MS) {
      await sleep(1500);
      receipt = await rpc("eth_getTransactionReceipt", [tx]);
    }
    if (!receipt) throw new Error("Still waiting for the network. Check the transaction in the explorer.");
    if (receipt.status !== "0x1") throw new Error("The transaction failed on the network.");
    return tx;
  }

  // ---------------------------------------------------------------- steps

  async function loadConfig() {
    config = await api("config");
    if (state.walletChainId) setWalletChain(Number(state.walletChainId));
    var c = contracts();
    set({
      configured: config.configured ? "1" : "0",
      chain: config.chainName,
      symbol: config.symbol,
      rate: config.goldPerToken,
      cap: config.walletCapGold,
      saves: c.saves ? "1" : "0",
      staking: c.veHemi && c.hemi ? "1" : "0"
    });
    if (!config.configured) throw new Error("The Hemi Exchange is closed right now.");
  }

  async function ensureChain() {
    var net = network();
    var current = parseInt(await rpc("eth_chainId"), 16);
    if (current === net.chainId) return;
    var chainHex = "0x" + net.chainId.toString(16);
    set({ step: "Switch your wallet to " + net.chainName });
    try {
      await rpc("wallet_switchEthereumChain", [{ chainId: chainHex }]);
    } catch (error) {
      if (error && (error.code === 4902 || /unrecognized|not been added|unknown chain/i.test(error.message || ""))) {
        await rpc("wallet_addEthereumChain", [{
          chainId: chainHex,
          chainName: net.chainName,
          nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
          rpcUrls: [net.rpcUrl],
          blockExplorerUrls: net.explorerUrl ? [net.explorerUrl] : []
        }]);
        // most wallets switch after adding; some need asking again
        if (parseInt(await rpc("eth_chainId"), 16) !== net.chainId) {
          await rpc("wallet_switchEthereumChain", [{ chainId: chainHex }]);
        }
      } else {
        throw error;
      }
    }
  }

  async function claimedOnChain(address) {
    return readUint(config.contract, SEL.claimed + pad32(config.token) + pad32(address));
  }

  async function refreshAccount() {
    var account = await api("account?address=" + state.address);
    var claimed = await claimedOnChain(state.address);
    var credited = BigInt(account.creditedAmount);
    var pending = credited > claimed ? credited - claimed : 0n;
    set({
      credited: account.creditedGold,
      remaining: account.remainingGold,
      available: account.availableGold,
      limitMessage: account.limitMessage,
      earnedGold: account.earnedGold,
      exchangedRun: account.exchangedRunGold,
      nextGoldIn: account.nextGoldIn,
      pending: pending > 0n ? formatUnits(pending, config.decimals) : ""
    });
  }

  function setWalletChain(id) {
    if (!id) {
      set({ walletChain: "", walletChainId: "", rightChain: "" });
      return;
    }
    set({ walletChain: chainName(id), walletChainId: id, rightChain: id === network().chainId ? "1" : "0" });
  }

  async function updateWalletChain() {
    try {
      setWalletChain(parseInt(await rpc("eth_chainId"), 16));
    } catch (error) {
      setWalletChain(0);
    }
  }

  // the exchange server is optional: the wallet connects without it
  async function tryLoadConfig() {
    try {
      await loadConfig();
      set({ exchange: "" });
      return true;
    } catch (error) {
      set({ exchange: friendlyError(error) });
      return false;
    }
  }

  // on-chain save slot of the connected wallet
  async function readSave() {
    var c = contracts();
    if (!c.saves || !state.address) return;
    var slot = decodeSave(await readCall(c.saves, SEL.getSave + pad32(state.address)));
    set({
      saveRead: "1",
      saveRunId: slot.runId,
      saveRunStartedAt: slot.runStartedAt,
      saveSavedAt: slot.savedAt,
      saveCount: slot.saveCount,
      saveData: slot.data
    });
  }

  // veHEMI voting power across the wallet's locks, and its HEMI balance
  async function readVePower() {
    var c = contracts();
    if (!c.veHemi || !c.hemi || !state.address) return;
    var owner = pad32(state.address);
    var locks = Number(await readUint(c.veHemi, SEL.balanceOf + owner));
    var power = 0n;
    for (var i = 0; i < Math.min(locks, MAX_VE_LOCKS); i++) {
      var tokenId = await readUint(c.veHemi, SEL.tokenOfOwnerByIndex + owner + uint(i));
      power += await readUint(c.veHemi, SEL.balanceOfNFT + uint(tokenId));
    }
    var balance = await readUint(c.hemi, SEL.balanceOf + owner);
    set({ veReady: "1", vePower: formatUnits(power, 18), veLocks: locks, hemiBalance: formatUnits(balance, 18) });
  }

  // everything the game shows about the wallet; reads only, never fatal
  async function readWalletData() {
    await readSave().catch(function () {});
    await readVePower().catch(function () {});
  }

  async function connect() {
    if (!wallet()) throw new Error("No wallet found. Install MetaMask or another EVM wallet.");
    rememberDisconnected(false);
    set({ step: "Approve the connection in your wallet" });
    var accounts = await rpc("eth_requestAccounts");
    if (!accounts || !accounts.length) throw new Error("No wallet account was shared.");
    if (accounts[0] !== state.address) clearAccountData();
    set({ address: accounts[0] });
    await updateWalletChain();
    var online = await tryLoadConfig();
    await readWalletData();

    // switch to Hemi right away, even if the exchange server is offline
    try {
      await ensureChain();
      await updateWalletChain();
    } catch (error) {
      await updateWalletChain();
      set({ exchange: error && error.code === 4001
        ? "Your wallet is still on " + (state.walletChain || "another network") + "."
        : friendlyError(error) });
      return;
    }
    if (online) {
      await refreshAccount().catch(function (error) { set({ exchange: friendlyError(error) }); });
    }
  }

  async function switchNetwork() {
    if (!state.address) return connect();
    await ensureChain();
    await updateWalletChain();
    if (state.rightChain === "1" && /still on/.test(state.exchange)) set({ exchange: "" });
    if (config && config.configured && state.rightChain === "1") {
      await refreshAccount().catch(function () {});
    }
  }

  // EIP-1193 has no standard disconnect: ask the wallet to drop this site's
  // permission where it can (MetaMask and others), and forget the account here
  async function disconnect() {
    rememberDisconnected(true);
    if (wallet()) {
      try {
        await rpc("wallet_revokePermissions", [{ eth_accounts: {} }]);
      } catch (error) { /* not every wallet supports it */ }
    }
    set({ address: "" });
    clearAccountData();
    if (/still on/.test(state.exchange)) set({ exchange: "" });
    setWalletChain(0);
  }

  // no popups: picks up a wallet that was connected before and the exchange status
  async function status() {
    if (wallet() && !state.address && !wasDisconnected()) {
      var accounts = await rpc("eth_accounts").catch(function () { return []; });
      if (accounts && accounts.length) set({ address: accounts[0] });
    }
    if (state.address) await updateWalletChain();
    var online = await tryLoadConfig();
    if (state.address) await readWalletData();
    if (online && state.address) await refreshAccount().catch(function () {});
  }

  async function redeem(gold) {
    if (!state.address) await connect();
    await loadConfig(); // the exchange itself has to be up to trade gold
    await ensureChain();

    set({ step: "Preparing your exchange..." });
    var challenge = await api("challenge", { address: state.address });

    set({ step: "Sign the message in your wallet (free, no gas)" });
    var signature = await rpc("personal_sign", [utf8Hex(challenge.message), state.address]);

    set({ step: "Checking with the exchange..." });
    var voucher = await api("redeem", { address: state.address, gold: gold, signature: signature });

    // the server has now credited this gold to the wallet; the game removes
    // them once per seq even if the transaction below is cancelled (it can be
    // claimed later because vouchers are cumulative)
    seq += 1;
    set({ seq: seq, granted: voucher.grantedGold, credited: voucher.creditedGold, exchangedRun: voucher.exchangedRunGold });

    var limitNote = voucher.limitMessage ? " " + voucher.limitMessage : "";

    var before = await claimedOnChain(state.address);
    var total = BigInt(voucher.cumulativeAmount);
    if (before >= total) {
      set({ amount: "0", pending: "" });
      if (limitNote) throw new Error(limitNote.trim());
      return "Nothing to claim right now.";
    }

    set({ pending: formatUnits(total - before, config.decimals) });
    await sendTransaction(voucher.contract,
      encodeClaim(voucher.token, voucher.cumulativeAmount, voucher.deadline, voucher.signature),
      "Confirm the claim in your wallet (small gas fee)");

    var amount = formatUnits(total - before, config.decimals);
    set({ amount: amount, pending: "" });
    await refreshAccount().catch(function () {});
    return "Received " + amount + " " + config.symbol + "!" + limitNote;
  }

  async function loadSave() {
    if (!state.address) throw new Error("Connect a wallet to load your on-chain save.");
    if (!config) await tryLoadConfig();
    if (!contracts().saves) throw new Error("On-chain saves aren't set up on this server yet.");
    set({ step: "Reading your save..." });
    await readSave();
    if (config && config.configured) await refreshAccount().catch(function () {});
  }

  async function writeSave(text, runId) {
    if (!state.address) throw new Error("Connect a wallet to save on-chain.");
    if (!config) await tryLoadConfig();
    var c = contracts();
    if (!c.saves) throw new Error("On-chain saves aren't set up on this server yet.");
    if (!text || new TextEncoder().encode(text).length > MAX_SAVE_BYTES) throw new Error("This save is too big to store on-chain.");
    await ensureChain();
    await updateWalletChain();
    if (runId === null) {
      // save into the wallet's current run (read fresh, so a New Game made
      // elsewhere is respected)
      await readSave();
      runId = Number(state.saveRunId || 0);
    }
    await sendTransaction(c.saves, encodeSave(text, runId), "Confirm the save in your wallet (tiny gas fee)");
    await readSave().catch(function () {});
    if (config && config.configured) await refreshAccount().catch(function () {});
    return "Saved on-chain!";
  }

  async function newGame() {
    if (!state.address) throw new Error("Connect a wallet to clear your on-chain save.");
    if (!config) await tryLoadConfig();
    var c = contracts();
    if (!c.saves) throw new Error("On-chain saves aren't set up on this server yet.");
    await ensureChain();
    await updateWalletChain();
    await sendTransaction(c.saves, SEL.newGame, "Confirm the fresh start in your wallet (tiny gas fee)");
    await readSave().catch(function () {});
    if (config && config.configured) await refreshAccount().catch(function () {});
    return "Your on-chain save is cleared. A new journey begins!";
  }

  async function vePower() {
    if (!state.address) throw new Error("Connect a wallet to read your veHEMI.");
    if (!config) await tryLoadConfig();
    set({ step: "Reading your veHEMI..." });
    await readVePower();
  }

  async function stake(amountWhole, days) {
    if (!state.address) await connect();
    if (!config) await tryLoadConfig();
    var c = contracts();
    if (!c.veHemi || !c.hemi) throw new Error("Staking needs the Hemi network.");
    if (!(amountWhole >= MIN_STAKE_HEMI)) throw new Error("Stake at least " + MIN_STAKE_HEMI + " HEMI.");
    if (!(days >= MIN_LOCK_DAYS && days <= MAX_LOCK_DAYS)) {
      throw new Error("Lock for " + MIN_LOCK_DAYS + " days up to 4 years.");
    }
    await ensureChain();
    await updateWalletChain();

    var owner = pad32(state.address);
    var amount = BigInt(amountWhole) * 10n ** 18n;
    var balance = await readUint(c.hemi, SEL.balanceOf + owner);
    if (balance < amount) throw new Error("This wallet only has " + formatUnits(balance, 18) + " HEMI.");

    var allowance = await readUint(c.hemi, SEL.allowance + owner + pad32(c.veHemi));
    if (allowance < amount) {
      await sendTransaction(c.hemi, SEL.approve + pad32(c.veHemi) + uint(amount),
        "Approve " + amountWhole + " HEMI for staking in your wallet");
    }
    await sendTransaction(c.veHemi, SEL.createLock + uint(amount) + uint(BigInt(days) * 86400n),
      "Confirm the " + days + "-day lock in your wallet");
    await readVePower().catch(function () {});
    return "Locked " + amountWhole + " HEMI for " + days + " days. Your mana grows!";
  }

  function run(action, task) {
    busy = true;
    runs += 1;
    set({ state: "working", action: action, run: runs, error: "" });
    task()
      .then(function (message) {
        if (message) {
          set({ state: "done", step: message });
        } else if (state.address) {
          set({ state: "connected", step: "Connected" });
        } else {
          set({ state: "idle", step: "" });
        }
      })
      .catch(function (error) {
        set({ state: "error", error: friendlyError(error), step: "" });
      })
      .then(function () {
        busy = false;
      });
  }

  // follow account and network switches made in the wallet itself
  if (global.ethereum && global.ethereum.on) {
    global.ethereum.on("accountsChanged", function (accounts) {
      var has = accounts && accounts.length;
      if (has && !state.address && wasDisconnected()) return; // stays disconnected until Connect
      if (!has || accounts[0] !== state.address) clearAccountData();
      set({ address: has ? accounts[0] : "" });
      if (!has) setWalletChain(0);
      if (!busy && state.state !== "working") set({ state: has ? "connected" : "idle" });
    });
    global.ethereum.on("chainChanged", function (id) {
      if (!state.address) return;
      setWalletChain(parseInt(id, 16));
      if (state.rightChain === "1" && /still on/.test(state.exchange)) set({ exchange: "" });
    });
  }

  global.ashfallBridge = {
    version: 4,

    isAvailable: function () { return true; },

    start: function (action, query) {
      if (busy) return "busy";
      var params = new URLSearchParams(query || "");
      var number = function (name) { return Math.floor(Number(params.get(name) || 0)); };
      if (action === "connect") {
        run(action, connect);
      } else if (action === "status") {
        run(action, status);
      } else if (action === "switch") {
        run(action, switchNetwork);
      } else if (action === "disconnect") {
        run(action, disconnect);
      } else if (action === "redeem") {
        var gold = Math.max(0, number("gold"));
        run(action, function () { return redeem(gold); });
      } else if (action === "loadsave") {
        run(action, loadSave);
      } else if (action === "save") {
        var text = params.get("data") || "";
        var runId = params.has("run") ? Math.max(0, number("run")) : null;
        run(action, function () { return writeSave(text, runId); });
      } else if (action === "newgame") {
        run(action, newGame);
      } else if (action === "vepower") {
        run(action, vePower);
      } else if (action === "stake") {
        var amount = number("amount");
        var days = number("days");
        run(action, function () { return stake(amount, days); });
      } else {
        return "unknown";
      }
      return "ok";
    },

    poll: function () {
      set({ wallet: wallet() ? "1" : "0" });
      return encodeState();
    },

    // for the page menu (web/menu.js)
    getState: function () {
      set({ wallet: wallet() ? "1" : "0" });
      return Object.assign({}, state);
    },

    toggleMenu: function () {
      if (global.ashfallMenu) global.ashfallMenu.toggle();
      return "ok";
    },

    // exposed for tests
    _encodeClaim: encodeClaim,
    _encodeSave: encodeSave,
    _decodeSave: decodeSave
  };
}(window));
