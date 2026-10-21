/* The ☰ menu in the page's top bar (outside the game canvas).
 * Wallet connection goes through web/bridge.js, so the game's Hemi Exchange
 * sees the same wallet. */
(function () {
  "use strict";

  var bridge = window.ashfallBridge;
  var button = document.getElementById("menuButton");
  var panel = document.getElementById("menuPanel");
  var connect = document.getElementById("menuConnect");
  var switchButton = document.getElementById("menuSwitch");
  var disconnect = document.getElementById("menuDisconnect");
  var status = document.getElementById("menuWalletStatus");
  var networkLine = document.getElementById("menuNetwork");
  var networkName = document.getElementById("menuNetworkName");
  var note = document.getElementById("menuNote");
  var dot = document.getElementById("menuDot");
  var canvas = document.getElementById("canvas");

  function shortAddress(address) {
    return address.slice(0, 6) + "..." + address.slice(-4);
  }

  function render() {
    var s = bridge.getState();
    var connected = !!s.address;
    var working = s.state === "working";
    var rightChain = s.rightChain === "1";
    var target = s.chain || "Hemi";
    dot.hidden = !connected;

    if (connected) {
      status.textContent = shortAddress(s.address);
    } else {
      status.textContent = s.wallet === "1" ? "Not connected" : "No browser wallet found";
    }

    networkLine.hidden = !connected || !s.walletChain;
    networkLine.className = rightChain ? "network ok" : "network";
    networkName.textContent = rightChain
      ? "On " + s.walletChain
      : "On " + s.walletChain + ", the exchange uses " + target;

    connect.hidden = connected;
    switchButton.hidden = !connected || rightChain || !s.walletChain;
    switchButton.textContent = "Switch to " + target;
    disconnect.hidden = !connected;
    connect.disabled = switchButton.disabled = disconnect.disabled = working;

    if (working) {
      note.textContent = s.step || "Working...";
      note.className = "note";
    } else if (s.state === "error") {
      note.textContent = s.error;
      note.className = "note error";
    } else {
      note.textContent = s.exchange || "";
      note.className = "note";
    }
  }

  function open() {
    panel.hidden = false;
    button.setAttribute("aria-expanded", "true");
    bridge.start("status");
    render();
  }

  function close() {
    panel.hidden = true;
    button.setAttribute("aria-expanded", "false");
    if (canvas) canvas.focus(); // give the keyboard back to the game
  }

  function toggle() {
    if (panel.hidden) open(); else close();
  }

  function action(element, name) {
    element.addEventListener("click", function (event) {
      event.stopPropagation();
      bridge.start(name);
      render();
    });
  }

  button.addEventListener("click", function (event) {
    event.stopPropagation();
    toggle();
  });

  action(connect, "connect");
  action(switchButton, "switch");
  action(disconnect, "disconnect");

  panel.addEventListener("click", function (event) {
    event.stopPropagation();
  });

  document.addEventListener("click", function () {
    if (!panel.hidden) close();
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && !panel.hidden) close();
  });

  setInterval(render, 250);
  render();
  bridge.start("status"); // no popup: just notices a wallet connected earlier

  window.ashfallMenu = { open: open, close: close, toggle: toggle };
}());
