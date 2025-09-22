// background.js — native-only bridge (iOS-safe). Popup sends messages here.
(() => {
  const B = typeof browser !== "undefined" ? browser : undefined;
  const C = typeof chrome  !== "undefined" ? chrome  : undefined;
  const R = (B && B.runtime) || (C && C.runtime);

  const HOSTS = [
    "application.id",
    "com.conornolan.Screen-Actions.WebExtension",
    "com.conornolan.Screen-Actions.ScreenActionsWebExtension",
    "com.conornolan.Screen-Actions.ScreenActionsWebExtension2",
    "com.conornolan.Screen-Actions.WebExtFix.1757988823"
  ];

  function callSendNativeMessage(host, body) {
    return new Promise((resolve, reject) => {
      if (!R || !R.sendNativeMessage) return reject(new Error("runtime.sendNativeMessage unavailable"));
      try {
        const done = (resp) => {
          const err = (C && C.runtime && C.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err)));
          else resolve(resp);
        };
        const maybe = R.sendNativeMessage(host, body, done);
        if (maybe && typeof maybe.then === "function") maybe.then(resolve).catch(reject);
      } catch (e) {
        reject(e);
      }
    });
  }

  async function sendNative(payload) {
    let lastErr = null;
    for (const host of HOSTS) {
      try { return await callSendNativeMessage(host, payload); }
      catch (e) { lastErr = e; }
    }
    throw lastErr || new Error("Native messaging failed.");
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
    return true; // keep channel open
  });

  try { console.log("[SA] background ready"); } catch {}
})();
