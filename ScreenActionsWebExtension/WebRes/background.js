// WebRes/background.js — MV3 worker (Safari + Chrome). Promise-safe native bridge; 7s timeout.
(() => {
  const RT =
    (typeof chrome !== "undefined" && chrome.runtime) ||
    (typeof browser !== "undefined" && browser.runtime);
  if (!RT) return;

  const HOST_HINT = ""; // Safari ignores; only used if a Chrome-style 3‑arg API is detected.

  function withTimeout(promise, ms) {
    let settled = false;
    return new Promise((resolve) => {
      promise
        .then((resp) => { settled = true; resolve(resp || { ok: false, message: "No response" }); })
        .catch((e)  => { settled = true; resolve({ ok: false, message: (e && e.message) || String(e) }); });
      setTimeout(() => { if (!settled) resolve({ ok: false, message: "Native timeout" }); }, ms);
    });
  }

  function sendNative(action, payload, timeoutMs = 7000) {
    const msg = { action, payload };
    if (!RT.sendNativeMessage) return Promise.resolve({ ok: false, message: "sendNativeMessage unavailable" });

    // Chrome callback API: (host, message, callback)
    if (typeof chrome !== "undefined" &&
        typeof chrome.runtime?.sendNativeMessage === "function" &&
        chrome.runtime.sendNativeMessage.length === 3) {
      return new Promise((resolve) => {
        let done = false;
        chrome.runtime.sendNativeMessage(HOST_HINT, msg, (resp) => {
          done = true;
          const err = chrome.runtime.lastError || null;
          resolve(err ? { ok: false, message: err.message || String(err) }
                      : (resp || { ok: false, message: "No response" }));
        });
        setTimeout(() => { if (!done) resolve({ ok: false, message: "Native timeout" }); }, timeoutMs);
      });
    }

    // Safari Promise API — prefer 1‑arg (message) form, then (host, message)
    try {
      const p1 = RT.sendNativeMessage(msg);
      if (p1 && typeof p1.then === "function") return withTimeout(p1, timeoutMs);
    } catch {}
    try {
      const p2 = RT.sendNativeMessage(HOST_HINT, msg);
      if (p2 && typeof p2.then === "function") return withTimeout(p2, timeoutMs);
    } catch {}

    return Promise.resolve({ ok: false, message: "Unsupported sendNativeMessage form" });
  }

  // MV3 one‑shot messages (return Promises)
  RT.onMessage.addListener((msg) => {
    try {
      if (!msg || !msg.cmd) return;
      if (msg.cmd === "echo")   return Promise.resolve({ ok: true, echo: msg.data ?? true });
      if (msg.cmd === "native") return sendNative(msg.action, msg.payload);
    } catch (e) {
      return Promise.resolve({ ok: false, message: (e && e.message) || String(e) });
    }
  });

  // Persistent Port
  RT.onConnect?.addListener((port) => {
    port.onMessage.addListener(async (msg) => {
      try {
        if (!msg || !msg.cmd) return;
        if (msg.cmd === "echo")   { port.postMessage({ ok: true, echo: msg.data ?? true }); return; }
        if (msg.cmd === "native") { port.postMessage(await sendNative(msg.action, msg.payload)); return; }
      } catch (e) {
        port.postMessage({ ok: false, message: (e && e.message) || String(e) });
      }
    });
  });
})();
