// popup.js — thin flow that wakes the MV3 worker reliably on iOS.
// Changes:
//  • No runtime.connect Port. Uses runtime.sendMessage only (wakes worker).
//  • Longer timeouts (5s) to tolerate cold-starts.
//  • Still calls your thin native actions (autoDetect/createReminder/addEvent/extractContact/receiptCSV).
(() => {
  const RT        = (typeof chrome !== "undefined" && chrome.runtime) || (typeof browser !== "undefined" && browser.runtime);
  const TABS      = (typeof chrome !== "undefined" && chrome.tabs)    || (typeof browser !== "undefined" && browser.tabs);
  const SCRIPTING = (typeof chrome !== "undefined" && chrome.scripting)|| (typeof browser !== "undefined" && browser.scripting);

  const q = (id) => document.getElementById(id);
  const show = (id) => {
    for (const el of document.querySelectorAll(".view")) { el.classList.remove("active"); el.hidden = true; }
    const el = q(id); if (el) { el.classList.add("active"); el.hidden = false; }
  };
  const setStatus = (el, t, ok) => { el.textContent = t || ""; el.className = "status " + (ok ? "ok" : (t ? "err" : "")); };

  // ---- Messaging helpers (sendMessage-only)
  function sendMessage(payload, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
      try {
        let settled = false;
        const ret = RT.sendMessage(payload, (resp) => {
          settled = true;
          const lastErr = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          if (lastErr) reject(new Error(lastErr.message || String(lastErr)));
          else resolve(resp);
        });
        if (ret && typeof ret.then === "function") {
          ret.then((resp) => { if (!settled) resolve(resp); }).catch((e) => { if (!settled) reject(e); });
        }
        setTimeout(() => { if (!settled) reject(new Error("timeout")); }, timeoutMs);
      } catch (e) { reject(e); }
    });
  }

  async function askNative(action, payload) {
    try { return await sendMessage({ cmd: "native", action, payload }, 5000); }
    catch (e) { return { ok: false, message: e?.message || "Native bridge error." }; }
  }

  // ---- Page context (cache-first via background)
  async function pageCtx() {
    try {
      const [tab] = TABS ? await TABS.query({ active: true, currentWindow: true }) : [null];
      const res = await sendMessage({ cmd: "getPageCtx", tabId: tab?.id }, 5000);
      if (res?.ok && res?.ctx) {
        const c = res.ctx;
        if ((c.selection?.trim()?.length || 0) > 0 || c.title || c.url) return c;
      }
      // Runtime fallback: may be empty after focus change on iOS
      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null) {
        const exec = await SCRIPTING.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func: () => String(getSelection ? getSelection() : "")
        });
        const first = exec && exec.find(r => r?.result?.trim()?.length > 0);
        return { selection: (first ? first.result : ""), title: tab?.title || document.title || "", url: tab?.url || "" };
      }
      return { selection: "", title: tab?.title || document.title || "", url: tab?.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  // ---- Thin actions that bounce to app if native returns openURL/url
  async function runThin(action, ctx) {
    setStatus(q("status"), "Working…", true);
    const r = await askNative(action, ctx);
    const open = r?.openURL || r?.url;
    if (open) {
      try {
        if (TABS?.create) await TABS.create({ url: open });
        else window.open(open, "_blank");
        setStatus(q("status"), "Opening app…", true);
      } catch {
        setStatus(q("status"), r?.message || "Couldn’t open app.", false);
      }
      return;
    }
    setStatus(q("status"), r?.message || (r?.ok ? "Done." : "Native bridge error."), !!r?.ok);
  }

  // ---- (Optional) “fat” editor toggles
  function wireEditors() {
    for (const btn of document.querySelectorAll(".nav-back")) btn.addEventListener("click", () => show("home"));
    q("event-save")?.addEventListener("click", () => runThin("addEvent", ctx));
    q("rem-save")  ?.addEventListener("click", () => runThin("createReminder", ctx));
    q("ctc-save")  ?.addEventListener("click", () => runThin("extractContact", ctx));

    q("csv-reparse")?.addEventListener("click", async () => {
      const t = q("csv-input").value || "";
      const r = await askNative("receiptCSV", { selection: t, title: "", url: "" });
      q("csv-preview").textContent = (typeof r?.csv === "string") ? r.csv : "—";
    });
    q("csv-export") ?.addEventListener("click", async () => {
      const csv = q("csv-preview").textContent || "";
      const r = await askNative("receiptCSV", { csv });
      setStatus(q("csv-status"), r?.message || (r?.ok ? "Exported." : "Error."), !!r?.ok);
    });
  }

  function wireHome() {
    q("btn-auto")?.addEventListener("click", () => runThin("autoDetect", ctx));
    q("btn-rem") ?.addEventListener("click", () => runThin("createReminder", ctx));
    q("btn-cal") ?.addEventListener("click", () => runThin("addEvent", ctx));
    q("btn-ctc") ?.addEventListener("click", () => runThin("extractContact", ctx));
    q("btn-csv") ?.addEventListener("click", () => runThin("receiptCSV", ctx));
  }

  // ---- Boot
  let ctx = { selection: "", title: "", url: "" };
  document.addEventListener("DOMContentLoaded", async () => {
    wireHome();
    wireEditors();
    show("home");

    // Ready check (sendMessage wakes worker; allow 5s)
    try { await sendMessage({ cmd: "echo", payload: true }, 5000); setStatus(q("status"), "Ready.", true); }
    catch { setStatus(q("status"), "Native bridge error.", false); }

    // Populate selection/title/url
    ctx = await pageCtx();
    q("sel").textContent = (ctx.selection?.trim() || ctx.title || "No selection");
  });
})();
