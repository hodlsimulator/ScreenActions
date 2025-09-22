// background.js — native messaging proxy with robust fallbacks (iOS 26 safe)

(function () {
  const API = globalThis.browser || globalThis.chrome;

  // Fill with exact IDs after build (step 5).
  const HOSTS = ["com.conornolan.Screen-Actions","com.conornolan.Screen-Actions.ScreenActionsWebExtension"];

  // Promise wrapper that works with both Promise- and callback-style APIs
  function callSendNativeMessage(host, payload) {
    return new Promise((resolve, reject) => {
      if (!API.runtime || !API.runtime.sendNativeMessage) {
        return reject(new Error("sendNativeMessage unavailable"));
      }
      let settled = false;

      try {
        const maybePromise = API.runtime.sendNativeMessage(host, payload, (resp) => {
          if (settled) return;
          const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) { settled = true; reject(new Error(err.message || String(err))); }
          else { settled = true; resolve(resp); }
        });
        // Safari/browser may return a Promise; handle both shapes
        if (maybePromise && typeof maybePromise.then === "function") {
          maybePromise.then((resp) => { if (!settled) { settled = true; resolve(resp); } })
                      .catch((e)   => { if (!settled) { settled = true; reject(e); } });
        }
      } catch (e) {
        reject(e);
      }
    });
  }

  // Fallback using connectNative (port)
  function callConnectNative(host, payload) {
    return new Promise((resolve, reject) => {
      if (!API.runtime || !API.runtime.connectNative) {
        return reject(new Error("connectNative unavailable"));
      }
      let settled = false;
      let port;
      try {
        port = API.runtime.connectNative(host);
      } catch (e) {
        return reject(e);
      }

      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          try { port.disconnect(); } catch (_) {}
          reject(new Error("connectNative timeout"));
        }
      }, 3000);

      port.onMessage.addListener((msg) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(msg);
        try { port.disconnect(); } catch (_) {}
      });

      port.onDisconnect.addListener(() => {
        const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(new Error(err?.message || "Native port disconnected"));
        }
      });

      try { port.postMessage(payload); } catch (e) {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(e);
        }
      }
    });
  }

  async function sendNativeViaHosts(payload) {
    let lastErr = null;
    for (const host of HOSTS) {
      // First try sendNativeMessage (preferred), then connectNative
      try {
        const resp = await callSendNativeMessage(host, payload);
        try { console.log("[SA] native ok via sendNativeMessage:", host); } catch {}
        return resp;
      } catch (e1) {
        lastErr = e1;
        try { console.warn("[SA] sendNativeMessage failed via", host, e1 && e1.message); } catch {}
      }
      try {
        const resp2 = await callConnectNative(host, payload);
        try { console.log("[SA] native ok via connectNative:", host); } catch {}
        return resp2;
      } catch (e2) {
        lastErr = e2;
        try { console.warn("[SA] connectNative failed via", host, e2 && e2.message); } catch {}
      }
    }
    throw lastErr || new Error("Native messaging failed.");
  }

  // Proxy popup → native
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
    return true;
  });

  try { console.log("[SA] background worker ready"); } catch {}
})();
