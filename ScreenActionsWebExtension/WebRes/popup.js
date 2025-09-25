// popup.js — in-popover editors using native prepare*/save* (no app bounce)
(() => {
  const RT = (typeof chrome !== "undefined" && chrome.runtime) || (typeof browser !== "undefined" && browser.runtime);
  const TABS = (typeof chrome !== "undefined" && chrome.tabs) || (typeof browser !== "undefined" && browser.tabs);
  const SCRIPTING = (typeof chrome !== "undefined" && chrome.scripting) || (typeof browser !== "undefined" && browser.scripting);
  let port = null;

  // ------- DOM helpers -------
  const q = (id) => document.getElementById(id);
  const show = (id) => {
    for (const el of document.querySelectorAll(".view")) { el.classList.remove("active"); el.hidden = true; }
    const el = q(id); if (el) { el.classList.add("active"); el.hidden = false; }
  };
  const setStatus = (el, t, ok) => { el.textContent = t || ""; el.className = "status " + (ok ? "ok" : (t ? "err" : "")); };

  // ------- Page context -------
  async function pageCtx() {
    try {
      const [tab] = TABS ? await TABS.query({ active: true, currentWindow: true }) : [{ title: document.title, url: "" }];
      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null) {
        const res = await SCRIPTING.executeScript({ target: { tabId: tab.id, allFrames: true }, func: () => String(getSelection ? getSelection() : "") });
        const first = res && res.find(r => r?.result?.trim()?.length > 0);
        return { selection: (first ? first.result : ""), title: tab?.title || document.title || "", url: tab?.url || "" };
      }
      return { selection: "", title: tab?.title || document.title || "", url: tab?.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  // ------- Messaging to native (background.js queues & bridges) -------
  function ensurePort() { if (port) return port; port = RT.connect(); return port; }
  function viaPortOnce(payload, timeoutMs = 1500) {
    const p = ensurePort();
    return new Promise((resolve, reject) => {
      const handler = (resp) => { p.onMessage.removeListener(handler); resolve(resp); };
      p.onMessage.addListener(handler);
      p.postMessage(payload);
      setTimeout(() => { try { p.onMessage.removeListener(handler); } catch {} reject(new Error("port timeout")); }, timeoutMs);
    });
  }
  function viaSendMessage(payload, timeoutMs = 1500) {
    return new Promise((resolve, reject) => {
      try {
        let settled = false;
        const ret = RT.sendMessage(payload, (resp) => {
          settled = true;
          const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err))); else resolve(resp);
        });
        if (ret && typeof ret.then === "function") { ret.then((resp) => { if (!settled) resolve(resp); }).catch((e) => { if (!settled) reject(e); }); }
        setTimeout(() => { if (!settled) reject(new Error("sendMessage timeout")); }, timeoutMs);
      } catch (e) { reject(e); }
    });
  }
  function viaDirectNative(action, payload, timeoutMs = 2500) {
    return new Promise((resolve, reject) => {
      try {
        if (!RT.sendNativeMessage) { reject(new Error("sendNativeMessage unavailable")); return; }
        let p;
        try { p = RT.sendNativeMessage({ action, payload }); }
        catch { p = RT.sendNativeMessage("", { action, payload }); }
        if (p && typeof p.then === "function") {
          let done = false;
          p.then((r) => { done = true; resolve(r); }).catch((e) => { done = true; reject(e); });
          setTimeout(() => { if (!done) reject(new Error("direct native timeout")); }, timeoutMs);
        } else { reject(new Error("Unsupported sendNativeMessage form")); }
      } catch (e) { reject(e); }
    });
  }
  async function askNative(action, payload) {
    try { return await viaPortOnce({ cmd: "native", action, payload }); } catch {}
    try { return await viaSendMessage({ cmd: "native", action, payload }); } catch {}
    return await viaDirectNative(action, payload);
  }

  // ------- Utils -------
  const toInputDT = (iso) => {
    if (!iso) return "";
    const d = new Date(iso); const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };
  const fromInputDT = (v) => { const d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString(); };

  // ------- State -------
  let ctx = { selection: "", title: "", url: "" };

  // ------- Editors: Event -------
  async function openEventEditor() {
    show("editor-event"); setStatus(q("event-status"), "", true);
    const r = await askNative("prepareEvent", ctx);
    if (!r?.ok) { setStatus(q("event-status"), r?.message || "Failed to prepare.", false); return; }
    const f = r.fields || {};
    q("event-title").value = f.title || "";
    q("event-start").value = toInputDT(f.startISO);
    q("event-end").value = toInputDT(f.endISO);
    q("event-notes").value = f.notes || "";
    q("event-location").value = f.location || "";
    q("event-inferTZ").checked = !!f.inferTZ;
    q("event-alert").value = String(f.alertMinutes ?? 0);
  }
  async function saveEvent() {
    setStatus(q("event-status"), "Saving…", true);
    const fields = {
      title: q("event-title").value || "",
      startISO: fromInputDT(q("event-start").value),
      endISO: fromInputDT(q("event-end").value),
      notes: q("event-notes").value || "",
      location: q("event-location").value || "",
      inferTZ: q("event-inferTZ").checked,
      alertMinutes: parseInt(q("event-alert").value || "0", 10) || 0
    };
    const r = await askNative("saveEvent", { fields });
    setStatus(q("event-status"), r?.message || (r?.ok ? "Done." : "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ------- Editors: Reminder -------
  function onRemHasDue() { q("rem-due-wrap").style.display = q("rem-hasDue").checked ? "" : "none"; }
  async function openReminderEditor() {
    show("editor-rem"); setStatus(q("rem-status"), "", true);
    const r = await askNative("prepareReminder", ctx);
    if (!r?.ok) { setStatus(q("rem-status"), r?.message || "Failed to prepare.", false); return; }
    const f = r.fields || {};
    q("rem-title").value = f.title || "";
    q("rem-hasDue").checked = !!f.hasDue; onRemHasDue();
    q("rem-due").value = toInputDT(f.dueISO);
    q("rem-notes").value = f.notes || "";
  }
  async function saveReminder() {
    setStatus(q("rem-status"), "Saving…", true);
    const fields = {
      title: q("rem-title").value || "",
      hasDue: q("rem-hasDue").checked,
      dueISO: q("rem-hasDue").checked ? fromInputDT(q("rem-due").value) : null,
      notes: q("rem-notes").value || ""
    };
    const r = await askNative("saveReminder", { fields });
    setStatus(q("rem-status"), r?.message || (r?.ok ? "Done." : "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ------- Editors: Contact -------
  let emails = [], phones = [];
  function refreshContactLists() {
    const emailsEl = q("ctc-emails"); emailsEl.innerHTML = "";
    emails.forEach((val, i) => {
      const row = document.createElement("div"); row.className = "row";
      const input = document.createElement("input"); input.type = "text"; input.value = val; input.placeholder = "email@example.com";
      const del = document.createElement("button"); del.type = "button"; del.textContent = "Remove";
      row.appendChild(input); row.appendChild(del); emailsEl.appendChild(row);
      input.addEventListener("input", () => { emails[i] = input.value; });
      del.addEventListener("click", () => { emails.splice(i, 1); refreshContactLists(); });
    });
    const phonesEl = q("ctc-phones"); phonesEl.innerHTML = "";
    phones.forEach((val, i) => {
      const row = document.createElement("div"); row.className = "row";
      const input = document.createElement("input"); input.type = "text"; input.value = val; input.placeholder = "+353 1 123 4567";
      const del = document.createElement("button"); del.type = "button"; del.textContent = "Remove";
      row.appendChild(input); row.appendChild(del); phonesEl.appendChild(row);
      input.addEventListener("input", () => { phones[i] = input.value; });
      del.addEventListener("click", () => { phones.splice(i, 1); refreshContactLists(); });
    });
  }
  async function openContactEditor() {
    show("editor-ctc"); setStatus(q("ctc-status"), "", true);
    const r = await askNative("prepareContact", ctx);
    if (!r?.ok) { setStatus(q("ctc-status"), r?.message || "Failed to prepare.", false); return; }
    const f = r.fields || {};
    q("ctc-given").value = f.givenName || "";
    q("ctc-family").value = f.familyName || "";
    q("ctc-street").value = f.street || "";
    q("ctc-city").value = f.city || "";
    q("ctc-state").value = f.state || "";
    q("ctc-postal").value = f.postalCode || "";
    q("ctc-country").value = f.country || "";
    emails = (f.emails || []).slice();
    phones = (f.phones || []).slice();
    refreshContactLists();
  }
  async function saveContact() {
    setStatus(q("ctc-status"), "Saving…", true);
    const fields = {
      givenName: q("ctc-given").value || "",
      familyName: q("ctc-family").value || "",
      emails, phones,
      street: q("ctc-street").value || "",
      city: q("ctc-city").value || "",
      state: q("ctc-state").value || "",
      postalCode: q("ctc-postal").value || "",
      country: q("ctc-country").value || ""
    };
    const r = await askNative("saveContact", { fields });
    setStatus(q("ctc-status"), r?.message || (r?.ok ? "Done." : "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ------- Editors: Receipt CSV -------
  async function openCSVEditor() {
    show("editor-csv"); setStatus(q("csv-status"), "", true);
    const input = `${(ctx.selection || "").trim()}\n${ctx.title || ""}\n${ctx.url || ""}`.trim();
    q("csv-input").value = input;
    const r = await askNative("prepareReceiptCSV", { selection: input, title: "", url: "" });
    q("csv-preview").textContent = r?.csv || "—";
  }
  async function reparseCSV() {
    const t = q("csv-input").value || "";
    const r = await askNative("prepareReceiptCSV", { selection: t, title: "", url: "" });
    q("csv-preview").textContent = r?.csv || "—";
  }
  async function exportCSV() {
    setStatus(q("csv-status"), "Exporting…", true);
    const csv = q("csv-preview").textContent || "";
    const r = await askNative("exportReceiptCSV", { csv });
    setStatus(q("csv-status"), r?.message || (r?.ok ? "Exported." : "Error."), !!r?.ok);
  }

  // ------- Home one-taps (kept) -------
  async function run(action) {
    const r = await askNative(action, ctx);
    setStatus(q("status"), r?.ok ? (r.message || "Done.") : (r?.message || "Native error."), !!r?.ok);
  }

  // ------- Boot -------
  async function boot() {
    ctx = await pageCtx();
    q("sel").textContent = (ctx.selection?.trim() || ctx.title || "No selection");
    q("btn-auto")?.addEventListener("click", () => run("autoDetect"));
    q("btn-rem") ?.addEventListener("click", openReminderEditor);
    q("btn-cal") ?.addEventListener("click", openEventEditor);
    q("btn-ctc") ?.addEventListener("click", openContactEditor);
    q("btn-csv") ?.addEventListener("click", openCSVEditor);

    for (const btn of document.querySelectorAll(".nav-back")) btn.addEventListener("click", () => show("home"));
    q("event-save")?.addEventListener("click", saveEvent);
    q("rem-save")  ?.addEventListener("click", saveReminder);
    q("ctc-save")  ?.addEventListener("click", saveContact);
    q("csv-reparse")?.addEventListener("click", reparseCSV);
    q("csv-export") ?.addEventListener("click", exportCSV);

    // Connectivity
    try {
      await viaPortOnce({ cmd: "echo", payload: true }).catch(() => viaSendMessage({ cmd: "echo", payload: true }));
      const r = await askNative("ping", {});
      setStatus(q("status"), r?.ok ? "Ready." : "Native bridge error.", !!r?.ok);
    } catch { setStatus(q("status"), "Native bridge error.", false); }
  }

  if (document.readyState !== "loading") boot();
  else document.addEventListener("DOMContentLoaded", boot);
})();
