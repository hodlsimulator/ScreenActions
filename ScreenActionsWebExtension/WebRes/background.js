// background.js — caches selection per-tab and bridges to native.
// Fixes "Empty native reply" by supporting both Promise and callback
// forms of runtime.sendNativeMessage used by Safari on iOS.

(() => {
  'use strict';

  const RT = (typeof chrome !== 'undefined' && chrome.runtime)
    ? chrome.runtime
    : (typeof browser !== 'undefined' && browser.runtime)
      ? browser.runtime
      : undefined;

  const TABS = (typeof chrome !== 'undefined' && chrome.tabs)
    ? chrome.tabs
    : (typeof browser !== 'undefined' && browser.tabs)
      ? browser.tabs
      : undefined;

  if (!RT) return;

  // ---------- Per-tab page context ----------
  // tabId -> { selection, title, url, structured?, ts }
  const selStore = new Map();

  function setCtxFromSender(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok: false, message: 'No tab.' };
    const selection = String(payload?.selection || '').trim();
    const title = String(payload?.title || '');
    const url = String(payload?.url || '');
    const structured =
      (payload && typeof payload.structured === 'object') ? payload.structured : undefined;

    selStore.set(tabId, { selection, title, url, structured, ts: Date.now() });
    return { ok: true };
  }

  async function getActiveTabId() {
    if (!TABS?.query) return undefined;
    try {
      const [tab] = await TABS.query({ active: true, currentWindow: true });
      return tab?.id;
    } catch { return undefined; }
  }

  async function getCtx(tabIdMaybe) {
    let tabId = tabIdMaybe;
    if (typeof tabId !== 'number') tabId = await getActiveTabId();
    const ctx = (typeof tabId === 'number') ? selStore.get(tabId) : undefined;
    return {
      ok: true,
      ctx: {
        selection:  ctx?.selection  || '',
        title:      ctx?.title      || '',
        url:        ctx?.url        || '',
        structured: ctx?.structured || undefined
      }
    };
  }

  // ---------- Native bridge (queued) ----------
  const TIMEOUT_MS = 8000;
  const queue = [];
  let inFlight = false;

  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const clone = (v) => { try { return JSON.parse(JSON.stringify(v ?? null)); } catch { return null; } };
  const isThenable = (x) => !!x && (typeof x === 'object' || typeof x === 'function') && typeof x.then === 'function';

  async function sendNativeRaw(message) {
    const RTN = RT && RT.sendNativeMessage;
    if (typeof RTN !== 'function') throw new Error('sendNativeMessage not available');

    const msg = clone(message) || {};

    // Attempt 1: Promise, 1-arg (Safari sometimes supports this)
    try {
      const r = RTN(msg);
      if (isThenable(r)) return await r;
    } catch (_) {}

    // Attempt 2: Promise, 2-arg with host hint (some WebKit builds accept this)
    try {
      const r = RTN('', msg);
      if (isThenable(r)) return await r;
    } catch (_) {}

    // Attempt 3: Callback, 2-arg (msg, cb)
    try {
      return await new Promise((resolve, reject) => {
        try {
          RTN(msg, (res) => {
            const le = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.lastError)
              ? chrome.runtime.lastError : null;
            if (le) reject(new Error(le.message || 'Native callback error'));
            else resolve(res);
          });
        } catch (e) { reject(e); }
      });
    } catch (_) {}

    // Attempt 4: Callback, 3-arg ('', msg, cb)
    try {
      return await new Promise((resolve, reject) => {
        try {
          RTN('', msg, (res) => {
            const le = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.lastError)
              ? chrome.runtime.lastError : null;
            if (le) reject(new Error(le.message || 'Native callback error'));
            else resolve(res);
          });
        } catch (e) { reject(e); }
      });
    } catch (_) {}

    throw new Error('Native bridge unavailable (sendNativeMessage did not resolve)');
  }

  function withTimeout(promise, ms, tag = 'native') {
    let t;
    const killer = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${tag} timeout`)), ms); });
    return Promise.race([promise, killer]).finally(() => clearTimeout(t));
  }

  async function runQueue() {
    if (inFlight) return;
    const job = queue.shift();
    if (!job) return;
    inFlight = true;
    try {
      const res = await withTimeout(sendNativeRaw(job.message), TIMEOUT_MS, 'native');
      job.resolve(
        (res && typeof res === 'object' && ('ok' in res))
          ? res
          : { ok: false, message: 'Empty native reply.' }
      );
    } catch (e) {
      job.resolve({ ok: false, message: (e && e.message) || 'Native bridge error.' });
    } finally {
      inFlight = false;
      await sleep(0);
      void runQueue();
    }
  }

  function enqueueNative(message) {
    return new Promise((resolve) => { queue.push({ message, resolve }); void runQueue(); });
  }

  async function handleCommand(request, sender) {
    if (!request || typeof request !== 'object') return { ok: false, message: 'Bad request.' };
    const cmd = String(request.cmd || '');

    if (cmd === 'selUpdate')  return setCtxFromSender(sender, request.payload || {});
    if (cmd === 'getPageCtx') {
      const tabId = (typeof request.tabId === 'number') ? request.tabId : sender?.tab?.id;
      return await getCtx(tabId);
    }
    if (cmd === 'native') {
      const action = String(request.action || '');
      const payload = clone(request.payload) || {};
      if (!action) return { ok: false, message: 'Missing action.' };
      return await enqueueNative({ action, payload });
    }
    if (cmd === 'echo') return { ok: true };

    return { ok: false, message: 'Unknown command.' };
  }

  // Safari-safe: reply via sendResponse and return true for async.
  RT.onMessage.addListener((request, sender, sendResponse) => {
    Promise.resolve(handleCommand(request, sender)).then((res) => {
      // Ensure popup always gets a shaped reply
      if (res && typeof res === 'object' && ('ok' in res)) { sendResponse(res); }
      else { sendResponse({ ok: false, message: 'Empty native reply.' }); }
    });
    return true; // keep the channel open for async
  });
})();
