// Streams current selection/title/url (and light JSON-LD hints) to the background.
// Runs on every page; no UI changes.

(function () {
  'use strict';

  const RT = (typeof chrome !== 'undefined' && chrome.runtime)
    ? chrome.runtime
    : (typeof browser !== 'undefined' && browser.runtime)
      ? browser.runtime
      : undefined;
  if (!RT) return;

  function harvestStructured() {
    const out = {};
    try {
      const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
      for (const s of scripts) {
        let data; try { data = JSON.parse(s.textContent || ''); } catch { continue; }
        const arr = Array.isArray(data) ? data : [data];
        for (const it of arr) {
          const t = String(it['@type'] || it.type || '').toLowerCase();
          if (!out.event && t.includes('event')) {
            const loc = it.location || {};
            let locationName = '';
            let addr = null;
            if (typeof loc === 'string') locationName = loc;
            else if (loc && typeof loc === 'object') {
              locationName = typeof loc.name === 'string' ? loc.name : '';
              const a = loc.address || {};
              addr = {
                street: a.streetAddress || '',
                city: a.addressLocality || a.locality || '',
                state: a.addressRegion || a.region || '',
                postalCode: a.postalCode || '',
                country: a.addressCountry || ''
              };
            }
            out.event = {
              name: typeof it.name === 'string' ? it.name : '',
              startDate: typeof it.startDate === 'string' ? it.startDate : '',
              endDate: typeof it.endDate === 'string' ? it.endDate : '',
              locationName,
              address: addr
            };
          }
          if (!out.person && (t.includes('person') || t.includes('organization'))) {
            out.person = {
              name: typeof it.name === 'string' ? it.name : '',
              email: typeof it.email === 'string' ? it.email : '',
              telephone: typeof it.telephone === 'string' ? it.telephone : ''
            };
          }
        }
      }
    } catch {}
    return out;
  }

  function snapshot() {
    const selection = String(window.getSelection?.().toString() || '').slice(0, 20000);
    const title = document.title || '';
    const url = location.href || '';
    const structured = harvestStructured();
    return { selection, title, url, structured };
  }

  let lastSent = '';
  function maybeSend(force = false) {
    const snap = snapshot();
    const key = `${snap.selection}\n${snap.title}\n${snap.url}`;
    if (!force && key === lastSent) return;
    lastSent = key;
    RT.sendMessage({ cmd: 'selUpdate', payload: snap }).catch(() => {});
  }

  document.addEventListener('selectionchange', () => { maybeSend(false); }, { passive: true });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) maybeSend(true); }, { passive: true });
  window.addEventListener('focus', () => { maybeSend(true); }, { passive: true });

  // Initial push
  maybeSend(true);
})();
