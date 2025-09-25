// Keep last {selection,title,url} fresh, even when the popup steals focus.
(() => {
  const RT = (typeof chrome !== 'undefined' && chrome.runtime) ||
             (typeof browser !== 'undefined' && browser.runtime);
  if (!RT) return;

  function textSel() {
    try {
      let s = (window.getSelection && String(window.getSelection())) || '';
      if (!s && document.activeElement) {
        const el = document.activeElement;
        if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
          const v = el.value || '';
          if (typeof el.selectionStart === 'number' && typeof el.selectionEnd === 'number') {
            s = v.substring(el.selectionStart, el.selectionEnd);
          } else {
            s = v;
          }
        }
        if (el.isContentEditable) s = el.innerText || el.textContent || '';
      }
      s = s.replace(/\s+/g, ' ').trim();
      if (!s) {
        const meta = document.querySelector('meta[name="description"]');
        s = (meta && meta.content) ? meta.content.trim() : '';
      }
      return s.slice(0, 4000);
    } catch { return ''; }
  }

  function pageTitle() {
    try {
      const og = document.querySelector('meta[property="og:title"]');
      return (og && og.content) ? og.content : (document.title || '');
    } catch { return ''; }
  }

  function canonicalURL() {
    try {
      const link = document.querySelector('link[rel="canonical"]');
      if (link && link.href) return link.href;
      const og = document.querySelector('meta[property="og:url"]');
      if (og && og.content) return og.content;
      return (document.location && document.location.href) || '';
    } catch { return ''; }
  }

  let scheduled = false;
  function push() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      try {
        RT.sendMessage({
          cmd: 'selUpdate',
          payload: { selection: textSel(), title: pageTitle(), url: canonicalURL() }
        });
      } catch {}
    }, 50);
  }

  push();
  document.addEventListener('selectionchange', push, { passive: true });
  document.addEventListener('pointerup',        push, { passive: true });
  document.addEventListener('keyup',            push, { passive: true });
  document.addEventListener('visibilitychange', () => { if (document.hidden) push(); }, { passive: true });
  window.addEventListener('pagehide', push, { passive: true });
})();
