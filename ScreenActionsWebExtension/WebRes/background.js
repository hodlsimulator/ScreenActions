// background.js — iOS/macOS Safari: native messaging bridge (one-arg only)
(() => {
  const RT = (typeof browser !== "undefined" ? browser.runtime
           : (typeof chrome !== "undefined" ? chrome.runtime : null));

  function sendNative(body) {
    if (!RT || typeof RT.sendNativeMessage !== "function") {
      return Promise.reject(new Error("runtime.sendNativeMessage unavailable"));
    }
    const p = RT.sendNativeMessage(body);
    if (!p || typeof p.then !== "function") {
      return Promise.reject(new Error("sendNativeMessage did not return a Promise"));
    }
    return p;
  }

  const onMsg = RT && RT.onMessage;
  if (onMsg && typeof onMsg.addListener === "function") {
    onMsg.addListener((msg, _sender, sendResponse) => {
      if (!msg || msg.cmd !== "native") return;
      (async () => {
        try {
          sendResponse(await sendNative({ action: msg.action, payload: msg.payload }));
        } catch (e) {
          sendResponse({ ok: false, message: (e && e.message) || String(e) });
        }
      })();
      return true; // keep channel open
    });
  }
})();
