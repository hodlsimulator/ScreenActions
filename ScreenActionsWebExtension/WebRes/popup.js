// popup.js — home sheet stays simple; editors open only after tap.
// Prefill comes from native prepare*; save via native save*.

(() => {
  'use strict';

  const RT = (typeof chrome !== 'undefined' && chrome.runtime)
    ? chrome.runtime
    : (typeof browser !== 'undefined' && browser.runtime)
      ? browser.runtime
      : undefined;

  if (!RT) return;

  // ---------- DOM helpers ----------
  const el = (id) => document.getElementById(id);
  const pad2 = (n) => String(n).padStart(2, '0');

  function setStatus(where, msg, ok) {
    const node = el(where);
    if (!node) return;
    node.textContent = msg || '';
    node.classList.remove('ok', 'err');
    if (msg) node.classList.add(ok ? 'ok' : 'err');
  }

  function showView(name) {
    for (const s of document.querySelectorAll('.view')) s.classList.remove('active');
    el(name)?.classList.add('active');
  }

  function toInputLocal(d) {
    const y = d.getFullYear();
    const m = pad2(d.getMonth() + 1);
    const da = pad2(d.getDate());
    const h = pad2(d.getHours());
    const mi = pad2(d.getMinutes());
    return `${y}-${m}-${da}T${h}:${mi}`;
  }
  function fromInputLocal(s) {
    const d = new Date(s);
    return isNaN(d) ? null : d.toISOString();
  }

  // ---------- BG bridge ----------
  function bg(cmd, payload = {}) {
    return RT.sendMessage({ cmd, ...payload });
  }
  function bgNative(action, payload = {}) {
    return bg('native', { action, payload });
  }

  // ---------- Prefill helpers ----------
  function fillEventFields(fields) {
    el('evTitle').value = fields.title || 'Event';
    const s = fields.startISO ? new Date(fields.startISO) : new Date();
    const e = fields.endISO ? new Date(fields.endISO) : new Date(Date.now() + 3600_000);
    el('evStart').value = toInputLocal(s);
    el('evEnd').value = toInputLocal(e);
    el('evLocation').value = fields.location || '';
    el('evInferTZ').checked = !!fields.inferTZ;
    el('evAlert').value = (typeof fields.alertMinutes === 'number' && fields.alertMinutes > 0)
      ? String(fields.alertMinutes) : '';
    el('evNotes').value = fields.notes || '';
  }

  function fillReminderFields(fields) {
    el('remTitle').value = fields.title || 'Todo';
    const hasDue = !!fields.hasDue;
    el('remHasDue').checked = hasDue;
    el('remDue').disabled = !hasDue;
    if (fields.dueISO) el('remDue').value = toInputLocal(new Date(fields.dueISO));
    else el('remDue').value = '';
    el('remNotes').value = fields.notes || '';
  }

  function rowFor(listId, val, placeholder) {
    const row = document.createElement('div');
    row.className = 'row';
    const input = document.createElement('input');
    input.type = 'text';
    input.value = val || '';
    input.placeholder = placeholder;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = '✕';
    btn.addEventListener('click', () => row.remove());
    row.appendChild(input);
    row.appendChild(btn);
    el(listId).appendChild(row);
  }

  function fillContactFields(fields) {
    el('ctGiven').value = fields.givenName || '';
    el('ctFamily').value = fields.familyName || '';

    el('emails').textContent = '';
    const emails = Array.isArray(fields.emails) ? fields.emails : [];
    if (emails.length === 0) rowFor('emails', '', 'name@example.com');
    else for (const e of emails) rowFor('emails', e, 'name@example.com');

    el('phones').textContent = '';
    const phones = Array.isArray(fields.phones) ? fields.phones : [];
    if (phones.length === 0) rowFor('phones', '', '+353 1 234 5678');
    else for (const p of phones) rowFor('phones', p, '+353 1 234 5678');

    el('ctStreet').value = fields.street || '';
    el('ctCity').value = fields.city || '';
    el('ctState').value = fields.state || '';
    el('ctPostal').value = fields.postalCode || '';
    el('ctCountry').value = fields.country || '';
  }

  function fillCSV(text, csv) {
    el('csvInput').value = (typeof text === 'string') ? text : '';
    el('csvOut').textContent = (typeof csv === 'string') ? csv : '';
  }

  function gatherEventFields() {
    const title = el('evTitle').value.trim();
    const startISO = fromInputLocal(el('evStart').value);
    const endISO = fromInputLocal(el('evEnd').value);
    const location = el('evLocation').value.trim();
    const inferTZ = el('evInferTZ').checked;
    const alertMinutes = el('evAlert').value ? parseInt(el('evAlert').value, 10) : undefined;
    const notes = el('evNotes').value;

    return {
      title: title || 'Event',
      startISO, endISO,
      location,
      inferTZ,
      alertMinutes,
      notes
    };
  }
  function gatherReminderFields() {
    const title = el('remTitle').value.trim() || 'Todo';
    const hasDue = el('remHasDue').checked;
    const dueISO = hasDue ? fromInputLocal(el('remDue').value) : undefined;
    const notes = el('remNotes').value;
    return { title, hasDue, dueISO, notes };
  }
  function gatherContactFields() {
    const givenName = el('ctGiven').value.trim();
    const familyName = el('ctFamily').value.trim();
    const emails = Array.from(el('emails').querySelectorAll('input'))
      .map(i => i.value.trim()).filter(Boolean);
    const phones = Array.from(el('phones').querySelectorAll('input'))
      .map(i => i.value.trim()).filter(Boolean);

    return {
      givenName, familyName, emails, phones,
      street: el('ctStreet').value,
      city: el('ctCity').value,
      state: el('ctState').value,
      postalCode: el('ctPostal').value,
      country: el('ctCountry').value
    };
  }

  // ---------- Boot ----------
  let cachedCtx = { selection: '', title: '', url: '', structured: undefined };

  async function ensureCtx() {
    const r = await bg('getPageCtx', {});
    if (r?.ok && r.ctx) cachedCtx = r.ctx;
    el('selText').textContent = cachedCtx.selection || cachedCtx.title || cachedCtx.url || '';
  }

  async function doPrepare(kind) {
    const action = ({
      event: 'prepareEvent',
      reminder: 'prepareReminder',
      contact: 'prepareContact',
      csv: 'prepareReceiptCSV',
      auto: 'prepareAutoDetect'
    })[kind];
    return await bgNative(action, cachedCtx || {});
  }

  async function init() {
    // Navigation
    el('backEvent').addEventListener('click', () => { showView('home'); setStatus('statusEvent', ''); });
    el('backReminder').addEventListener('click', () => { showView('home'); setStatus('statusReminder', ''); });
    el('backContact').addEventListener('click', () => { showView('home'); setStatus('statusContact', ''); });
    el('backCSV').addEventListener('click', () => { showView('home'); setStatus('statusCSV', ''); });

    // Actions
    el('btnAuto').addEventListener('click', async () => {
      setStatus('statusHome', '', true);
      const r = await doPrepare('auto');
      if (!r?.ok) { setStatus('statusHome', r?.message || 'Failed.', false); return; }
      const route = r.route;
      if (route === 'event') { fillEventFields(r.fields || {}); showView('event'); }
      else if (route === 'reminder') { fillReminderFields(r.fields || {}); showView('reminder'); }
      else if (route === 'contact') { fillContactFields(r.fields || {}); showView('contact'); }
      else if (route === 'csv') { fillCSV(cachedCtx?.selection || '', r.csv || ''); showView('csv'); }
    });

    el('btnEvent').addEventListener('click', async () => {
      setStatus('statusHome', '', true);
      const r = await doPrepare('event');
      if (!r?.ok) { setStatus('statusHome', r?.message || 'Failed.', false); return; }
      fillEventFields(r.fields || {});
      showView('event');
    });

    el('btnReminder').addEventListener('click', async () => {
      setStatus('statusHome', '', true);
      const r = await doPrepare('reminder');
      if (!r?.ok) { setStatus('statusHome', r?.message || 'Failed.', false); return; }
      fillReminderFields(r.fields || {});
      showView('reminder');
    });

    el('btnContact').addEventListener('click', async () => {
      setStatus('statusHome', '', true);
      const r = await doPrepare('contact');
      if (!r?.ok) { setStatus('statusHome', r?.message || 'Failed.', false); return; }
      fillContactFields(r.fields || {});
      showView('contact');
    });

    el('btnCSV').addEventListener('click', async () => {
      setStatus('statusHome', '', true);
      const r = await doPrepare('csv');
      if (!r?.ok) { setStatus('statusHome', r?.message || 'Failed.', false); return; }
      fillCSV(cachedCtx?.selection || '', r.csv || '');
      showView('csv');
    });

    // Editor saves
    el('saveEvent').addEventListener('click', async () => {
      setStatus('statusEvent', 'Saving…', true);
      const r = await bgNative('saveEvent', { fields: gatherEventFields() });
      if (r?.ok) { setStatus('statusEvent', r.message || 'Saved.', true); window.close(); }
      else setStatus('statusEvent', r?.message || 'Failed.', false);
    });

    el('saveReminder').addEventListener('click', async () => {
      setStatus('statusReminder', 'Saving…', true);
      const r = await bgNative('saveReminder', { fields: gatherReminderFields() });
      if (r?.ok) { setStatus('statusReminder', r.message || 'Saved.', true); window.close(); }
      else setStatus('statusReminder', r?.message || 'Failed.', false);
    });

    el('saveContact').addEventListener('click', async () => {
      setStatus('statusContact', 'Saving…', true);
      const r = await bgNative('saveContact', { fields: gatherContactFields() });
      if (r?.ok) { setStatus('statusContact', r.message || 'Saved.', true); window.close(); }
      else setStatus('statusContact', r?.message || 'Failed.', false);
    });

    // CSV reparse/export
    el('reparseCSV').addEventListener('click', async () => {
      setStatus('statusCSV', 'Parsing…', true);
      const text = el('csvInput').value || (cachedCtx?.selection || '');
      const r = await bgNative('prepareReceiptCSV', { selection: text, title: cachedCtx?.title || '', url: cachedCtx?.url || '' });
      if (r?.ok) { el('csvOut').textContent = r.csv || ''; setStatus('statusCSV', 'Parsed.', true); }
      else setStatus('statusCSV', r?.message || 'Failed.', false);
    });

    el('exportCSV').addEventListener('click', async () => {
      setStatus('statusCSV', 'Exporting…', true);
      const csv = el('csvOut').textContent || '';
      const r = await bgNative('exportReceiptCSV', { csv });
      if (r?.ok) { setStatus('statusCSV', r.message || 'Exported.', true); window.close(); }
      else setStatus('statusCSV', r?.message || 'Failed.', false);
    });

    await ensureCtx(); // keep the home sheet exactly as before
  }

  document.addEventListener('DOMContentLoaded', init);
})();
