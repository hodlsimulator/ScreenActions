// background.js — iOS/macOS Safari: native messaging bridge
(() => {
  const B = (typeof browser !== "undefined") ? browser : undefined;
  const C = (typeof chrome  !== "undefined") ? chrome  : undefined;
  const R = (B && B.runtime) || (C && C.runtime);

  function sendNative(body) {
    try {
      // Safari supports ONE-arg Promise form
      const p = R && R.sendNativeMessage ? R.sendNativeMessage(body) : null;
      if (p && typeof p.then === "function") return p;

      // Fallback (Chromium callback form, not used by Safari)
      return new Promise((resolve, reject) => {
        if (!R || !R.sendNativeMessage) return reject(new Error("runtime.sendNativeMessage unavailable"));
        try {
          R.sendNativeMessage(body, (resp) => {
            const err = (C && C.runtime && C.runtime.lastError) || null;
            if (err) reject(new Error(err.message || String(err)));
            else resolve(resp);
          });
        } catch (e) { reject(e); }
      });
    } catch (e) {
      return Promise.reject(e);
    }
  }

  const onMsg = (R && (R.onMessage || R.onMessageExternal));
  if (onMsg && typeof onMsg.addListener === "function") {
    onMsg.addListener((msg, _sender, sendResponse) => {
      if (!msg || msg.cmd !== "native") return;
      (async () => {
        try {
          const resp = await sendNative({ action: msg.action, payload: msg.payload });
          sendResponse(resp);
        } catch (e) {
          sendResponse({ ok: false, message: (e && e.message) || String(e) });
        }
      })();
      return true; // keep channel open
    });
  }

  try { console.log("[SA] background ready"); } catch {}
})();
