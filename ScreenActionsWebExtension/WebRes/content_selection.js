// Capture selection/title/url + lightweight JSON-LD (Event/Person) and stream to background.
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
          } else { s = v; }
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

  function parseJSONLD() {
    const out = {};
    try {
      const nodes = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
      for (const n of nodes) {
        let json; try { json = JSON.parse(n.textContent || ''); } catch { continue; }
        const items = Array.isArray(json) ? json : [json];
        for (const item of items) {
          const t = item && item['@type'];
          const types = Array.isArray(t) ? t.map(String) : [String(t || '')];
          if (types.includes('Event') && !out.event) {
            const loc = item.location || {};
            const addr = loc.address || {};
            out.event = {
              name: item.name || '',
              startDate: item.startDate || '',
              endDate: item.endDate || '',
              locationName: loc.name || '',
              address: {
                street: addr.streetAddress || '',
                city: addr.addressLocality || '',
                state: addr.addressRegion || '',
                postalCode: addr.postalCode || '',
                country: addr.addressCountry || ''
              }
            };
          }
          if ((types.includes('Person') || types.includes('Organization')) && !out.person) {
            out.person = {
              name: item.name || '',
              email: (Array.isArray(item.email) ? item.email[0] : item.email) || '',
              telephone: (Array.isArray(item.telephone) ? item.telephone[0] : item.telephone) || ''
            };
          }
          if (out.event && out.person) break;
        }
        if (out.event && out.person) break;
      }
    } catch {}
    return (out.event || out.person) ? out : undefined;
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
          payload: {
            selection: textSel(),
            title: pageTitle(),
            url: canonicalURL(),
            structured: parseJSONLD()
          }
        });
      } catch {}
    }, 50);
  }

  // First sample + updates
  push();
  document.addEventListener('selectionchange', push, { passive: true });
  document.addEventListener('pointerup',        push, { passive: true });
  document.addEventListener('keyup',            push, { passive: true });
  document.addEventListener('visibilitychange', () => { if (document.hidden) push(); }, { passive: true });
  window.addEventListener('pagehide', push, { passive: true });
})();
