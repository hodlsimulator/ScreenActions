// background.js — cache page context; queue native calls; NEVER auto-OK empty replies.

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

  // ---- Per-tab context ------------------------------------------------------
  // tabId -> { selection, title, url, structured?, ts }
  const selStore = new Map();

  function setCtxFromSender(sender, payload) {
    const tabId = sender?.tab?.id;
    if (typeof tabId !== 'number') return { ok: false, message: 'No tab.' };
    const selection  = String(payload?.selection || '').trim();
    const title      = String(payload?.title || '');
    const url        = String(payload?.url || '');
    const structured = (payload && typeof payload.structured === 'object') ? payload.structured : undefined;
    selStore.set(tabId, { selection, title, url, structured, ts: Date.now() });
    try { console.info('[BG] selUpdate', { tabId, len: selection.length, title, url }); } catch {}
    return { ok: true };
  }

  async function getActiveTabId() {
    if (!TABS?.query) return undefined;
    try { const [tab] = await TABS.query({ active: true, currentWindow: true }); return tab?.id; }
    catch { return undefined; }
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

  // ---- Native bridge (queued) ----------------------------------------------
  const TIMEOUT_MS = 8000;
  const HOST_HINT = '';
  const queue = [];
  let inFlight = false;

  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  function withTimeout(promise, ms, tag = 'native') {
    let t; const killer = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${tag} timeout`)), ms); });
    return Promise.race([promise, killer]).finally(() => clearTimeout(t));
  }

  function deepClone(v) { try { return JSON.parse(JSON.stringify(v ?? null)); } catch { return null; } }

  async function sendNativeRaw(message) {
    const msg = deepClone(message) || {};
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
    const job = queue.shift(); if (!job) return;
    inFlight = true;
    try {
      const res = await withTimeout(sendNativeRaw(job.message), TIMEOUT_MS, 'native');
      try { console.info('[BG] native reply', job.message?.action, res); } catch {}
      job.resolve(res);
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
        resolve: (value) => {
          // IMPORTANT: do NOT auto-OK empty/undefined replies.
          if (value && typeof value === 'object' && ('ok' in value)) {
            resolve(value);
          } else {
            resolve({ ok: false, message: 'Empty native reply.' });
          }
        },
        reject:  (error) => {
          const msg = (error && typeof error.message === 'string' && error.message) || 'Native bridge error.';
          resolve({ ok: false, message: msg });
        }
      };
      queue.push(wrapped);
      void runQueue();
    });
  }

  // ---- Commands -------------------------------------------------------------
  async function handleCommand(request, sender) {
    if (!request || typeof request !== 'object') return { ok: false, message: 'Bad request.' };
    const cmd = String(request.cmd || '');

    if (cmd === 'selUpdate') return setCtxFromSender(sender, request.payload || {});
    if (cmd === 'getPageCtx') {
      const tabId = (typeof request.tabId === 'number') ? request.tabId : sender?.tab?.id;
      return await getCtx(tabId);
    }
    if (cmd === 'echo') return { ok: true };

    if (cmd === 'native') {
      const action = String(request.action || '');
      const payload = deepClone(request.payload) || {};
      if (!action) return { ok: false, message: 'Missing action.' };
      return await enqueueNative({ action, payload });
    }
    return { ok: false, message: 'Unknown command.' };
  }

  RT.onMessage.addListener((request, sender) => handleCommand(request, sender));
})();
