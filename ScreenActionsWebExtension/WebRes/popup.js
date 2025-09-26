// popup.js — routes + UI glue for Home/Reminder/Event/etc.
// Update: Geofencing toggles now request permissions and reveal a radius slider.

(() => {
  'use strict';

  // --- Messaging to background/native ---
  const RT =
    (typeof browser !== 'undefined' && browser.runtime)
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
    native: (action, payload = {}) => sendMessage({ cmd: 'native', action, payload }),
  };

  // --- View helpers ---
  const views = ['home', 'reminder', 'event', 'contact', 'csv'];

  function show(id) {
    for (const v of views) {
      const el = document.getElementById(`view-${v}`);
      if (el) el.classList.toggle('active', v === id);
    }
  }

  function pad(n) { return String(n).padStart(2, '0'); }

  function isoToLocalParts(iso) {
    const d = iso ? new Date(iso) : new Date();
    if (isNaN(d.getTime())) {
      const f = new Date();
      return {
        date: `${f.getFullYear()}-${pad(f.getMonth() + 1)}-${pad(f.getDate())}`,
        time: `${pad(f.getHours())}:${pad(f.getMinutes())}`,
      };
    }
    return {
      date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
      time: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
    };
  }

  function localPartsToISO(dateStr, timeStr) {
    const t = (timeStr && /^\d{2}:\d{2}$/.test(timeStr)) ? `${timeStr}:00` : '00:00:00';
    return new Date(`${dateStr}T${t}`).toISOString();
  }

  async function populateHomeSelection() {
    const out = await bg.getPageCtx();
    const text = out?.ctx?.selection || '';
    const pre = document.getElementById('home-selection');
    pre.textContent = text ? text : '(no selection)';
  }

  // ----- Reminder -----

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
    document.getElementById('remHasDue').checked = !!f.hasDue;

    const parts = isoToLocalParts(f.dueISO);
    document.getElementById('remDueDate').value = parts.date;
    document.getElementById('remDueTime').value = parts.time;
    document.getElementById('remNotes').value = f.notes || '';

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
      notes: document.getElementById('remNotes').value,
    };

    const status = document.getElementById('remStatus');
    status.textContent = 'Saving…';
    status.className = 'status';

    const out = await bg.native('saveReminder', { fields });
    if (out?.ok) {
      status.textContent = 'Reminder saved.';
      status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.';
      status.className = 'status err';
    }
  }

  // ----- Event -----

  function geoAnyOn() {
    return (
      document.getElementById('evtGeoArrive').checked ||
      document.getElementById('evtGeoDepart').checked
    );
  }

  function updateGeoUI() {
    const radiusRow = document.getElementById('evtGeoRadiusRow');
    const hint = document.getElementById('evtGeoHint');
    const any = geoAnyOn();
    radiusRow.classList.toggle('hidden', !any);

    const locEmpty = !document.getElementById('evtLocation').value.trim();
    hint.classList.toggle('hidden', !(any && locEmpty));
  }

  function updateRadiusLabel() {
    const v = parseInt(document.getElementById('evtGeoRadius').value, 10) || 150;
    document.getElementById('evtGeoRadiusLabel').textContent = `${v} m`;
  }

  async function onGeoToggle() {
    if (geoAnyOn()) {
      // Trigger permissions like the app/share sheet
      await bg.native('ensureGeofencingPermissions', {});
    }
    updateGeoUI();
  }

  async function openEvent() {
    show('event');

    const status = document.getElementById('evtStatus');
    status.textContent = '';

    const prep = await bg.native('prepareEvent', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.';
      status.className = 'status err';
      return;
    }

    const f = prep.fields || {};
    document.getElementById('evtTitle').value = f.title || '';

    const sParts = isoToLocalParts(f.startISO);
    const eParts = isoToLocalParts(f.endISO);
    document.getElementById('evtStartDate').value = sParts.date;
    document.getElementById('evtStartTime').value = sParts.time;
    document.getElementById('evtEndDate').value = eParts.date;
    document.getElementById('evtEndTime').value = eParts.time;

    document.getElementById('evtLocation').value = f.location || '';
    document.getElementById('evtInferTZ').checked = !!f.inferTZ;

    // Geofencing defaults
    document.getElementById('evtGeoArrive').checked = false;
    document.getElementById('evtGeoDepart').checked = false;
    document.getElementById('evtGeoRadius').value = String(f.geoRadius || 150);
    updateRadiusLabel();
    updateGeoUI();

    document.getElementById('evtAlert').value = String(Number(f.alertMinutes || 0));
    document.getElementById('evtNotes').value = f.notes || '';
  }

  async function saveEvent() {
    const status = document.getElementById('evtStatus');

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
      startISO,
      endISO,
      location: document.getElementById('evtLocation').value,
      inferTZ: document.getElementById('evtInferTZ').checked,
      alertMinutes: parseInt(document.getElementById('evtAlert').value, 10) || 0,
      notes: document.getElementById('evtNotes').value,
      geoArrive: document.getElementById('evtGeoArrive').checked,
      geoDepart: document.getElementById('evtGeoDepart').checked,
      geoRadius: parseInt(document.getElementById('evtGeoRadius').value, 10) || 150,
    };

    status.textContent = 'Saving…';
    status.className = 'status';

    const out = await bg.native('saveEvent', { fields });
    if (out?.ok) {
      status.textContent = 'Event saved.';
      status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.';
      status.className = 'status err';
    }
  }

  // ----- Contact -----

  async function openContact() {
    show('contact');

    const status = document.getElementById('ctStatus');
    status.textContent = '';

    const prep = await bg.native('prepareContact', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.';
      status.className = 'status err';
      return;
    }

    const f = prep.fields || {};
    document.getElementById('ctGiven').value = f.givenName || '';
    document.getElementById('ctFamily').value = f.familyName || '';

    const emails = f.emails || [];
    document.getElementById('ctEmail1').value = emails[0] || '';
    document.getElementById('ctEmail2').value = emails[1] || '';

    const phones = f.phones || [];
    document.getElementById('ctPhone1').value = phones[0] || '';
    document.getElementById('ctPhone2').value = phones[1] || '';

    document.getElementById('ctStreet').value = f.street || '';
    document.getElementById('ctCity').value = f.city || '';
    document.getElementById('ctState').value = f.state || '';
    document.getElementById('ctPostal').value = f.postalCode || '';
    document.getElementById('ctCountry').value = f.country || '';
  }

  async function saveContact() {
    const status = document.getElementById('ctStatus');
    status.textContent = 'Saving…';
    status.className = 'status';

    const fields = {
      givenName: document.getElementById('ctGiven').value,
      familyName: document.getElementById('ctFamily').value,
      emails: [document.getElementById('ctEmail1').value, document.getElementById('ctEmail2').value].filter(Boolean),
      phones: [document.getElementById('ctPhone1').value, document.getElementById('ctPhone2').value].filter(Boolean),
      street: document.getElementById('ctStreet').value,
      city: document.getElementById('ctCity').value,
      state: document.getElementById('ctState').value,
      postalCode: document.getElementById('ctPostal').value,
      country: document.getElementById('ctCountry').value,
    };

    const out = await bg.native('saveContact', { fields });
    if (out?.ok) {
      status.textContent = 'Contact saved.';
      status.className = 'status ok';
      await bg.native('hapticSuccess', {});
      window.close?.();
    } else {
      status.textContent = out?.message || 'Save failed.';
      status.className = 'status err';
    }
  }

  // ----- CSV -----

  async function openCSV() {
    show('csv');

    const status = document.getElementById('csvStatus');
    status.textContent = '';

    const prep = await bg.native('prepareReceiptCSV', {});
    if (!prep?.ok) {
      status.textContent = prep?.message || 'Failed to prepare.';
      status.className = 'status err';
      return;
    }

    document.getElementById('csvInput').textContent = (prep.fieldsText || '') || '';
    document.getElementById('csvPreview').textContent = prep.csv || '';
  }

  // Updated: stay inside Safari using Web Share API (files) or a download fallback,
  // while still calling native first for quota + app-group write.
  async function exportCSV() {
    const status = document.getElementById('csvStatus');
    status.textContent = 'Exporting…';
    status.className = 'status';

    // CSV content from preview
    const csv = document.getElementById('csvPreview').textContent || '';

    // 1) Preserve existing behaviour: gate via native (quota + app-group write)
    const out = await bg.native('exportReceiptCSV', { csv });
    if (!out?.ok) {
      status.textContent = out?.message || 'Export failed.';
      status.className = 'status err';
      return;
    }

    // Generate a filename similar to native pattern
    const iso = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const filename = `receipt-${iso}.csv`;

    // Helper to finish consistently
    const finishOk = async (msg) => {
      status.textContent = msg || 'CSV exported.';
      status.className = 'status ok';
      try { await bg.native('hapticSuccess', {}); } catch {}
      window.close?.();
    };

    // 2) Try Web Share API with files (lets user pick "Save to Files" in Safari)
    try {
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
      const file = new File([blob], filename, { type: 'text/csv' });

      const canShareFiles = !!navigator.share &&
                            (!navigator.canShare || navigator.canShare({ files: [file] }));
      if (canShareFiles) {
        await navigator.share({ files: [file] });
        return await finishOk('Shared. Choose “Save to Files”.');
      }
    } catch {
      // fall through to download
    }

    // 3) Fallback: force a download (Safari places it in Files → Downloads)
    try {
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 10000);
      return await finishOk('Saved to Downloads.');
    } catch {
      // 4) Last resort: native has already written to app-group; user can finish in the app
      status.textContent = 'Exported. Open the app to save to Files.';
      status.className = 'status ok';
    }
  }

  // ----- Wiring -----

  window.addEventListener('DOMContentLoaded', async () => {
    // Home
    document.getElementById('btn-auto').onclick = async () => {
      const out = await bg.native('prepareAutoDetect', {});
      if (out?.ok && out?.route) {
        if (out.route === 'event')   return openEvent();
        if (out.route === 'reminder')return openReminder();
        if (out.route === 'contact') return openContact();
        if (out.route === 'csv')     return openCSV();
      }
      openEvent();
    };
    document.getElementById('btn-rem').onclick = openReminder;
    document.getElementById('btn-evt').onclick = openEvent;
    document.getElementById('btn-contact').onclick = openContact;
    document.getElementById('btn-csv').onclick = openCSV;

    // Reminder
    document.getElementById('btnRemCancel').onclick = () => show('home');
    document.getElementById('btnRemSave').onclick = saveReminder;

    // Event
    document.getElementById('btnEvtCancel').onclick = () => show('home');
    document.getElementById('btnEvtSave').onclick = saveEvent;

    // Geofencing UI hooks
    document.getElementById('evtGeoArrive').addEventListener('change', onGeoToggle);
    document.getElementById('evtGeoDepart').addEventListener('change', onGeoToggle);
    document.getElementById('evtGeoRadius').addEventListener('input', updateRadiusLabel);
    document.getElementById('evtLocation').addEventListener('input', updateGeoUI);

    // Contact
    document.getElementById('btnCtCancel').onclick = () => show('home');
    document.getElementById('btnCtSave').onclick = saveContact;

    // CSV
    document.getElementById('btnCsvBack').onclick = () => show('home');
    document.getElementById('btnCsvExport').onclick = exportCSV;

    await populateHomeSelection();
  });
})();
