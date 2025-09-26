// content_selection.js — push selection/title/url to background cache.
(function () {
  'use strict';
  const RT = (typeof browser !== 'undefined' && browser.runtime)
    ? browser.runtime
    : (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime : undefined;
  if (!RT) return;

  function snapshot() {
    const selection = String(window.getSelection?.().toString() || '').slice(0, 20000);
    const title = document.title || '';
    const url = location.href || '';
    return { selection, title, url, structured: undefined };
  }

  let last = '';
  function push(force = false) {
    const s = snapshot();
    const key = `${s.selection}\n${s.title}\n${s.url}`;
    if (!force && key === last) return;
    last = key;
    try { RT.sendMessage({ cmd: 'selUpdate', payload: s }); } catch {}
  }

  document.addEventListener('selectionchange', () => push(false), { passive: true });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) push(true); }, { passive: true });
  window.addEventListener('focus', () => push(true), { passive: true });

  push(true);
})();
