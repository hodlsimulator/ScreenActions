// popup.js — call native directly; fall back to background proxy if needed
(() => {
  const BR = (typeof browser !== "undefined" && browser.runtime &&
              typeof browser.runtime.sendNativeMessage === "function")
            ? browser.runtime : null;
  const RT = (typeof browser !== "undefined" ? browser.runtime :
             (typeof chrome  !== "undefined" ? chrome.runtime  : null));
  const TABS=(browser&&browser.tabs)||(chrome&&chrome.tabs);
  const SCRIPTING=(browser&&browser.scripting)||(chrome&&chrome.scripting);
  const STORAGE=(browser&&browser.storage&&browser.storage.local)||(chrome&&chrome.storage&&chrome.storage.local)||null;

  function q(id){ return document.getElementById(id); }
  function setStatus(t, ok){ const s=q("status"); if(!s)return; s.textContent=t; s.className=ok?"status ok":"status err"; }

  async function nativeDirect(action, payload){
    if (BR) {
      const p = BR.sendNativeMessage({action, payload});
      if (p && typeof p.then==="function") return await p;
    }
    // Background proxy fallback
    return await new Promise((resolve,reject)=>{
      if (!RT || !RT.sendMessage) return reject(new Error("runtime.sendMessage unavailable"));
      try{
        const ret = RT.sendMessage({cmd:"native", action, payload}, resp=>{
          const err=(chrome&&chrome.runtime&&chrome.runtime.lastError)||null;
          err?reject(new Error(err.message||String(err))):resolve(resp);
        });
        if (ret && typeof ret.then==="function") ret.then(resolve).catch(reject);
      }catch(e){ reject(e); }
    });
  }

  async function getPageContext(){
    try{
      const [tab] = await (TABS? TABS.query({active:true,currentWindow:true}) : [{title:document.title,url:""}]);
      if (SCRIPTING && SCRIPTING.executeScript){
        const r = await SCRIPTING.executeScript({ target:{tabId:tab.id, allFrames:true},
          func:()=>{ function selFromActive(){ const el=document.activeElement; if(!el) return ""; const tag=(el.tagName||"").toLowerCase(); const type=(el.type||"").toLowerCase();
            if(tag==="textarea"|| (tag==="input" && (type===""||["text","search","url","tel"].includes(type)))){
              const s=el.selectionStart??0, e=el.selectionEnd??0, v=el.value||""; return e>s? v.substring(s,e):""; } return ""; }
            const sel=String(getSelection?getSelection():"") || selFromActive(); return {selection:sel,title:document.title||"",url:location.href||""}; }
        });
        const pick = r && r.find(x=>x?.result?.selection?.trim()?.length>0);
        return (pick?.result) || (r?.[0]?.result) || {selection:"",title:tab.title||"",url:tab.url||""};
      }
      return {selection:"",title:tab.title||"",url:tab.url||""};
    }catch{ return {selection:"",title:document.title||"",url:""}; }
  }

  async function run(action){
    const ctx=await getPageContext();
    q("sel") && (q("sel").textContent=(ctx.selection?.trim()||ctx.title||"(No selection)"));
    try{
      const r = await nativeDirect(action, ctx);
      setStatus(r?.ok ? (r.message||"Done.") : (r?.message||"Native bridge error."), !!r?.ok);
    }catch(e){ setStatus((e&&e.message)||"Native bridge error.", false); }
  }

  document.addEventListener("DOMContentLoaded", async ()=>{
    q("btn-auto")?.addEventListener("click",()=>run("autoDetect"));
    q("btn-rem") ?.addEventListener("click",()=>run("createReminder"));
    q("btn-cal") ?.addEventListener("click",()=>run("addEvent"));
    q("btn-ctc") ?.addEventListener("click",()=>run("extractContact"));
    q("btn-csv") ?.addEventListener("click",()=>run("receiptCSV"));

    try{ const ping=await nativeDirect("ping",{}); setStatus(ping?.ok?"Ready.":"Native bridge error.", !!ping?.ok); }
    catch{ setStatus("Native bridge error.", false); }
  });
})();
