// background.js — strict Safari-native bridge. One-argument only. No host. No callbacks.
// Also caches per-tab selection so popup can prefill editors.

(() => {
  'use strict';

  const RT = (typeof browser !== 'undefined' && browser.runtime)
    ? browser.runtime
    : (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime : undefined;
  const TABS = (typeof browser !== 'undefined' && browser.tabs)
    ? browser.tabs
    : (typeof chrome !== 'undefined' && chrome.tabs) ? chrome.tabs : undefined;

  if (!RT) return;

  // ---------- Per-tab selection cache ----------
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
    try { const [tab] = await TABS.query({ active:true, currentWindow:true }); return tab?.id; }
    catch { return undefined; }
  }

  async function getCtx(tabIdMaybe) {
    let tabId = tabIdMaybe;
    if (typeof tabId !== 'number') tabId = await getActiveTabId();
    const ctx = (typeof tabId === 'number') ? selStore.get(tabId) : undefined;
    return { ok:true, ctx: {
      selection: ctx?.selection || '',
      title: ctx?.title || '',
      url: ctx?.url || '',
      structured: ctx?.structured || undefined
    }};
  }

  // ---------- Native (Safari-first, single-argument) ----------
  function hasSafariNative() {
    return (typeof browser !== 'undefined'
         && browser.runtime
         && typeof browser.runtime.sendNativeMessage === 'function');
  }

  async function sendNativeStrict(message) {
    // Deep-clone to ensure JSON-serialisable payload (Safari rejects exotic values).
    let msg;
    try { msg = JSON.parse(JSON.stringify(message || {})); }
    catch { msg = {}; }

    if (hasSafariNative()) {
      // IMPORTANT: single argument only on iOS Safari.
      return await browser.runtime.sendNativeMessage(msg);
    }

    // Chrome fallback (desktop dev), still single-argument path if available.
    if (typeof chrome !== 'undefined'
        && chrome.runtime
        && typeof chrome.runtime.sendNativeMessage === 'function') {
      return await new Promise((resolve, reject) => {
        try {
          // Use callback form but still **one argument** (no host string)
          chrome.runtime.sendNativeMessage(msg, (out) => {
            const le = chrome.runtime.lastError || null;
            if (le) reject(new Error(le.message || 'Native callback error'));
            else resolve(out);
          });
        } catch (e) { reject(e); }
      });
    }

    throw new Error('sendNativeMessage not available');
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
        // Call native **inline** (within this onMessage task) — iOS Safari is strict about timing.
        const out = await sendNativeStrict({ action, payload });
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
    return true; // keep channel open for the Promise above
  });
})();
