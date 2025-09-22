// background.js — native-only bridge (Safari iOS/macOS). Popup sends messages here.
(() => {
  const B = (typeof browser !== "undefined") ? browser : undefined;
  const C = (typeof chrome  !== "undefined") ? chrome  : undefined;
  const R = (B && B.runtime) || (C && C.runtime);

  function sendNative(body) {
    return new Promise((resolve, reject) => {
      if (!R || !R.sendNativeMessage) return reject(new Error("runtime.sendNativeMessage unavailable"));
      try {
        const done = (resp) => {
          const err = (C && C.runtime && C.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err)));
          else resolve(resp);
        };
        // Safari: one-argument form only
        const maybe = R.sendNativeMessage(body, done);
        if (maybe && typeof maybe.then === "function") maybe.then(resolve).catch(reject);
      } catch (e) {
        reject(e);
      }
    });
  }

  (R.onMessage || R.onMessageExternal).addListener((msg, _sender, sendResponse) => {
    if (!msg || msg.cmd !== "native") return;
    (async () => {
      try {
        const resp = await sendNative({ action: msg.action, payload: msg.payload });
        sendResponse(resp);
      } catch (e) {
        sendResponse({ ok: false, message: (e && e.message) || String(e) });
      }
    })();
    return true; // keep channel open for async reply
  });

  try { console.log("[SA] background ready"); } catch {}
})();
