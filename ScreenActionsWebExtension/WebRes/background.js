// background.js — iOS/macOS Safari: native messaging bridge (one-arg only)
(() => {
  const BR = (typeof browser !== "undefined" && browser.runtime &&
              typeof browser.runtime.sendNativeMessage === "function")
            ? browser.runtime : null;

  function sendNative(body) {
    if (!BR) return Promise.reject(new Error("browser.runtime.sendNativeMessage unavailable"));
    const p = BR.sendNativeMessage(body);
    if (!p || typeof p.then !== "function")
      return Promise.reject(new Error("sendNativeMessage did not return a Promise"));
    return p;
  }

  const onMsg = browser && browser.runtime && browser.runtime.onMessage;
  if (onMsg && typeof onMsg.addListener === "function") {
    onMsg.addListener((msg, _sender, sendResponse) => {
      if (!msg || msg.cmd !== "native") return;
      (async () => {
        try { sendResponse(await sendNative({ action: msg.action, payload: msg.payload })); }
        catch (e) { sendResponse({ ok:false, message:(e && e.message) || String(e) }); }
      })();
      return true;
    });
  }
})();
