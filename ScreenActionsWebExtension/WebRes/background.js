// background.js — MV3 worker; popup → native (callback style, works on Safari)
// v1-final

(function () {
  const RT =
    (typeof chrome !== "undefined" && chrome.runtime) ||
    (typeof browser !== "undefined" && browser.runtime);

  if (!RT) {
    // nothing we can do, but avoid throwing
    self.addEventListener("install", () => {});
    return;
  }

  // Single handler for all messages from popup
  RT.onMessage.addListener(function (msg, sender, sendResponse) {
    try {
      if (!msg || !msg.cmd) return;

      // simple health check
      if (msg.cmd === "echo") {
        try { sendResponse({ ok: true, echo: msg.data ?? true }); } catch {}
        return;
      }

      if (msg.cmd === "native") {
        // ALWAYS use callback form; Safari supports this even if it also has Promise form.
        try {
          RT.sendNativeMessage(
            { action: msg.action, payload: msg.payload },
            function (resp) {
              // If native threw, surface a simple error object (resp could be undefined)
              const lastErr =
                typeof chrome !== "undefined" &&
                chrome.runtime &&
                chrome.runtime.lastError
                  ? chrome.runtime.lastError.message || String(chrome.runtime.lastError)
                  : null;
              if (!resp && lastErr) {
                try { sendResponse({ ok: false, message: lastErr }); } catch {}
              } else {
                try { sendResponse(resp); } catch {}
              }
            }
          );
        } catch (e) {
          try { sendResponse({ ok: false, message: (e && e.message) || String(e) }); } catch {}
        }
        return true; // keep channel open for async sendResponse
      }
    } catch (e) {
      try { sendResponse({ ok: false, message: (e && e.message) || String(e) }); } catch {}
    }
  });
})();
