// popup.js — full-sheet popup; Reminder editor matches Share sheet.
// Round tick (top-right) saves; bottom-centre Cancel returns to Home.

(() => {
  'use strict';

  const RT =
    (typeof browser !== 'undefined' && browser.runtime) ? browser.runtime :
    (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime : null;
  if (!RT) return;

  const $  = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  // Close the whole popup if the (hidden) top Cancel is ever tapped.
  const navCancel = $('#navCancel');
  if (navCancel) {
    navCancel.addEventListener('click', () => { try { window.close(); } catch {} });
  }

  // ----- Messaging
  function send(req){
    return new Promise((resolve, reject) => {
      try {
        RT.sendMessage(req, (out) => {
          const err = (chrome && chrome.runtime && chrome.runtime.lastError) ||
                      (browser && browser.runtime && browser.runtime.lastError);
          if (err) reject(new Error(err.message || 'runtime error'));
          else resolve(out);
        });
      } catch (e) { reject(e); }
    });
  }
  const native  = (action, payload={}) => send({ cmd: 'native', action, payload });
  const pageCtx = async () => {
    const out = await send({ cmd: 'getPageCtx' });
    return (out && out.ctx) ? out.ctx : { selection:'', title:'', url:'' };
  };

  // ----- UI helpers
  function show(id){
    $$('.view').forEach(v => v.classList.toggle('active', v.id === id));
    // Only show floating tick on the Reminder editor.
    const showTick = (id === 'reminder');
    $('#navConfirm').style.display = showTick ? 'flex' : 'none';
  }
  function setStatus(sel, msg, ok){
    const el = (typeof sel === 'string') ? $(sel) : sel;
    if (!el) return;
    el.textContent = msg || '';
    el.className = 'status ' + (ok ? 'ok' : 'err');
  }

  const pad = n => String(n).padStart(2,'0');
  const isoToLocal = (iso) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };
  const localToISO = (s) => {
    if (!s) return null;
    const d = new Date(s);
    return isNaN(d.getTime()) ? null : d.toISOString();
  };

  // ----- Contact list helpers
  function clearList(sel){ const el = $(sel); el.innerHTML = ''; return el; }
  function addListRow(container, value=''){
    const el = (typeof container === 'string') ? $(container) : container;
    const row = document.createElement('div');
    row.className = 'row';
    const input = document.createElement('input');
    input.type = 'text'; input.value = value;
    const del = document.createElement('button');
    del.type = 'button'; del.textContent = 'Remove';
    del.addEventListener('click', () => row.remove());
    row.appendChild(input); row.appendChild(del); el.appendChild(row);
  }

  // ----- HOME
  async function showHome(){
    $('#navTitle').textContent = 'Screen Actions';
    show('home');
    const ctx = await pageCtx();
    const text = `${(ctx.selection || ctx.title || '').trim()}${ctx.url ? `\n${ctx.url}` : ''}`.trim();
    $('#selText').textContent = text;
  }

  // ----- Editors
  let onSave = null; // set by the currently presented editor

  // Present Reminder (shared by openReminder + AutoDetect route)
  function presentReminder(fields){
    $('#remTitle').value = fields.title || '';
    $('#remHasDue').checked = !!fields.hasDue;
    $('#remDue').disabled = !$('#remHasDue').checked;
    $('#remDueRow').style.display = $('#remHasDue').checked ? '' : 'none';
    $('#remDue').value = fields.dueISO ? isoToLocal(fields.dueISO) : '';
    $('#remNotes').value = fields.notes || '';

    $('#navTitle').textContent = 'New Reminder';
    show('reminder');

    onSave = async () => {
      const payload = {
        title:  $('#remTitle').value,
        hasDue: $('#remHasDue').checked,
        dueISO: $('#remHasDue').checked ? localToISO($('#remDue').value) : null,
        notes:  $('#remNotes').value
      };
      const res = await native('saveReminder', { fields: payload });
      if (res?.ok){
        // show confirmation on Home, like Share sheet
        setStatus('#statusHome', res?.message || 'Reminder created.', true);
        showHome();
      } else {
        setStatus('#statusReminder', res?.message || 'Failed.', false);
      }
    };
  }

  async function openReminder(){
    const out = await native('prepareReminder', {});
    if (!out?.ok){
      setStatus('#statusHome', out?.message || 'Failed.', false);
      return;
    }
    presentReminder(out.fields);
  }

  function fillEventFields(fields){
    $('#evTitle').value = fields.title || '';
    $('#evStart').value = fields.startISO ? isoToLocal(fields.startISO) : '';
    $('#evEnd').value   = fields.endISO   ? isoToLocal(fields.endISO)   : '';
    $('#evLocation').value = fields.location || '';
    $('#evInferTZ').checked = !!fields.inferTZ;
    $('#evAlert').value = (fields.alertMinutes != null) ? String(fields.alertMinutes) : '';
  }

  async function saveEventWithNotes(notes){
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
    if (res?.ok) setTimeout(showHome, 450);
  }

  async function openEvent(){
    const out = await native('prepareEvent', {});
    if (!out?.ok){
      setStatus('#statusHome', out?.message || 'Failed.', false);
      return;
    }
    fillEventFields(out.fields);
    $('#navTitle').textContent = 'New Event';
    show('event');
    onSave = async () => saveEventWithNotes(out.fields.notes || '');
  }

  async function openContact(){
    const out = await native('prepareContact', {});
    if (!out?.ok){
      setStatus('#statusHome', out?.message || 'Failed.', false);
      return;
    }
    $('#ctGiven').value = out.fields.givenName || '';
    $('#ctFamily').value = out.fields.familyName || '';
    const emails = clearList('#emails'); (out.fields.emails || ['']).forEach(v => addListRow(emails, v));
    const phones = clearList('#phones'); (out.fields.phones || ['']).forEach(v => addListRow(phones, v));
    $('#ctStreet').value = out.fields.street || '';
    $('#ctCity').value = out.fields.city || '';
    $('#ctState').value = out.fields.state || '';
    $('#ctPostal').value = out.fields.postalCode || '';
    $('#ctCountry').value = out.fields.country || '';

    $('#navTitle').textContent = 'New Contact';
    show('contact');
    onSave = async () => {
      const fields = {
        givenName: $('#ctGiven').value,
        familyName: $('#ctFamily').value,
        emails: $$('#emails .row input').map(i => i.value).filter(Boolean),
        phones: $$('#phones .row input').map(i => i.value).filter(Boolean),
        street: $('#ctStreet').value, city: $('#ctCity').value, state: $('#ctState').value,
        postalCode: $('#ctPostal').value, country: $('#ctCountry').value
      };
      const res = await native('saveContact', { fields });
      setStatus('#statusContact', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
      if (res?.ok) setTimeout(showHome, 450);
    };
  }

  async function openCSV(){
    const ctx = await pageCtx();
    $('#csvInput').value = `${(ctx.selection || ctx.title || '').trim()}${ctx.url ? `\n${ctx.url}` : ''}`.trim();
    const out = await native('prepareReceiptCSV', {});
    if (out?.ok) $('#csvOut').textContent = out.csv || '';
    else setStatus('#statusHome', out?.message || 'Failed.', false);
    $('#navTitle').textContent = 'Receipt → CSV';
    show('csv');
    onSave = async () => {
      const res = await native('exportReceiptCSV', { csv: $('#csvOut').textContent || '' });
      setStatus('#statusCSV', res?.message || (res?.ok ? 'Exported.' : ''), !!res?.ok);
      if (res?.ok) setTimeout(showHome, 450);
    };
  }

  // Auto Detect
  async function openAuto(){
    const out = await native('prepareAutoDetect', {});
    if (!out?.ok){
      setStatus('#statusHome', out?.message || 'Failed.', false);
      return;
    }
    switch (out.route) {
      case 'event':
        fillEventFields(out.fields);
        $('#navTitle').textContent = 'New Event';
        show('event');
        onSave = async () => saveEventWithNotes(out.fields.notes || '');
        break;
      case 'reminder':
        presentReminder(out.fields);
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
        $('#navTitle').textContent = 'New Contact';
        show('contact');
        onSave = async () => {
          const fields = {
            givenName: $('#ctGiven').value,
            familyName: $('#ctFamily').value,
            emails: $$('#emails .row input').map(i => i.value).filter(Boolean),
            phones: $$('#phones .row input').map(i => i.value).filter(Boolean),
            street: $('#ctStreet').value, city: $('#ctCity').value, state: $('#ctState').value,
            postalCode: $('#ctPostal').value, country: $('#ctCountry').value
          };
          const res = await native('saveContact', { fields });
          setStatus('#statusContact', res?.message || (res?.ok ? 'Saved.' : ''), !!res?.ok);
          if (res?.ok) setTimeout(showHome, 450);
        };
        break;
      case 'csv':
        $('#navTitle').textContent = 'Receipt → CSV';
        show('csv');
        $('#csvOut').textContent = out.csv || '';
        onSave = async () => {
          const res = await native('exportReceiptCSV', { csv: $('#csvOut').textContent || '' });
          setStatus('#statusCSV', res?.message || (res?.ok ? 'Exported.' : ''), !!res?.ok);
          if (res?.ok) setTimeout(showHome, 450);
        };
        break;
      default:
        setStatus('#statusHome', 'Could not route selection.', false);
    }
  }

  // Wire up
  document.addEventListener('DOMContentLoaded', () => {
    // Reminder toggle row & due input
    $('#remHasDue').addEventListener('change', (e) => {
      const on = !!e.target.checked;
      $('#remDue').disabled = !on;
      $('#remDueRow').style.display = on ? '' : 'none';
    });

    // Reminder bottom Cancel (acts like the old Back)
    $('#cancelReminder').addEventListener('click', () => {
      show('home');
      setStatus('#statusReminder','');
    });

    // Top-right round tick (save current editor if Reminder is visible)
    $('#navConfirm').addEventListener('click', () => {
      if ($('#reminder').classList.contains('active')) onSave && onSave();
    });

    // Event/Contact/CSV existing buttons (unchanged)
    $('#backEvent').addEventListener('click', () => { show('home'); setStatus('#statusEvent',''); });
    $('#backContact').addEventListener('click', () => { show('home'); setStatus('#statusContact',''); });
    $('#backCSV').addEventListener('click', () => { show('home'); setStatus('#statusCSV',''); });
    $('#saveEvent').addEventListener('click', () => onSave && onSave());
    $('#saveContact').addEventListener('click', () => onSave && onSave());
    $('#exportCSV').addEventListener('click', () => onSave && onSave());

    // Home buttons
    $('#btnAuto').addEventListener('click', openAuto);
    $('#btnReminder').addEventListener('click', openReminder);
    $('#btnEvent').addEventListener('click', openEvent);
    $('#btnContact').addEventListener('click', openContact);
    $('#btnCSV').addEventListener('click', openCSV);

    // Start on Home
    showHome();
  });
})();
