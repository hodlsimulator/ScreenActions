// background.js — native messaging proxy with robust host detection (iOS 26 safe)

(function () {
  const API = globalThis.browser || globalThis.chrome;

  // Derive the extension bundle id (Safari exposes it in the extension URL)
  let derivedExtID = null;
  try {
    const u = API.runtime.getURL("");
    const m = typeof u === "string" && u.match(/safari-web-extension:\/\/([^/]+)/);
    derivedExtID = m ? m[1] : null;
  } catch (_) {}

  // App id goes first; adjust if your printed app CFBundleIdentifier differs.
  const HOSTS = [
    "com.conornolan.Screen-Actions",
    "com.conornolan.Screen-Actions.WebExtension"
  ].concat(derivedExtID ? [derivedExtID] : []);

  async function sendNativeViaHosts(payload) {
    let lastErr = null;
    for (const host of HOSTS) {
      try {
        const resp = await API.runtime.sendNativeMessage(host, payload);
        try { console.log("[ScreenActions] native ok via", host); } catch (_e) {}
        return resp;
      } catch (e) {
        lastErr = e;
        try { console.warn("[ScreenActions] native fail via", host, e && e.message); } catch (_e) {}
      }
    }
    throw lastErr || new Error("Native messaging failed.");
  }

  // MV3 on Safari: prefer callback + return true; some builds are picky about Promises.
  (API.runtime.onMessage || API.runtime.onMessageExternal).addListener((msg, _sender, sendResponse) => {
    if (!msg || msg.cmd !== "native") return;
    (async () => {
      try {
        const resp = await sendNativeViaHosts({ action: msg.action, payload: msg.payload });
        sendResponse(resp);
      } catch (e) {
        sendResponse({ ok: false, message: (e && e.message) || String(e) });
      }
    })();
    return true; // keep channel open for async response
  });

  try { console.log("[ScreenActions] background worker ready"); } catch (_e) {}
})();
