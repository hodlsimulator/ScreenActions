// background.js — MV3 worker; robust popup ↔ background ↔ native bridge.
// Supports BOTH runtime.onMessage (sendMessage) and runtime.onConnect (Port).

(() => {
  const RT =
    (typeof chrome !== "undefined" && chrome.runtime) ||
    (typeof browser !== "undefined" && browser.runtime);
  if (!RT) return;

  function sendNativeCB(action, payload, cb) {
    try {
      // Always use callback form (safest on Safari iOS)
      RT.sendNativeMessage({ action, payload }, (resp) => {
        const lastErr =
          typeof chrome !== "undefined" &&
          chrome.runtime &&
          chrome.runtime.lastError
            ? chrome.runtime.lastError.message ||
              String(chrome.runtime.lastError)
            : null;
        if (!resp && lastErr) cb({ ok: false, message: lastErr });
        else cb(resp || { ok: false, message: "No response" });
      });
    } catch (e) {
      cb({ ok: false, message: (e && e.message) || String(e) });
    }
  }

  // Path 1: one-shot messages
  RT.onMessage.addListener((msg, _sender, sendResponse) => {
    try {
      if (!msg || !msg.cmd) return;

      if (msg.cmd === "echo") {
        try { sendResponse({ ok: true, echo: msg.data ?? true }); } catch {}
        return;
      }

      if (msg.cmd === "native") {
        sendNativeCB(msg.action, msg.payload, (r) => {
          try { sendResponse(r); } catch {}
        });
        return true; // keep channel open
      }
    } catch (e) {
      try { sendResponse({ ok: false, message: (e && e.message) || String(e) }); } catch {}
    }
  });

  // Path 2: persistent Port
  RT.onConnect?.addListener((port) => {
    port.onMessage.addListener((msg) => {
      try {
        if (!msg || !msg.cmd) return;

        if (msg.cmd === "echo") {
          port.postMessage({ ok: true, echo: msg.data ?? true });
          return;
        }

        if (msg.cmd === "native") {
          sendNativeCB(msg.action, msg.payload, (r) => port.postMessage(r));
          return;
        }
      } catch (e) {
        port.postMessage({ ok: false, message: (e && e.message) || String(e) });
      }
    });
  });
})();
