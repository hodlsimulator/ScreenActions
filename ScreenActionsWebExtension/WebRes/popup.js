// popup.js — call native directly; fall back to background proxy if direct call fails or is unavailable
(() => {
  const RT = (typeof browser !== "undefined" ? browser.runtime
           : (typeof chrome !== "undefined" ? chrome.runtime : null));
  const TABS = (typeof browser !== "undefined" ? browser.tabs
             : (typeof chrome !== "undefined" ? chrome.tabs : null));
  const SCRIPTING = (typeof browser !== "undefined" ? browser.scripting
                  : (typeof chrome !== "undefined" ? chrome.scripting : null));

  function q(id){ return document.getElementById(id); }

  function setStatus(t, ok){
    const s = q("status");
    if(!s) return;
    s.textContent = t;
    s.className = ok ? "status ok" : "status err";
  }

  async function nativeViaBackground(action, payload){
    return await new Promise((resolve, reject) => {
      if (!RT || !RT.sendMessage) return reject(new Error("runtime.sendMessage unavailable"));
      try {
        const ret = RT.sendMessage({ cmd:"native", action, payload }, resp => {
          const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          err ? reject(new Error(err.message || String(err))) : resolve(resp);
        });
        if (ret && typeof ret.then === "function") ret.then(resolve).catch(reject);
      } catch (e) {
        reject(e);
      }
    });
  }

  async function nativeDirect(action, payload){
    const api = RT && typeof RT.sendNativeMessage === "function" ? RT : null;
    if (api) {
      try {
        const p = api.sendNativeMessage({ action, payload });
        if (p && typeof p.then === "function") return await p;
      } catch (_) {
        // fall through to background proxy
      }
    }
    return await nativeViaBackground(action, payload);
  }

  async function pageCtx(){
    try{
      const [tab] = TABS ? await TABS.query({ active:true, currentWindow:true }) : [{ title:document.title, url:"" }];
      if (SCRIPTING && SCRIPTING.executeScript){
        const res = await SCRIPTING.executeScript({
          target:{ tabId: tab.id, allFrames:true },
          func: () => String(getSelection ? getSelection() : "")
        });
        const first = res && res.find(r => r?.result?.trim()?.length > 0);
        return { selection:(first ? first.result : ""), title:tab?.title || document.title || "", url:tab?.url || "" };
      }
      return { selection:"", title:tab?.title || document.title || "", url:tab?.url || "" };
    } catch {
      return { selection:"", title:document.title || "", url:"" };
    }
  }

  async function run(action){
    const ctx = await pageCtx();
    if (q("sel")) q("sel").textContent = (ctx.selection?.trim() || ctx.title || "(No selection)");
    try{
      const r = await nativeDirect(action, ctx);
      setStatus(r?.ok ? (r.message || "Done.") : (r?.message || "Native bridge error."), !!r?.ok);
    } catch(e){
      setStatus((e && e.message) || "Native bridge error.", false);
    }
  }

  document.addEventListener("DOMContentLoaded", async () => {
    q("btn-auto")?.addEventListener("click", () => run("autoDetect"));
    q("btn-rem") ?.addEventListener("click", () => run("createReminder"));
    q("btn-cal") ?.addEventListener("click", () => run("addEvent"));
    q("btn-ctc") ?.addEventListener("click", () => run("extractContact"));
    q("btn-csv") ?.addEventListener("click", () => run("receiptCSV"));
    try {
      const ping = await nativeDirect("ping", {});
      setStatus(ping?.ok ? "Ready." : "Native bridge error.", !!ping?.ok);
    } catch {
      setStatus("Native bridge error.", false);
    }
  });
})();
