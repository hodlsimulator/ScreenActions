// popup.js — MV3 popover; always proxy to background via runtime.sendMessage
(() => {
  const RT = (typeof browser !== "undefined" ? browser.runtime
           : (typeof chrome  !== "undefined" ? chrome.runtime  : null));
  const TABS = (typeof browser !== "undefined" ? browser.tabs
             : (typeof chrome  !== "undefined" ? chrome.tabs  : null));
  const SCRIPTING = (typeof browser !== "undefined" ? browser.scripting
                  : (typeof chrome  !== "undefined" ? chrome.scripting : null));

  function q(id){ return document.getElementById(id); }
  function setStatus(t, ok){
    const s = q("status"); if(!s) return;
    s.textContent = t;
    s.className = "status " + (ok ? "ok" : "err");
  }

  async function pageCtx(){
    try{
      const [tab] = TABS ? await TABS.query({ active:true, currentWindow:true }) : [{ title:document.title, url:"" }];
      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null){
        const res = await SCRIPTING.executeScript({
          target:{ tabId: tab.id, allFrames:true },
          func: () => String(getSelection ? getSelection() : "")
        });
        const first = res && res.find(r => r?.result?.trim()?.length > 0);
        return { selection:(first ? first.result : ""), title:tab?.title || document.title || "", url:tab?.url || "" };
      }
      return { selection:"", title:tab?.title || document.title || "", url:tab?.url || "" };
    } catch { return { selection:"", title:document.title || "", url:"" }; }
  }

  // Always message the background; support both callback/promise styles
  async function native(action, payload){
    return await new Promise((resolve, reject) => {
      if (!RT || !RT.sendMessage) return reject(new Error("runtime.sendMessage unavailable"));
      try {
        const maybe = RT.sendMessage({ cmd:"native", action, payload }, (resp) => {
          const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) return reject(new Error(err.message || String(err)));
          resolve(resp);
        });
        if (maybe && typeof maybe.then === "function") maybe.then(resolve).catch(reject);
      } catch (e) { reject(e); }
    });
  }

  async function run(action){
    const ctx = await pageCtx();
    if (q("sel")) q("sel").textContent = (ctx.selection?.trim() || ctx.title || "(No selection)");
    try{
      const r = await native(action, ctx);
      if (r?.openURL) setStatus("Opening app…", true);
      else setStatus(r?.ok ? (r.message || "Done.") : (r?.message || "Native error."), !!r?.ok);
    } catch(e){
      setStatus((e && e.message) || "Native error.", false);
    }
  }

  function boot(){
    q("btn-auto")?.addEventListener("click", () => run("autoDetect"));
    q("btn-rem") ?.addEventListener("click", () => run("createReminder"));
    q("btn-cal") ?.addEventListener("click", () => run("addEvent"));
    q("btn-ctc") ?.addEventListener("click", () => run("extractContact"));
    q("btn-csv") ?.addEventListener("click", () => run("receiptCSV"));
    // ping → Ready
    native("ping", {}).then(r => setStatus(r?.ok ? "Ready." : "Native bridge error.", !!r?.ok))
                      .catch(() => setStatus("Native bridge error.", false));
  }

  if (document.readyState !== "loading") boot();
  else document.addEventListener("DOMContentLoaded", boot);
})();
