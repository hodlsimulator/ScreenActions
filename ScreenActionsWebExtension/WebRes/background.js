// background.js — MV3 worker (Safari-friendly). Uses Promise-return for onMessage.
(() => {
  const RT =
    (typeof chrome !== "undefined" && chrome.runtime) ||
    (typeof browser !== "undefined" && browser.runtime);
  if (!RT) return;

  // Native bridge wrapped as a Promise
  function sendNative(action, payload) {
    return new Promise((resolve) => {
      try {
        RT.sendNativeMessage({ action, payload }, (resp) => {
          const err =
            (typeof chrome !== "undefined" &&
              chrome.runtime &&
              chrome.runtime.lastError) ||
            null;
          if (!resp && err) {
            resolve({ ok: false, message: err.message || String(err) });
          } else {
            resolve(resp || { ok: false, message: "No response" });
          }
        });
      } catch (e) {
        resolve({ ok: false, message: (e && e.message) || String(e) });
      }
    });
  }

  // Path 1: one-shot messages — return a Promise (no sendResponse/return true)
  RT.onMessage.addListener((msg /*, sender */) => {
    try {
      if (!msg || !msg.cmd) return;
      if (msg.cmd === "echo") {
        return Promise.resolve({ ok: true, echo: msg.data ?? true });
      }
      if (msg.cmd === "native") {
        return sendNative(msg.action, msg.payload);
      }
    } catch (e) {
      return Promise.resolve({
        ok: false,
        message: (e && e.message) || String(e),
      });
    }
  });

  // Path 2: persistent Port (unchanged behaviour, but uses the same Promise helper)
  RT.onConnect?.addListener((port) => {
    port.onMessage.addListener(async (msg) => {
      try {
        if (!msg || !msg.cmd) return;
        if (msg.cmd === "echo") {
          port.postMessage({ ok: true, echo: msg.data ?? true });
          return;
        }
        if (msg.cmd === "native") {
          port.postMessage(await sendNative(msg.action, msg.payload));
          return;
        }
      } catch (e) {
        port.postMessage({ ok: false, message: (e && e.message) || String(e) });
      }
    });
  });
})();
