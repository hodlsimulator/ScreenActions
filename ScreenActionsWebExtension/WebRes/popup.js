// popup.js — routes + UI glue for Home/Reminder/Event/etc.
// Focus: Event sheet updated to 5 sections mirroring the share-sheet look.

(() => {
  'use strict';

  // ------- Runtime helpers -------
  const RT = (typeof browser !== 'undefined' && browser.runtime)
    ? browser.runtime
    : (typeof chrome !== 'undefined' && chrome.runtime)
      ? chrome.runtime
      : undefined;

  async function sendMessage(msg) {
    if (!RT || !RT.sendMessage) throw new Error('runtime not available');
    return await new Promise((resolve) => {
      try {
        RT.sendMessage(msg, (resp) => resolve(resp || {}));
      } catch {
        resolve({});
      }
    });
  }

  const bg = {
    getPageCtx: () => sendMessage({ cmd: 'getPageCtx' }),
    native: (action, payload = {}) => sendMessage({ cmd: 'native', action, payload })
  };

  // ------- View routing -------
  const views = ['home', 'reminder', 'event', 'contact', 'csv'];
  function show(id) {
    for (const v of views) {
      const el = document.getElementById(`view-${v}`);
      if (el) el.classList.toggle('active', v === id);
    }
  }

  // ------- Time helpers (local <-> ISO) -------
  function pad(n) { return String(n).padStart(2, '0'); }

  function isoToLocalParts(iso) {
    // robust parse for ISO with/without fractional seconds
    const d = iso ? new Date(iso) : new Date();
    if (isNaN(d.getTime())) {
      const fallback = new Date();
      return {
        date: `${fallback.getFullYear()}-${pad(fallback.getMonth()+1)}-${pad(fallback.getDate())}`,
        time: `${pad(fallback.getHours())}:${pad(fallback.getMinutes())}`
      };
    }
    return {
      date: `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`,
      time: `${pad(d.getHours())}:${pad(d.getMinutes())}`
    };
  }

  function localPartsToISO(dateStr, timeStr) {
    const t = (timeStr && /^\d{2}:\d{2}$/.test(timeStr)) ? `${timeStr}:00` : '00:00:00';
    // Construct local time then send as ISO string
    const d = new Date(`${dateStr}T${t}`);
    return d.toISOString();
  }

  // ------- Populate Home selection -------
  async function populateHomeSelection() {
    const out = await bg.getPageCtx();
    const text = out?.ctx?.selection || '';
    const pre = document.getElementById('home-selection');
    pre.textContent = text ? text : '(no selection)';
  }

  // ------- Reminder sheet -------
  async function openReminder() {
    show('reminder');
    const status = document.getElementById('remStatus');
    status.textContent = '';
    const prep = await bg.native('prepareReminder', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.';
      status.className = 'status err';
      return;
    }
    const f = prep.fields || {};
    document.getElementById('remTitle').value = f.title || '';
    const hasDue = !!f.hasDue;
    document.getElementById('remHasDue').checked = hasDue;
    const parts = isoToLocalParts(f.dueISO);
    document.getElementById('remDueDate').value = parts.date;
    document.getElementById('remDueTime').value = parts.time;
    document.getElementById('remNotes').value = f.notes || '';

    // Enable/disable date/time by toggle
    const toggleDueEnabled = () => {
      const enabled = document.getElementById('remHasDue').checked;
      document.getElementById('remDueDate').disabled = !enabled;
      document.getElementById('remDueTime').disabled = !enabled;
    };
    document.getElementById('remHasDue').onchange = toggleDueEnabled;
    toggleDueEnabled();
  }

  async function saveReminder() {
    const fields = {
      title: document.getElementById('remTitle').value.trim(),
      hasDue: document.getElementById('remHasDue').checked,
      dueISO: localPartsToISO(
        document.getElementById('remDueDate').value,
        document.getElementById('remDueTime').value
      ),
      notes: document.getElementById('remNotes').value
    };
    const status = document.getElementById('remStatus');
    status.textContent = 'Saving…'; status.className = 'status';
    const out = await bg.native('saveReminder', { fields });
    if (out?.ok) {
      status.textContent = 'Reminder saved.'; status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.'; status.className = 'status err';
    }
  }

  // ------- Event sheet (UPDATED) -------
  async function openEvent() {
    show('event');
    const status = document.getElementById('evtStatus');
    status.textContent = '';
    const prep = await bg.native('prepareEvent', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.'; status.className = 'status err';
      return;
    }
    const f = prep.fields || {};
    // Details
    document.getElementById('evtTitle').value = f.title || '';
    const sParts = isoToLocalParts(f.startISO);
    const eParts = isoToLocalParts(f.endISO);
    document.getElementById('evtStartDate').value = sParts.date;
    document.getElementById('evtStartTime').value = sParts.time;
    document.getElementById('evtEndDate').value = eParts.date;
    document.getElementById('evtEndTime').value = eParts.time;

    // Location
    document.getElementById('evtLocation').value = f.location || '';
    document.getElementById('evtInferTZ').checked = !!f.inferTZ;

    // Geofencing defaults off (native will ignore if both off)
    document.getElementById('evtGeoArrive').checked = false;
    document.getElementById('evtGeoDepart').checked = false;

    // Alert
    const alert = Number(f.alertMinutes || 0);
    document.getElementById('evtAlert').value = String(isFinite(alert) ? alert : 0);

    // Notes
    document.getElementById('evtNotes').value = f.notes || '';
  }

  async function saveEvent() {
    const status = document.getElementById('evtStatus');

    // Build ISO start/end from separate date/time fields
    const startISO = localPartsToISO(
      document.getElementById('evtStartDate').value,
      document.getElementById('evtStartTime').value
    );
    const endISO = localPartsToISO(
      document.getElementById('evtEndDate').value,
      document.getElementById('evtEndTime').value
    );

    const fields = {
      title: document.getElementById('evtTitle').value.trim() || 'Event',
      startISO, endISO,
      location: document.getElementById('evtLocation').value,
      inferTZ: document.getElementById('evtInferTZ').checked,
      alertMinutes: parseInt(document.getElementById('evtAlert').value, 10) || 0,
      notes: document.getElementById('evtNotes').value,
      // New geofencing toggles (native will ignore if both false)
      geoArrive: document.getElementById('evtGeoArrive').checked,
      geoDepart: document.getElementById('evtGeoDepart').checked
    };

    status.textContent = 'Saving…'; status.className = 'status';

    const out = await bg.native('saveEvent', { fields });
    if (out?.ok) {
      status.textContent = 'Event saved.'; status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.'; status.className = 'status err';
    }
  }

  // ------- Contact sheet (minimal; unchanged behaviour) -------
  async function openContact() {
    show('contact');
    const status = document.getElementById('ctStatus');
    status.textContent = '';
    const prep = await bg.native('prepareContact', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.'; status.className = 'status err';
      return;
    }
    const f = prep.fields || {};
    document.getElementById('ctGiven').value  = f.givenName || '';
    document.getElementById('ctFamily').value = f.familyName || '';
    const emails = f.emails || [];
    document.getElementById('ctEmail1').value = emails[0] || '';
    document.getElementById('ctEmail2').value = emails[1] || '';
    const phones = f.phones || [];
    document.getElementById('ctPhone1').value = phones[0] || '';
    document.getElementById('ctPhone2').value = phones[1] || '';
    document.getElementById('ctStreet').value = f.street || '';
    document.getElementById('ctCity').value   = f.city || '';
    document.getElementById('ctState').value  = f.state || '';
    document.getElementById('ctPostal').value = f.postalCode || '';
    document.getElementById('ctCountry').value= f.country || '';
  }

  async function saveContact() {
    const status = document.getElementById('ctStatus');
    status.textContent = 'Saving…'; status.className = 'status';
    const fields = {
      givenName: document.getElementById('ctGiven').value,
      familyName: document.getElementById('ctFamily').value,
      emails: [document.getElementById('ctEmail1').value, document.getElementById('ctEmail2').value].filter(Boolean),
      phones: [document.getElementById('ctPhone1').value, document.getElementById('ctPhone2').value].filter(Boolean),
      street: document.getElementById('ctStreet').value,
      city: document.getElementById('ctCity').value,
      state: document.getElementById('ctState').value,
      postalCode: document.getElementById('ctPostal').value,
      country: document.getElementById('ctCountry').value
    };
    const out = await bg.native('saveContact', { fields });
    if (out?.ok) {
      status.textContent = 'Contact saved.'; status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.'; status.className = 'status err';
    }
  }

  // ------- CSV sheet (minimal; unchanged behaviour) -------
  async function openCSV() {
    show('csv');
    const status = document.getElementById('csvStatus');
    status.textContent = '';
    const prep = await bg.native('prepareReceiptCSV', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.'; status.className = 'status err';
      return;
    }
    document.getElementById('csvInput').textContent = (prep.fieldsText || '') || '';
    document.getElementById('csvPreview').textContent = prep.csv || '';
  }
  async function exportCSV() {
    const status = document.getElementById('csvStatus');
    status.textContent = 'Exporting…'; status.className = 'status';
    const csv = document.getElementById('csvPreview').textContent || '';
    const out = await bg.native('exportReceiptCSV', { csv });
    if (out?.ok) {
      status.textContent = 'CSV exported.'; status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Export failed.'; status.className = 'status err';
    }
  }

  // ------- Wire up buttons -------
  window.addEventListener('DOMContentLoaded', async () => {
    // Home
    document.getElementById('btn-auto').onclick    = async () => {
      const out = await bg.native('prepareAutoDetect', {});
      if (out?.ok && out?.route) {
        // jump to the chosen sheet
        if (out.route === 'event') return openEvent();
        if (out.route === 'reminder') return openReminder();
        if (out.route === 'contact') return openContact();
        if (out.route === 'csv') return openCSV();
      }
      // fallback
      openEvent();
    };
    document.getElementById('btn-rem').onclick     = openReminder;
    document.getElementById('btn-evt').onclick     = openEvent;
    document.getElementById('btn-contact').onclick = openContact;
    document.getElementById('btn-csv').onclick     = openCSV;

    // Reminder buttons
    document.getElementById('btnRemCancel').onclick = () => show('home');
    document.getElementById('btnRemSave').onclick   = saveReminder;

    // Event buttons
    document.getElementById('btnEvtCancel').onclick = () => show('home');
    document.getElementById('btnEvtSave').onclick   = saveEvent;

    // Contact buttons
    document.getElementById('btnCtCancel').onclick  = () => show('home');
    document.getElementById('btnCtSave').onclick    = saveContact;

    // CSV buttons
    document.getElementById('btnCsvBack').onclick   = () => show('home');
    document.getElementById('btnCsvExport').onclick = exportCSV;

    // Home selection text
    await populateHomeSelection();
  });
})();
