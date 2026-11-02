/* Fullscreen for the game's page: the whole page goes fullscreen when the
 * game's title screen or Settings asks (src/utilities/webBridge.lua), so
 * state() and toggle() answer in strings. Browsers only go fullscreen right
 * after a click or key press, and Esc always leaves it. */
(function () {
  "use strict";

  var root = document.documentElement;
  var canvas = document.getElementById("canvas");

  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function fullscreenEnabled() {
    return !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);
  }

  function ignore(result) {
    if (result && result.catch) result.catch(function () {});
  }

  function toggleFullscreen() {
    if (fullscreenElement()) {
      ignore((document.exitFullscreen || document.webkitExitFullscreen).call(document));
    } else if (fullscreenEnabled()) {
      ignore((root.requestFullscreen || root.webkitRequestFullscreen).call(root, { navigationUI: "hide" }));
    }
    return "ok";
  }

  // give the keyboard back to the game
  function fullscreenChanged() {
    if (canvas) canvas.focus();
  }

  document.addEventListener("fullscreenchange", fullscreenChanged);
  document.addEventListener("webkitfullscreenchange", fullscreenChanged);

  window.ashfallFullscreen = {
    state: function () { return fullscreenEnabled() ? (fullscreenElement() ? "1" : "0") : ""; },
    toggle: toggleFullscreen
  };
}());
