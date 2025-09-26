// background.js — robust Safari-native bridge; tries 1-arg, 2-arg, and callback forms.
// Also caches per-tab selection so the popup can prefill editors.
(() => {
  'use strict';

  const RT = (typeof browser !== 'undefined' && browser.runtime)
    ? browser.runtime
    : (typeof chrome  !== 'undefined' && chrome.runtime) ? chrome.runtime : undefined;

  const TABS = (typeof browser !== 'undefined' && browser.tabs)
    ? browser.tabs
    : (typeof chrome  !== 'undefined' && chrome.tabs) ? chrome.tabs : undefined;

  if (!RT) return;

  // ---------- Per-tab selection cache ----------
  const selStore = new Map();
  function setCtxFromSender(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok:false, message:'No tab.' };
    const selection = String(payload?.selection || '').trim();
    const title     = String(payload?.title || '');
    const url       = String(payload?.url || '');
    const structured= (payload && typeof payload.structured === 'object') ? payload.structured : undefined;
    selStore.set(tabId, { selection, title, url, structured, ts: Date.now() });
    return { ok:true };
  }
  async function getActiveTabId(){ if(!TABS?.query) return undefined; try{ const [tab]=await TABS.query({active:true,currentWindow:true}); return tab?.id; }catch{ return undefined; } }
  async function getCtx(tabIdMaybe){
    let tabId = tabIdMaybe; if (typeof tabId !== 'number') tabId = await getActiveTabId();
    const ctx = (typeof tabId === 'number') ? selStore.get(tabId) : undefined;
    return { ok:true, ctx: { selection: ctx?.selection || '', title: ctx?.title || '', url: ctx?.url || '', structured: ctx?.structured || undefined } };
  }

  // ---------- Native bridge ----------
  const TIMEOUT_MS = 15000;
  const withTimeout = (p,ms)=>new Promise((res,rej)=>{
    const t=setTimeout(()=>rej(new Error('native timeout')),ms);
    Promise.resolve(p).then(v=>{clearTimeout(t);res(v)}).catch(e=>{clearTimeout(t);rej(e)});
  });

  function getNativeFn(){
    if (typeof browser !== 'undefined' && browser.runtime && typeof browser.runtime.sendNativeMessage === 'function')
      return browser.runtime.sendNativeMessage.bind(browser.runtime);
    if (typeof chrome  !== 'undefined' && chrome.runtime  && typeof chrome.runtime.sendNativeMessage  === 'function')
      return chrome.runtime.sendNativeMessage.bind(chrome.runtime);
    return null;
  }

  async function sendNative(message){
    // Deep-clone to ensure JSON-serialisable payload
    let msg; try { msg = JSON.parse(JSON.stringify(message || {})); } catch { msg = {}; }
    const f = getNativeFn();
    if (!f) throw new Error('sendNativeMessage not available');

    // 1) Promise, 1 arg
    try { const r=f(msg); if (r?.then) return await withTimeout(r, TIMEOUT_MS); } catch {}
    // 2) Promise, 2 args (empty host)
    try { const r=f('', msg); if (r?.then) return await withTimeout(r, TIMEOUT_MS); } catch {}
    // 3) Callback, 1 arg
    try { return await withTimeout(new Promise((res,rej)=>{ try { f(msg,(out)=>{ const le=chrome?.runtime?.lastError; if(le) rej(new Error(le.message||'Native cb error')); else res(out); }); } catch(e){ rej(e);} }), TIMEOUT_MS); } catch {}
    // 4) Callback, 2 args (empty host)
    try { return await withTimeout(new Promise((res,rej)=>{ try { f('',msg,(out)=>{ const le=chrome?.runtime?.lastError; if(le) rej(new Error(le.message||'Native cb error')); else res(out); }); } catch(e){ rej(e);} }), TIMEOUT_MS); } catch {}

    throw new Error('Invalid call to sendNativeMessage');
  }

  // ---------- Router ----------
  async function handleCommand(request, sender) {
    if (!request || typeof request !== 'object') return { ok:false, message:'Bad request.' };
    const cmd = String(request.cmd || '');

    if (cmd === 'selUpdate') return setCtxFromSender(sender, request.payload || {});
    if (cmd === 'getPageCtx') {
      const tabId = (typeof request.tabId === 'number') ? request.tabId : sender?.tab?.id;
      return await getCtx(tabId);
    }
    if (cmd === 'native') {
      const action  = String(request.action  || '');
      const payload = (request.payload && typeof request.payload === 'object') ? request.payload : {};
      if (!action) return { ok:false, message:'Missing action.' };
      try {
        const out = await sendNative({ action, payload });
        return (out && typeof out === 'object') ? out : { ok:false, message:'Empty native reply.' };
      } catch (e) {
        return { ok:false, message: e?.message || 'Native bridge error.' };
      }
    }
    if (cmd === 'echo') return { ok:true };
    return { ok:false, message:'Unknown command.' };
  }

  RT.onMessage.addListener((request, sender, sendResponse) => {
    Promise.resolve(handleCommand(request, sender)).then(sendResponse);
    return true; // keep channel open
  });
})();
