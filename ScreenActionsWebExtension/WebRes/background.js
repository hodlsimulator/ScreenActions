// background.js — iOS/macOS Safari: native messaging bridge (one-arg only)
(() => {
  const B = (typeof browser !== "undefined") ? browser : undefined;
  const C = (typeof chrome  !== "undefined") ? chrome  : undefined;
  const R = (B && B.runtime) || (C && C.runtime);

  function sendNative(body) {
    const p = (R && typeof R.sendNativeMessage === "function") ? R.sendNativeMessage(body) : null;
    if (!p || typeof p.then !== "function") {
      return Promise.reject(new Error("runtime.sendNativeMessage unavailable"));
    }
    return p;
  }

  const onMsg = R && (R.onMessage || R.onMessageExternal);
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
