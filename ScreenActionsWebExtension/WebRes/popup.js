// popup.js — iOS share-sheet UI for the Web Extension popup

(() => {
  'use strict';

  const RT = (typeof browser !== 'undefined' && browser.runtime)
    ? browser.runtime
    : (typeof chrome !== 'undefined' && chrome.runtime)
      ? chrome.runtime
      : null;

  if (!RT) return;

  const $  = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  // --- Runtime messaging helpers ----
  function send(req) {
    return new Promise((resolve, reject) => {
      try {
        RT.sendMessage(req, (out) => {
          const err = (chrome && chrome.runtime && chrome.runtime.lastError)
                   || (browser && browser.runtime && browser.runtime.lastError);
          if (err) reject(new Error(err.message || 'runtime error'));
          else resolve(out);
        });
      } catch (e) { reject(e); }
    });
  }
  const native = (action, payload={}) => send({ cmd: 'native', action, payload });
  const pageCtx = async () => {
    const out = await send({ cmd: 'getPageCtx' });
    return (out && out.ctx) ? out.ctx : { selection: '', title: '', url: '' };
  };

  // --- UI helpers ----
  function setHeader(mode, title) {
    $('#navTitle').textContent = title || 'Screen Actions';
    if (mode === 'home') {
      $('#navCancel').hidden = true;
      $('#navSave').hidden   = true;
    } else {
      $('#navCancel').hidden = false;
      $('#navSave').hidden   = false;
      $('#navCancel').textContent = 'Cancel';
      $('#navSave').textContent   = 'Save';
    }
  }
  function showView(id) { $$('.view').forEach(v => v.classList.toggle('active', v.id === id)); }
  function setStatus(sel, msg, ok) {
    const el = (typeof sel === 'string') ? $(sel) : sel;
    if (!el) return;
    el.textContent = msg || '';
    el.className = 'status ' + (ok ? 'ok' : 'err');
  }
  const pad = n => String(n).padStart(2, '0');
  function isoToLocal(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function localToISO(localStr) {
    if (!localStr) return null;
    const d = new Date(localStr);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }

  // --- Contact list row helpers ----
  function clearList(sel) { const el = $(sel); el.innerHTML = ''; return el; }
  function addListRow(container, value='') {
    const el = (typeof container === 'string') ? $(container) : container;
    const row = document.createElement('div');
    row.className = 'row';
    const input = document.createElement('input');
    input.type = 'text'; input.value = value;
    const del = document.createElement('button');
    del.type = 'button'; del.textContent = 'Remove';
    del.addEventListener('click', () => row.remove());
    row.appendChild(input); row.appendChild(del);
    el.appendChild(row);
  }

  // --- Save handlers (assigned dynamically by editors) ----
  let saveHandler = null;
  $('#navSave').addEventListener('click', async () => { if (typeof saveHandler === 'function') await saveHandler(); });

  // --- Home view ----
  async function showHome() {
    setHeader('home', 'Screen Actions');
    showView('home');
    setStatus('#statusHome', '', true);

    const ctx = await pageCtx();
    const text = `${(ctx.selection || ctx.title || '').trim()}${ctx.url ? `\n${ctx.url}` : ''}`.trim();
    $('#selText').textContent = text;

    saveHandler = null;
  }

  // --- Editors -------------------------------------------------------------

  async function openReminder() {
    const out = await native('prepareReminder', {});
    if (!out?.ok) { setStatus('#statusHome', out?.message || 'Failed.', false); return; }

    $('#remTitle').value = out.fields.title || '';
    $('#remHasDue').checked = !!out.fields.hasDue;
    $('#remDue').disabled = !$('#remHasDue').checked;
    $('#remDue').value = out.fields.dueISO ? isoToLocal(out.fields.dueISO) : '';
    $('#remNotes').value = out.fields.notes || '';

    setHeader('editor', 'New Reminder');
    showView('reminder');

    saveHandler = async () => {
      const fields = {
        title: $('#remTitle').value,
        hasDue: $('#remHasDue').checked,
        dueISO: $('#remHasDue').checked ? localToISO($('#remDue').value) : null,
        notes: $('#remNotes').value
      };
      const res = await native('saveReminder', { fields });
      setStatus('#statusReminder', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
      if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
    };
  }

  function fillEventFields(fields) {
    $('#evTitle').value    = fields.title || '';
    $('#evStart').value    = fields.startISO ? isoToLocal(fields.startISO) : '';
    $('#evEnd').value      = fields.endISO ? isoToLocal(fields.endISO) : '';
    $('#evLocation').value = fields.location || '';
    $('#evInferTZ').checked = !!fields.inferTZ;
    $('#evAlert').value     = (fields.alertMinutes != null) ? String(fields.alertMinutes) : '';
  }
  async function saveEventWithNotes(notes) {
    const fields = {
      title: $('#evTitle').value,
      startISO: localToISO($('#evStart').value),
      endISO:   localToISO($('#evEnd').value),
      location: $('#evLocation').value,
      inferTZ:  $('#evInferTZ').checked,
      alertMinutes: parseInt($('#evAlert').value || '0', 10) || 0,
      notes
    };
    const res = await native('saveEvent', { fields });
    setStatus('#statusEvent', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
    if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
  }
  async function openEvent() {
    const out = await native('prepareEvent', {});
    if (!out?.ok) { setStatus('#statusHome', out?.message || 'Failed.', false); return; }
    fillEventFields(out.fields);
    setHeader('editor', 'New Event');
    showView('event');
    saveHandler = async () => saveEventWithNotes(out.fields.notes || '');
  }

  async function openContact() {
    const out = await native('prepareContact', {});
    if (!out?.ok) { setStatus('#statusHome', out?.message || 'Failed.', false); return; }

    $('#ctGiven').value  = out.fields.givenName || '';
    $('#ctFamily').value = out.fields.familyName || '';
    const emails = clearList('#emails'); (out.fields.emails || ['']).forEach(v => addListRow(emails, v));
    const phones = clearList('#phones'); (out.fields.phones || ['']).forEach(v => addListRow(phones, v));
    $('#ctStreet').value = out.fields.street || '';
    $('#ctCity').value   = out.fields.city || '';
    $('#ctState').value  = out.fields.state || '';
    $('#ctPostal').value = out.fields.postalCode || '';
    $('#ctCountry').value = out.fields.country || '';

    setHeader('editor', 'New Contact');
    showView('contact');

    saveHandler = async () => {
      const fields = {
        givenName: $('#ctGiven').value,
        familyName: $('#ctFamily').value,
        emails: $$('#emails .row input').map(i => i.value).filter(Boolean),
        phones: $$('#phones .row input').map(i => i.value).filter(Boolean),
        street: $('#ctStreet').value,
        city: $('#ctCity').value,
        state: $('#ctState').value,
        postalCode: $('#ctPostal').value,
        country: $('#ctCountry').value
      };
      const res = await native('saveContact', { fields });
      setStatus('#statusContact', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
      if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
    };
  }

  async function openCSV() {
    const ctx = await pageCtx();
    $('#csvInput').value = `${(ctx.selection || ctx.title || '').trim()}${ctx.url ? `\n${ctx.url}` : ''}`.trim();

    const out = await native('prepareReceiptCSV', {});
    if (out?.ok) $('#csvOut').textContent = out.csv || '';
    else setStatus('#statusHome', out?.message || 'Failed.', false);

    setHeader('editor', 'Receipt → CSV');
    showView('csv');

    saveHandler = async () => {
      const res = await native('exportReceiptCSV', { csv: $('#csvOut').textContent || '' });
      setStatus('#statusCSV', res?.message || (res?.ok ? 'Exported.' : ''), !!res?.ok);
      if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
    };
  }

  // --- Auto detect routes to the right editor and pre-fills fields ----
  async function openAuto() {
    const out = await native('prepareAutoDetect', {});
    if (!out?.ok) { setStatus('#statusHome', out?.message || 'Failed.', false); return; }
    switch (out.route) {
      case 'event':
        fillEventFields(out.fields); setHeader('editor', 'New Event'); showView('event');
        saveHandler = async () => saveEventWithNotes(out.fields.notes || '');
        break;
      case 'reminder':
        $('#remTitle').value = out.fields.title || '';
        $('#remHasDue').checked = !!out.fields.hasDue;
        $('#remDue').disabled = !$('#remHasDue').checked;
        $('#remDue').value = out.fields.dueISO ? isoToLocal(out.fields.dueISO) : '';
        $('#remNotes').value = out.fields.notes || '';
        setHeader('editor', 'New Reminder'); showView('reminder');
        saveHandler = async () => {
          const fields = {
            title: $('#remTitle').value,
            hasDue: $('#remHasDue').checked,
            dueISO: $('#remHasDue').checked ? localToISO($('#remDue').value) : null,
            notes: $('#remNotes').value
          };
          const res = await native('saveReminder', { fields });
          setStatus('#statusReminder', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
          if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
        };
        break;
      case 'contact':
        $('#ctGiven').value = out.fields.givenName || '';
        $('#ctFamily').value = out.fields.familyName || '';
        const emails = clearList('#emails'); (out.fields.emails || ['']).forEach(v => addListRow(emails, v));
        const phones = clearList('#phones'); (out.fields.phones || ['']).forEach(v => addListRow(phones, v));
        $('#ctStreet').value = out.fields.street || '';
        $('#ctCity').value = out.fields.city || '';
        $('#ctState').value = out.fields.state || '';
        $('#ctPostal').value = out.fields.postalCode || '';
        $('#ctCountry').value = out.fields.country || '';
        setHeader('editor', 'New Contact'); showView('contact');
        saveHandler = async () => {
          const fields = {
            givenName: $('#ctGiven').value,
            familyName: $('#ctFamily').value,
            emails: $$('#emails .row input').map(i => i.value).filter(Boolean),
            phones: $$('#phones .row input').map(i => i.value).filter(Boolean),
            street: $('#ctStreet').value, city: $('#ctCity').value,
            state: $('#ctState').value, postalCode: $('#ctPostal').value, country: $('#ctCountry').value
          };
          const res = await native('saveContact', { fields });
          setStatus('#statusContact', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
          if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
        };
        break;
      case 'csv':
        setHeader('editor', 'Receipt → CSV'); showView('csv');
        $('#csvOut').textContent = out.csv || '';
        saveHandler = async () => {
          const res = await native('exportReceiptCSV', { csv: $('#csvOut').textContent || '' });
          setStatus('#statusCSV', res?.message || (res?.ok ? 'Exported.' : ''), !!res?.ok);
          if (res?.ok) { await native('hapticSuccess'); setTimeout(showHome, 450); }
        };
        break;
      default:
        setStatus('#statusHome', 'Could not route selection.', false);
    }
  }

  // --- Wiring --------------------------------------------------------------
  document.addEventListener('DOMContentLoaded', () => {
    // Home buttons
    $('#btnAuto').addEventListener('click', openAuto);
    $('#btnReminder').addEventListener('click', openReminder);
    $('#btnEvent').addEventListener('click', openEvent);
    $('#btnContact').addEventListener('click', openContact);
    $('#btnCSV').addEventListener('click', openCSV);

    // Editor affordances
    $('#navCancel').addEventListener('click', showHome);
    $('#remHasDue').addEventListener('change', (e) => { $('#remDue').disabled = !e.target.checked; });
    $('#addEmail').addEventListener('click', () => addListRow('#emails', ''));
    $('#addPhone').addEventListener('click', () => addListRow('#phones', ''));

    showHome();
  });
})();
