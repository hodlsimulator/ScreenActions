// popup.js — MV3 popover; robust path: Port → sendMessage → direct Promise native.
(() => {
  const RT        = (typeof chrome !== "undefined" && chrome.runtime) ||
                    (typeof browser !== "undefined" && browser.runtime);
  const TABS      = (typeof chrome !== "undefined" && chrome.tabs) ||
                    (typeof browser !== "undefined" && browser.tabs);
  const SCRIPTING = (typeof chrome !== "undefined" && chrome.scripting) ||
                    (typeof browser !== "undefined" && browser.scripting);

  let   port      = null;
  const HOST_HINT = ""; // ignored by Safari

  function q(id) { return document.getElementById(id); }

  function setStatus(t, ok) {
    const s = q("status");
    if (!s) return;
    s.textContent = t;
    s.className   = "status " + (ok ? "ok" : "err");
  }

  async function pageCtx() {
    try {
      const [tab] = TABS
        ? await TABS.query({ active: true, currentWindow: true })
        : [{ title: document.title, url: "" }];

      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null) {
        const res = await SCRIPTING.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func:   () => String(getSelection ? getSelection() : "")
        });
        const first = res && res.find(r => r?.result?.trim()?.length > 0);
        return {
          selection: (first ? first.result : ""),
          title:     tab?.title || document.title || "",
          url:       tab?.url   || ""
        };
      }

      return {
        selection: "",
        title:     tab?.title || document.title || "",
        url:       tab?.url   || ""
      };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  function ensurePort() {
    if (port) return port;
    port = RT.connect();
    return port;
  }

  function viaPortOnce(payload, timeoutMs = 1500) {
    const p = ensurePort();
    return new Promise((resolve, reject) => {
      const handler = (resp) => {
        p.onMessage.removeListener(handler);
        resolve(resp);
      };
      p.onMessage.addListener(handler);
      p.postMessage(payload);
      setTimeout(() => {
        try { p.onMessage.removeListener(handler); } catch {}
        reject(new Error("port timeout"));
      }, timeoutMs);
    });
  }

  function viaSendMessage(payload, timeoutMs = 1500) {
    return new Promise((resolve, reject) => {
      try {
        let settled = false;
        const ret = RT.sendMessage(payload, (resp) => {
          settled = true;
          const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err)));
          else     resolve(resp);
        });

        if (ret && typeof ret.then === "function") {
          ret.then((resp) => { if (!settled) resolve(resp); })
             .catch((e)   => { if (!settled) reject(e); });
        }

        setTimeout(() => {
          if (!settled) reject(new Error("sendMessage timeout"));
        }, timeoutMs);
      } catch (e) {
        reject(e);
      }
    });
  }

  // Direct Promise native (Safari) with Chrome callback fallback
  function viaDirectNative(action, payload, timeoutMs = 2500) {
    return new Promise((resolve, reject) => {
      try {
        if (!RT.sendNativeMessage) {
          reject(new Error("sendNativeMessage unavailable"));
          return;
        }

        // Chrome 3‑arg callback if present
        if (
          typeof chrome !== "undefined" &&
          typeof chrome.runtime?.sendNativeMessage === "function" &&
          chrome.runtime.sendNativeMessage.length === 3
        ) {
          let done = false;
          chrome.runtime.sendNativeMessage(HOST_HINT, { action, payload }, (r) => {
            done = true;
            const err = chrome.runtime.lastError || null;
            if (err) reject(new Error(err.message || String(err)));
            else     resolve(r);
          });
          setTimeout(() => {
            if (!done) reject(new Error("direct native timeout"));
          }, timeoutMs);
          return;
        }

        // Safari Promise API — prefer 1‑arg (message) form
        let settled = false;
        let p;
        try {
          p = RT.sendNativeMessage({ action, payload });
        } catch {
          p = RT.sendNativeMessage(HOST_HINT, { action, payload });
        }

        if (p && typeof p.then === "function") {
          p.then((r) => { settled = true; resolve(r); })
           .catch((e) => { settled = true; reject(e); });

          setTimeout(() => {
            if (!settled) reject(new Error("direct native timeout"));
          }, timeoutMs);
        } else {
          reject(new Error("Unsupported sendNativeMessage form"));
        }
      } catch (e) {
        reject(e);
      }
    });
  }

  async function askNative(action, payload) {
    try { return await viaPortOnce({ cmd: "native", action, payload }); } catch {}
    try { return await viaSendMessage({ cmd: "native", action, payload }); } catch {}
    return await viaDirectNative(action, payload);
  }

  async function run(action) {
    const ctx = await pageCtx();
    if (q("sel")) q("sel").textContent = (ctx.selection?.trim() || ctx.title || "(No selection)");

    try {
      const r = await askNative(action, ctx);

      // TEMP DIAGNOSTIC: log what the native bridge returned for this action
      console.log("[POPUP] action result:", action, r);

      if (r?.openURL) {
        setStatus("Opening app…", true);
      } else {
        setStatus(r?.ok ? (r.message || "Done.")
                        : (r?.message || "Native error."),
                  !!r?.ok);
      }
    } catch (e) {
      setStatus((e && e.message) || "Native error.", false);
    }
  }

  async function boot() {
    q("btn-auto")?.addEventListener("click", () => run("autoDetect"));
    q("btn-rem") ?.addEventListener("click", () => run("createReminder"));
    q("btn-cal") ?.addEventListener("click", () => run("addEvent"));
    q("btn-ctc") ?.addEventListener("click", () => run("extractContact"));
    q("btn-csv") ?.addEventListener("click", () => run("receiptCSV"));

    // Health‑check: echo → ping
    try {
      await viaPortOnce({ cmd: "echo", data: true })
        .catch(() => viaSendMessage({ cmd: "echo", data: true }));

      const r = await askNative("ping", {});
      setStatus(r?.ok ? "Ready." : "Native bridge error.", !!r?.ok);
    } catch {
      setStatus("Native bridge error.", false);
    }
  }

  if (document.readyState !== "loading") boot();
  else document.addEventListener("DOMContentLoaded", boot);
})();
