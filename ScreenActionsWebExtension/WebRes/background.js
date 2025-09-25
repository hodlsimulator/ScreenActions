// background.js — queues native calls; caches {selection,title,url,structured}

(() => {
  'use strict';

  const RT =
    (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime :
    (typeof browser !== 'undefined' && browser.runtime) ? browser.runtime :
    undefined;

  const TABS =
    (typeof chrome !== 'undefined' && chrome.tabs) ? chrome.tabs :
    (typeof browser !== 'undefined' && browser.tabs) ? browser.tabs :
    undefined;

  if (!RT) return;

  // ---- Selection store (per-tab)
  // tabId -> { selection, title, url, structured?, ts }
  const selStore = new Map();

  function setCtxFromSender(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok: false, message: 'No tab.' };
    const selection = String(payload?.selection || '').trim();
    const title = String(payload?.title || '');
    const url = String(payload?.url || '');
    const structured = (payload && typeof payload.structured === 'object') ? payload.structured : undefined;
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

  // ---- Native messaging (queued)
  const TIMEOUT_MS = 8000;
  const HOST_HINT = '';
  const queue = [];
  let inFlight = false;

  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const ok  = (extra = {}) => ({ ok: true,  ...extra });
  const err = (message = 'Native bridge error.') => ({ ok: false, message });
  const clone = (v) => { try { return JSON.parse(JSON.stringify(v ?? null)); } catch { return null; } };

  function withTimeout(promise, ms, tag = 'native') {
    let t;
    const killer = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${tag} timeout`)), ms); });
    return Promise.race([promise, killer]).finally(() => clearTimeout(t));
  }

  async function sendNativeRaw(message) {
    const msg = clone(message) || {};
    const fn = RT.sendNativeMessage;
    if (typeof fn !== 'function') throw new Error('sendNativeMessage not available.');
    try { return await fn(msg); }
    catch (e1) {
      try { return await fn(HOST_HINT, msg); }
      catch (e2) {
        if (fn.length >= 3) {
          return await new Promise((resolve, reject) => {
            try {
              fn(HOST_HINT, msg, (res) => {
                const le = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.lastError) ? chrome.runtime.lastError : null;
                if (le) reject(new Error(le.message || 'Native callback error.')); else resolve(res);
              });
            } catch (e3) { reject(e3); }
          });
        }
        throw (e2 || e1);
      }
    }
  }

  async function runQueue() {
    if (inFlight) return;
    const job = queue.shift();
    if (!job) return;
    inFlight = true;
    try {
      const result = await withTimeout(sendNativeRaw(job.message), TIMEOUT_MS, 'native');
      try { console.log('[BG] native reply:', job.message?.action, result); } catch {}
      job.resolve(result);
    } catch (e) {
      job.reject(e);
    } finally {
      inFlight = false;
      await sleep(0);
      void runQueue();
    }
  }

  function enqueueNative(message) {
    return new Promise((resolve) => {
      const wrapped = {
        message,
        resolve: (value) => resolve(value ?? ok()),
        reject:  (error) => resolve(err((error && error.message) ? String(error.message) : 'Native bridge error.'))
      };
      queue.push(wrapped);
      void runQueue();
    });
  }

  // ---- Commands
  async function handleCommand(request, sender) {
    if (!request || typeof request !== 'object') return err('Bad request.');
    const cmd = String(request.cmd || '');

    if (cmd === 'selUpdate') return setCtxFromSender(sender, request.payload || {});
    if (cmd === 'getPageCtx') {
      const tabId = (typeof request.tabId === 'number') ? request.tabId : sender?.tab?.id;
      return await getCtx(tabId);
    }
    if (cmd === 'echo') return ok({ echo: clone(request.payload) });

    if (cmd === 'native') {
      const action = String(request.action || '');
      const payload = clone(request.payload) || {};
      if (!action) return err('Missing action.');
      return await enqueueNative({ action, payload });
    }
    return err('Unknown command.');
  }

  RT.onMessage.addListener((request, sender) => handleCommand(request, sender));
  RT.onConnect.addListener((port) => {
    try {
      port.onMessage.addListener(async (request) => {
        const out = await handleCommand(request, port.sender);
        try { port.postMessage(out); } catch {}
      });
    } catch {}
  });
})();
