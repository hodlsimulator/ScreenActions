// background.js — native messaging proxy (iOS-first, robust)
// Notes:
// • We use runtime.sendNativeMessage only. On Safari, the "host" string is ignored,
//   but it must be a string, so we pass a conservative candidate list and try them.
// • We do NOT use connectNative (the port) on iOS because it can hang silently.

(function () {
  const API = globalThis.browser || globalThis.chrome;

  // Safari ignores this parameter, but keep plausible identifiers for clarity.
  // (Try them in order; first one will work everywhere Safari supports native messaging.)
  const HOSTS = [
    "application.id", // harmless, Safari ignores
    "com.conornolan.Screen-Actions.WebExtension",
    "com.conornolan.Screen-Actions.ScreenActionsWebExtension",
    "com.conornolan.Screen-Actions.ScreenActionsWebExtension2",
    "com.conornolan.Screen-Actions.WebExtFix.1757988823"
  ];

  // Promise wrapper that works with both Promise- and callback-style APIs.
  function callSendNativeMessage(host, payload) {
    return new Promise((resolve, reject) => {
      if (!API.runtime || !API.runtime.sendNativeMessage) {
        return reject(new Error("sendNativeMessage unavailable"));
      }
      try {
        const done = (resp) => {
          const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err)));
          else resolve(resp);
        };
        const maybe = API.runtime.sendNativeMessage(host, payload, done);
        if (maybe && typeof maybe.then === "function") {
          maybe.then(resolve).catch(reject);
        }
      } catch (e) {
        reject(e);
      }
    });
  }

  async function sendNative(payload) {
    let lastErr = null;
    for (const host of HOSTS) {
      try {
        const resp = await callSendNativeMessage(host, payload);
        try { console.log("[SA] native ok via sendNativeMessage:", host); } catch {}
        return resp;
      } catch (e) {
        lastErr = e;
        try { console.warn("[SA] sendNativeMessage failed via", host, e && e.message); } catch {}
      }
    }
    throw lastErr || new Error("Native messaging failed.");
  }

  // Proxy popup → native
  (API.runtime.onMessage || API.runtime.onMessageExternal).addListener((msg, _sender, sendResponse) => {
    if (!msg || msg.cmd !== "native") return;
    (async () => {
      try {
        const resp = await sendNative({ action: msg.action, payload: msg.payload });
        sendResponse(resp);
      } catch (e) {
        sendResponse({ ok: false, message: (e && e.message) || String(e) });
      }
    })();
    return true; // keep message channel open
  });

  try { console.log("[SA] background worker ready"); } catch {}
})();
