// background.js — native messaging proxy (works reliably on iOS 26)

const HOSTS = [
  "com.conornolan.Screen-Actions",             // App bundle id (primary)
  "com.conornolan.Screen-Actions.WebExtension" // Extension bundle id (fallback)
];

async function sendNativeViaHosts(payload) {
  let lastErr = null;
  for (const host of HOSTS) {
    try {
      const resp = await browser.runtime.sendNativeMessage(host, payload);
      return resp;
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error("Native messaging failed.");
}

// Popup/content → Background proxy
browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.cmd !== "native") return;

  // Keep the message channel alive (async)
  return (async () => {
    const { action, payload } = msg;
    const resp = await sendNativeViaHosts({ action, payload });
    return resp;
  })();
});

// Optional: small startup log
try { console.log("[ScreenActions] background worker ready"); } catch (_e) {}
