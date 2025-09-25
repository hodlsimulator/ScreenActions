// popup.js — editors in the popover with DIRECT native bridge first.
// If direct native isn't available, we fall back to background {cmd:"native"}.
// Also shows selection immediately and includes a tiny diagnostics ping.

(() => {
  const RT        = (typeof chrome !== "undefined" && chrome.runtime) || (typeof browser !== "undefined" && browser.runtime);
  const TABS      = (typeof chrome !== "undefined" && chrome.tabs)    || (typeof browser !== "undefined" && browser.tabs);
  const SCRIPTING = (typeof chrome !== "undefined" && chrome.scripting)|| (typeof browser !== "undefined" && browser.scripting);

  const q = (id) => document.getElementById(id);
  const show = (id) => {
    for (const el of document.querySelectorAll(".view")) { el.classList.remove("active"); el.hidden = true; }
    const el = q(id); if (el) { el.classList.add("active"); el.hidden = false; }
  };
  const setStatus = (el, t, ok) => { el.textContent = t || ""; el.className = "status " + (ok ? "ok" : (t ? "err" : "")); };
  const combineMsg = (r, okText, errText) => {
    if (!r) return errText || "Error.";
    const p = [];
    if (r.message) p.push(r.message);
    if (r.hint)    p.push(r.hint);
    if (!p.length) p.push(r.ok ? (okText || "Done.") : (errText || "Error."));
    return p.join(" ");
  };

  // ---------- Robust native (DIRECT first) ----------
  function tryDirectNative(action, payload, timeoutMs = 8000) {
    const fn = RT && RT.sendNativeMessage;
    if (!fn) return null;

    const msg = { action, payload };
    return new Promise((resolve) => {
      let settled = false;
      const done = (value) => { if (!settled) { settled = true; resolve(value); } };
      const onErr = (e) => done({ ok: false, message: (e && e.message) || "Native error." });

      // Helper to attempt a form
      const attempt = (invoker) => {
        try {
          const ret = invoker();
          // Promise form?
          if (ret && typeof ret.then === "function") {
            ret.then((v) => done(v)).catch(onErr);
            return true;
          }
          return false;
        } catch (e) { /* fall through */ return false; }
      };

      // 1) Promise: (msg)
      if (attempt(() => fn(msg))) return;

      // 2) Promise: ('', msg)
      if (attempt(() => fn("", msg))) return;

      // 3) Callback: (msg, cb)
      try {
        if (fn.length >= 2) {
          fn(msg, (res) => {
            const le = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
            if (le) done({ ok: false, message: le.message || "Native callback error." });
            else    done(res);
          });
          return;
        }
      } catch {}

      // 4) Callback: ('', msg, cb)
      try {
        if (fn.length >= 3) {
          fn("", msg, (res) => {
            const le = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) || null;
            if (le) done({ ok: false, message: le.message || "Native callback error." });
            else    done(res);
          });
          return;
        }
      } catch {}

      // If none worked, treat as unavailable.
      onErr(new Error("sendNativeMessage unavailable"));
      setTimeout(() => { if (!settled) onErr(new Error("timeout")); }, timeoutMs);
    });
  }

  function sendMessage(payload, timeoutMs = 8000) {
    // Wakes the worker and handles {cmd:"native"} fallback.
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
    // DIRECT first (reliable on iOS), then worker fallback.
    const direct = tryDirectNative(action, payload);
    if (direct) {
      const r = await direct;
      if (r && typeof r === "object" && ("ok" in r)) return r;
      // fall through only if direct path is clearly unavailable
    }
    try { return await sendMessage({ cmd: "native", action, payload }, 8000); }
    catch (e) { return { ok: false, message: e?.message || "Native bridge error." }; }
  }

  // ---------- Page context ----------
  async function pageCtx() {
    try {
      const [tab] = TABS ? await TABS.query({ active: true, currentWindow: true }) : [null];
      // 1) Background cache (fed by content_selection.js)
      const res = await sendMessage({ cmd: "getPageCtx", tabId: tab?.id }, 5000);
      if (res?.ok && res?.ctx) {
        const c = res.ctx;
        if ((c.selection?.trim()?.length || 0) > 0 || c.title || c.url || c.structured) return c;
      }
      // 2) Live fallback (may return empty on iOS after focus change)
      if (SCRIPTING && SCRIPTING.executeScript && tab && tab.id != null) {
        const exec = await SCRIPTING.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func: () => {
            try {
              const s = String(getSelection ? getSelection() : "");
              return s.trim();
            } catch { return ""; }
          }
        });
        const first = exec && exec.find(r => r?.result?.trim()?.length > 0);
        return { selection: (first ? first.result : ""), title: tab?.title || document.title || "", url: tab?.url || "" };
      }
      return { selection: "", title: tab?.title || document.title || "", url: tab?.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  // ---------- Global state ----------
  let ctx = { selection: "", title: "", url: "", structured: undefined };

  // ---------- Date helpers ----------
  const toInputDT = (iso) => {
    if (!iso) return "";
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };
  const fromInputDT = (v) => { const d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString(); };

  // ---------- Event editor ----------
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

  // ---------- Reminder editor ----------
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

  // ---------- Contact editor ----------
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

  // ---------- CSV ----------
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

  // ---------- Auto Detect → open an editor (no auto-save) ----------
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

  // ---------- Wire up ----------
  function wire() {
    // Home
    q("btn-auto")?.addEventListener("click", autoDetect);
    q("btn-rem") ?.addEventListener("click", openReminderEditor);
    q("btn-cal") ?.addEventListener("click", openEventEditor);
    q("btn-ctc") ?.addEventListener("click", openContactEditor);
    q("btn-csv") ?.addEventListener("click", openCSVView);

    // Event
    q("btn-event-back")?.addEventListener("click", () => show("home"));
    q("event-save")?.addEventListener("click", saveEvent);

    // Reminder
    q("btn-rem-back")?.addEventListener("click", () => show("home"));
    q("rem-save")  ?.addEventListener("click", saveReminder);
    q("rem-hasDue")?.addEventListener("change", onRemHasDue);

    // Contact
    q("btn-ctc-back")?.addEventListener("click", () => show("home"));
    q("ctc-save")  ?.addEventListener("click", saveContact);
    q("ctc-add-email")?.addEventListener("click", () => { emails.push(""); refreshContactLists(); });
    q("ctc-add-phone")?.addEventListener("click", () => { phones.push(""); refreshContactLists(); });

    // CSV
    q("btn-csv-back")?.addEventListener("click", () => show("home"));
    q("csv-reparse")?.addEventListener("click", reparseCSV);
    q("csv-export") ?.addEventListener("click", exportCSV);
  }

  // ---------- Boot with diagnostics ----------
  document.addEventListener("DOMContentLoaded", async () => {
    wire();
    show("home");

    // Wake worker (doesn't use the worker for native unless needed)
    try { await sendMessage({ cmd: "echo", payload: true }, 5000); setStatus(q("status"), "Ready.", true); }
    catch { setStatus(q("status"), "Ready (worker sleepy).", true); }

    // Context
    ctx = await pageCtx();
    q("sel").textContent = (ctx.selection?.trim() || ctx.title || "No selection");

    // Quick native ping so you immediately see if direct native works
    const ping = await askNative("ping", { t: Date.now() });
    if (!ping?.ok) setStatus(q("status"), combineMsg(ping, "", "Native bridge error."), false);
  });
})();
