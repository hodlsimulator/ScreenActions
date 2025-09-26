// background.js — caches selection per-tab; bridges popup↔native; Safari-safe replies.
(() => {
  'use strict';

  const RT = (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime
           : (typeof browser !== 'undefined' && browser.runtime) ? browser.runtime
           : undefined;
  const TABS = (typeof chrome !== 'undefined' && chrome.tabs) ? chrome.tabs
            : (typeof browser !== 'undefined' && browser.tabs) ? browser.tabs
            : undefined;

  if (!RT) return;

  // Per-tab context
  const selStore = new Map(); // tabId -> { selection, title, url, structured?, ts }

  function setCtxFromSender(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok:false, message:'No tab.' };
    const selection = String(payload?.selection || '').trim();
    const title = String(payload?.title || '');
    const url = String(payload?.url || '');
    const structured = (payload && typeof payload.structured === 'object') ? payload.structured : undefined;
    selStore.set(tabId, { selection, title, url, structured, ts: Date.now() });
    return { ok:true };
  }

  async function getActiveTabId() {
    if (!TABS?.query) return undefined;
    try { const [tab] = await TABS.query({ active:true, currentWindow:true }); return tab?.id; } catch { return undefined; }
  }

  async function getCtx(tabIdMaybe) {
    let tabId = tabIdMaybe;
    if (typeof tabId !== 'number') tabId = await getActiveTabId();
    const ctx = (typeof tabId === 'number') ? selStore.get(tabId) : undefined;
    return { ok:true, ctx: {
      selection:  ctx?.selection  || '',
      title:      ctx?.title      || '',
      url:        ctx?.url        || '',
      structured: ctx?.structured || undefined
    }};
  }

  // Native bridge (queued) — optional; popup may also call native directly.
  const TIMEOUT_MS = 15000;
  const queue = []; let inFlight = false;
  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));
  const clone = (v)=>{ try { return JSON.parse(JSON.stringify(v ?? null)); } catch { return null; } };
  const isThenable = (x)=>!!x && (typeof x==='object'||typeof x==='function') && typeof x.then==='function';

  async function sendNativeRaw(message) {
    const f = RT && RT.sendNativeMessage;
    if (typeof f !== 'function') throw new Error('sendNativeMessage not available');
    const msg = clone(message) || {};
    try { const r=f(msg); if (isThenable(r)) return await r; } catch {}
    try { const r=f('', msg); if (isThenable(r)) return await r; } catch {}
    try { return await new Promise((res,rej)=>{ try {
      f(msg,(out)=>{ const le=chrome?.runtime?.lastError||null; if(le) rej(new Error(le.message||'Native callback error')); else res(out); });
    } catch(e){ rej(e); } }); } catch {}
    try { return await new Promise((res,rej)=>{ try {
      f('',msg,(out)=>{ const le=chrome?.runtime?.lastError||null; if(le) rej(new Error(le.message||'Native callback error')); else res(out); });
    } catch(e){ rej(e); } }); } catch {}
    throw new Error('Native bridge unavailable');
  }

  function withTimeout(promise, ms){ let t; const killer=new Promise((_,rej)=>{t=setTimeout(()=>rej(new Error('native timeout')),ms)}); return Promise.race([promise,killer]).finally(()=>clearTimeout(t)); }

  async function runQueue() {
    if (inFlight) return;
    const job = queue.shift(); if (!job) return;
    inFlight = true;
    try {
      const res = await withTimeout(sendNativeRaw(job.message), TIMEOUT_MS);
      job.resolve((res && typeof res==='object' && ('ok' in res)) ? res : { ok:false, message:'Empty native reply.' });
    } catch(e) {
      job.resolve({ ok:false, message: (e && e.message) || 'Native bridge error.' });
    } finally { inFlight=false; await sleep(0); void runQueue(); }
  }

  function enqueueNative(message){ return new Promise((resolve)=>{ queue.push({message, resolve}); void runQueue(); }); }

  async function handleCommand(request, sender) {
    if (!request || typeof request !== 'object') return { ok:false, message:'Bad request.' };
    const cmd = String(request.cmd || '');
    if (cmd === 'selUpdate')  return setCtxFromSender(sender, request.payload || {});
    if (cmd === 'getPageCtx') { const tabId = (typeof request.tabId === 'number') ? request.tabId : sender?.tab?.id; return await getCtx(tabId); }
    if (cmd === 'native')     { const action = String(request.action || ''); const payload = clone(request.payload) || {}; if (!action) return { ok:false, message:'Missing action.' }; return await enqueueNative({ action, payload }); }
    if (cmd === 'echo')       return { ok:true };
    return { ok:false, message:'Unknown command.' };
  }

  RT.onMessage.addListener((request, sender, sendResponse) => {
    Promise.resolve(handleCommand(request, sender)).then((res)=>{
      if (res && typeof res==='object' && ('ok' in res)) sendResponse(res);
      else sendResponse({ ok:false, message:'Empty native reply.' });
    });
    return true; // keep channel open for async
  });
})();
