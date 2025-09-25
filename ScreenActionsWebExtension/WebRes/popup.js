// popup.js — FAT editors; always route native via background {cmd:"native"}.

(() => {
  const RT        = (typeof chrome !== "undefined" && chrome.runtime) || (typeof browser !== "undefined" && browser.runtime);
  const TABS      = (typeof chrome !== "undefined" && chrome.tabs)    || (typeof browser !== "undefined" && browser.tabs);
  const SCRIPTING = (typeof chrome !== "undefined" && chrome.scripting)|| (typeof browser !== "undefined" && browser.scripting);

  const q = (id) => document.getElementById(id);
  const show = (id) => { for (const el of document.querySelectorAll(".view")) { el.classList.remove("active"); el.hidden = true; } const el = q(id); if (el) { el.classList.add("active"); el.hidden = false; } };
  const setStatus = (el, t, ok) => { el.textContent = t || ""; el.className = "status " + (ok ? "ok" : (t ? "err" : "")); };
  const combineMsg = (r, okText, errText) => { if (!r) return errText || "Error."; const p = []; if (r.message) p.push(r.message); if (r.hint) p.push(r.hint); if (!p.length) p.push(r.ok ? (okText || "Done.") : (errText || "Error.")); return p.join(" "); };

  function sendMessage(payload, timeoutMs = 8000) {
    return new Promise((resolve, reject) => {
      try {
        let settled = false;
        const ret = RT.sendMessage(payload, (resp) => {
          settled = true;
          const lastErr = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
          if (lastErr) reject(new Error(lastErr.message || String(lastErr)));
          else resolve(resp);
        });
        if (ret && typeof ret.then === "function") {
          ret.then((resp) => { if (!settled) resolve(resp); }).catch((e) => { if (!settled) reject(e); });
        }
        setTimeout(() => { if (!settled) reject(new Error("timeout")); }, timeoutMs);
      } catch (e) { reject(e); }
    });
  }

  async function askNative(action, payload) {
    try { return await sendMessage({ cmd: "native", action, payload }, 8000); }
    catch (e) { return { ok: false, message: e?.message || "Native bridge error." }; }
  }

  // ---- Page context (cache-first; script fallback)
  async function pageCtx() {
    try {
      const [tab] = TABS ? await TABS.query({ active: true, currentWindow: true }) : [null];
      const res = await sendMessage({ cmd: "getPageCtx", tabId: tab?.id }, 5000);
      if (res?.ok && res?.ctx) {
        const c = res.ctx;
        if ((c.selection?.trim()?.length || 0) > 0 || c.title || c.url || c.structured) return c;
      }
      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null) {
        const exec = await SCRIPTING.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func: () => String(getSelection ? getSelection() : "").trim()
        });
        const first = exec && exec.find(r => r?.result?.trim()?.length > 0);
        return { selection: (first ? first.result : ""), title: tab?.title || document.title || "", url: tab?.url || "" };
      }
      return { selection: "", title: tab?.title || document.title || "", url: tab?.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  // ---- Global ctx
  let ctx = { selection: "", title: "", url: "", structured: undefined };

  // ---- Date helpers
  const toInputDT = (iso) => { if (!iso) return ""; const d = new Date(iso); const pad = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };
  const fromInputDT = (v) => { const d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString(); };

  // ---- Event editor
  async function openEventEditor() {
    show("editor-event");
    setStatus(q("event-status"), "", true);
    const r = await askNative("prepareEvent", ctx);
    if (!r?.ok) { setStatus(q("event-status"), combineMsg(r, "", "Failed to prepare."), false); return; }
    const f = r.fields || {};
    q("event-title").value = f.title || "";
    q("event-start").value = toInputDT(f.startISO);
    q("event-end").value   = toInputDT(f.endISO);
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
      endISO:   fromInputDT(q("event-end").value),
      notes:    q("event-notes").value || "",
      location: q("event-location").value || "",
      inferTZ:  q("event-inferTZ").checked,
      alertMinutes: parseInt(q("event-alert").value || "0", 10) || 0
    };
    const r = await askNative("saveEvent", { fields });
    setStatus(q("event-status"), combineMsg(r, "Event created.", "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ---- Reminder editor
  function onRemHasDue() { q("rem-due-wrap").style.display = q("rem-hasDue").checked ? "" : "none"; }

  async function openReminderEditor() {
    show("editor-rem");
    setStatus(q("rem-status"), "", true);
    const r = await askNative("prepareReminder", ctx);
    if (!r?.ok) { setStatus(q("rem-status"), combineMsg(r, "", "Failed to prepare."), false); return; }
    const f = r.fields || {};
    q("rem-title").value = f.title || "";
    q("rem-hasDue").checked = !!f.hasDue;
    onRemHasDue();
    q("rem-due").value   = toInputDT(f.dueISO);
    q("rem-notes").value = f.notes || "";
  }

  async function saveReminder() {
    setStatus(q("rem-status"), "Saving…", true);
    const fields = {
      title:  q("rem-title").value || "",
      hasDue: q("rem-hasDue").checked,
      dueISO: q("rem-hasDue").checked ? fromInputDT(q("rem-due").value) : null,
      notes:  q("rem-notes").value || ""
    };
    const r = await askNative("saveReminder", { fields });
    setStatus(q("rem-status"), combineMsg(r, "Reminder created.", "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ---- Contact editor
  let emails = [], phones = [];
  function refreshContactLists() {
    const emailsEl = q("ctc-emails"); emailsEl.innerHTML = "";
    emails.forEach((val, i) => {
      const row = document.createElement("div"); row.className = "row";
      const input = document.createElement("input"); input.type = "text"; input.value = val; input.placeholder = "email@example.com";
      input.addEventListener("input", () => { emails[i] = input.value; });
      const del = document.createElement("button"); del.type = "button"; del.className = "btn"; del.textContent = "Delete";
      del.addEventListener("click", () => { emails.splice(i, 1); refreshContactLists(); });
      row.appendChild(input); row.appendChild(del);
      emailsEl.appendChild(row);
    });

    const phonesEl = q("ctc-phones"); phonesEl.innerHTML = "";
    phones.forEach((val, i) => {
      const row = document.createElement("div"); row.className = "row";
      const input = document.createElement("input"); input.type = "text"; input.value = val; input.placeholder = "+353 85 123 4567";
      input.addEventListener("input", () => { phones[i] = input.value; });
      const del = document.createElement("button"); del.type = "button"; del.className = "btn"; del.textContent = "Delete";
      del.addEventListener("click", () => { phones.splice(i, 1); refreshContactLists(); });
      row.appendChild(input); row.appendChild(del);
      phonesEl.appendChild(row);
    });
  }

  async function openContactEditor() {
    show("editor-ctc");
    setStatus(q("ctc-status"), "", true);
    const r = await askNative("prepareContact", ctx);
    if (!r?.ok) { setStatus(q("ctc-status"), combineMsg(r, "", "Failed to prepare."), false); return; }
    const f = r.fields || {};
    q("ctc-given").value  = f.givenName || f.given || "";
    q("ctc-family").value = f.familyName || f.family || "";
    emails = Array.isArray(f.emails) ? f.emails.slice(0, 8) : [];
    phones = Array.isArray(f.phones) ? f.phones.slice(0, 8) : [];
    q("ctc-street").value   = f.street   || (f.address && f.address.street)   || "";
    q("ctc-city").value     = f.city     || (f.address && f.address.city)     || "";
    q("ctc-state").value    = f.state    || (f.address && f.address.state)    || "";
    q("ctc-postal").value   = f.postalCode || (f.address && f.address.postcode) || "";
    q("ctc-country").value  = f.country  || (f.address && f.address.country)  || "";
    refreshContactLists();
  }

  async function saveContact() {
    setStatus(q("ctc-status"), "Saving…", true);
    const fields = {
      givenName:  q("ctc-given").value || "",
      familyName: q("ctc-family").value || "",
      emails: emails.filter(x => (x || "").trim().length > 0).slice(0, 8),
      phones: phones.filter(x => (x || "").trim().length > 0).slice(0, 8),
      street:   q("ctc-street").value || "",
      city:     q("ctc-city").value || "",
      state:    q("ctc-state").value || "",
      postalCode: q("ctc-postal").value || "",
      country:  q("ctc-country").value || ""
    };
    const r = await askNative("saveContact", { fields });
    setStatus(q("ctc-status"), combineMsg(r, "Contact saved.", "Error."), !!r?.ok);
    if (r?.ok) show("home");
  }

  // ---- CSV
  function setCSV(text) { q("csv-preview").textContent = text || ""; }
  async function openCSVView() {
    show("editor-csv");
    q("csv-status").textContent = "";
    q("csv-input").value = (ctx.selection || "").trim();
    setCSV("");
    const r = await askNative("prepareReceiptCSV", { text: q("csv-input").value || "" });
    if (r?.ok && typeof r.csv === "string") setCSV(r.csv);
  }
  async function reparseCSV() {
    setCSV(""); setStatus(q("csv-status"), "Parsing…", true);
    const text = q("csv-input").value || "";
    const r = await askNative("prepareReceiptCSV", { text });
    if (r?.ok && typeof r.csv === "string") { setCSV(r.csv); setStatus(q("csv-status"), "Preview ready.", true); }
    else { setStatus(q("csv-status"), combineMsg(r, "", "Couldn’t parse."), false); }
  }
  async function exportCSV() {
    const csv = q("csv-preview").textContent || "";
    if (!csv) { setStatus(q("csv-status"), "Nothing to export.", false); return; }
    const r = await askNative("exportReceiptCSV", { csv });
    setStatus(q("csv-status"), combineMsg(r, "Exported.", "Export failed."), !!r?.ok);
  }

  // ---- Auto Detect → open an editor (no auto-save)
  async function autoDetect() {
    setStatus(q("status"), "Detecting…", true);
    const r = await askNative("prepareAutoDetect", ctx);
    if (!r?.ok) { setStatus(q("status"), combineMsg(r, "", "Couldn’t detect."), false); return; }
    const route = String(r.route || "");
    if (route === "event")    return openEventEditor();
    if (route === "reminder") return openReminderEditor();
    if (route === "contact")  return openContactEditor();
    if (route === "csv")      return openCSVView();
    setStatus(q("status"), "Ready.", true);
  }

  // ---- Wire
  function wire() {
    q("btn-auto")?.addEventListener("click", autoDetect);
    q("btn-rem") ?.addEventListener("click", openReminderEditor);
    q("btn-cal") ?.addEventListener("click", openEventEditor);
    q("btn-ctc") ?.addEventListener("click", openContactEditor);
    q("btn-csv") ?.addEventListener("click", openCSVView);

    q("btn-event-back")?.addEventListener("click", () => show("home"));
    q("event-save")?.addEventListener("click", saveEvent);

    q("btn-rem-back")?.addEventListener("click", () => show("home"));
    q("rem-save")  ?.addEventListener("click", saveReminder);
    q("rem-hasDue")?.addEventListener("change", onRemHasDue);

    q("btn-ctc-back")?.addEventListener("click", () => show("home"));
    q("ctc-save")  ?.addEventListener("click", saveContact);
    q("ctc-add-email")?.addEventListener("click", () => { emails.push(""); refreshContactLists(); });
    q("ctc-add-phone")?.addEventListener("click", () => { phones.push(""); refreshContactLists(); });

    q("btn-csv-back")?.addEventListener("click", () => show("home"));
    q("csv-reparse")?.addEventListener("click", reparseCSV);
    q("csv-export") ?.addEventListener("click", exportCSV);
  }

  // ---- Boot
  document.addEventListener("DOMContentLoaded", async () => {
    wire();
    show("home");
    try { await sendMessage({ cmd: "echo", payload: true }, 5000); setStatus(q("status"), "Ready.", true); }
    catch { setStatus(q("status"), "Ready.", true); }
    ctx = await pageCtx();
    q("sel").textContent = (ctx.selection?.trim() || ctx.title || "No selection");
  });
})();
