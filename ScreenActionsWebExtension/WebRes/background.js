// background.js — Safari-safe native bridge; call from background only.
(() => {
  'use strict';

  const RT = (typeof browser !== 'undefined' && browser.runtime) ? browser.runtime
           : (typeof chrome  !== 'undefined' && chrome.runtime ) ? chrome.runtime : undefined;
  const TABS = (typeof browser !== 'undefined' && browser.tabs) ? browser.tabs
           : (typeof chrome  !== 'undefined' && chrome.tabs  ) ? chrome.tabs  : undefined;
  if (!RT) return;

  // -------- per-tab context cache --------
  const sel = new Map();
  function setCtx(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok:false, message:'No tab.' };
    const selection = String(payload?.selection || '').trim();
    const title = String(payload?.title || '');
    const url = String(payload?.url || '');
    const structured = (payload && typeof payload.structured === 'object') ? payload.structured : undefined;
    sel.set(tabId, { selection, title, url, structured, ts: Date.now() });
    return { ok:true };
  }
  async function activeTabId(){ try{ const [t]=await TABS?.query?.({active:true,currentWindow:true})||[]; return t?.id; }catch{ return undefined; } }
  async function getCtx(tabIdMaybe){
    let id = tabIdMaybe; if (typeof id !== 'number') id = await activeTabId();
    const c = (typeof id === 'number') ? sel.get(id) : undefined;
    return { ok:true, ctx: { selection:c?.selection||'', title:c?.title||'', url:c?.url||'', structured:c?.structured||undefined } };
  }

  // -------- native bridge (Safari one-arg first; then fallbacks) --------
  const TIMEOUT = 15000;
  const withTimeout = (p,ms)=>new Promise((res,rej)=>{ const t=setTimeout(()=>rej(new Error('native timeout')),ms); Promise.resolve(p).then(v=>{clearTimeout(t);res(v)}).catch(e=>{clearTimeout(t);rej(e)}); });

  function getNativeFn(){
    if (typeof browser !== 'undefined' && browser.runtime && typeof browser.runtime.sendNativeMessage === 'function')
      return browser.runtime.sendNativeMessage.bind(browser.runtime);
    if (typeof chrome !== 'undefined' && chrome.runtime && typeof chrome.runtime.sendNativeMessage === 'function')
      return chrome.runtime.sendNativeMessage.bind(chrome.runtime);
    return null;
  }

  async function sendNative(message){
    let msg; try { msg = JSON.parse(JSON.stringify(message||{})); } catch { msg = {}; }
    const f = getNativeFn(); if (!f) throw new Error('sendNativeMessage not available');

    // 1) Promise, one-arg (Safari path)
    try { const r=f(msg); if (r?.then) return await withTimeout(r, TIMEOUT); } catch {}

    // 2) Callback, one-arg (some iOS builds expose only callback)
    try { return await withTimeout(new Promise((res,rej)=>{ try { f(msg,(out)=>{ const le=chrome?.runtime?.lastError; if(le) rej(new Error(le.message||'Native error')); else res(out); }); } catch(e){ rej(e);} }), TIMEOUT); } catch {}

    // 3) Two-arg with empty host (Chrome-style)
    try { const r=f('', msg); if (r?.then) return await withTimeout(r, TIMEOUT); } catch {}
    try { return await withTimeout(new Promise((res,rej)=>{ try { f('',msg,(out)=>{ const le=chrome?.runtime?.lastError; if(le) rej(new Error(le.message||'Native error')); else res(out); }); } catch(e){ rej(e);} }), TIMEOUT); } catch {}

    throw new Error('Invalid call to sendNativeMessage');
  }

  // -------- router --------
  async function handle(request, sender) {
    const cmd = String(request?.cmd || '');
    if (cmd === 'selUpdate') return setCtx(sender, request.payload || {});
    if (cmd === 'getPageCtx') return await getCtx((typeof request.tabId==='number')?request.tabId:sender?.tab?.id);
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

  RT.onMessage.addListener((req, sender, sendResponse) => { Promise.resolve(handle(req, sender)).then(sendResponse); return true; });
})();
