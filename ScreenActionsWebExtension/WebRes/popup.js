// popup.js — talks to background; no Share Sheet; storage-safe fallbacks.
(function () {
  const B = typeof browser !== "undefined" ? browser : undefined;
  const C = typeof chrome  !== "undefined" ? chrome  : undefined;

  const RUNTIME   = (B && B.runtime)   || (C && C.runtime);
  const TABS      = (B && B.tabs)      || (C && C.tabs);
  const SCRIPTING = (B && B.scripting) || (C && C.scripting);
  const STORAGE   = (B && B.storage && B.storage.local) || (C && C.storage && C.storage.local) || null;

  const REMEMBER_KEY   = "sa.rememberLastAction.enabled";
  const LAST_ACTION_KEY= "sa.rememberLastAction.value";

  // ---------- tiny storage wrapper (uses Web Storage if extension storage missing)
  function lsGet(key) {
    try { const v = localStorage.getItem(key); return v == null ? undefined : JSON.parse(v); }
    catch { return undefined; }
  }
  function lsSet(obj) {
    try { for (const [k,v] of Object.entries(obj)) localStorage.setItem(k, JSON.stringify(v)); } catch {}
  }
  async function storeGet(keys) {
    if (STORAGE) return new Promise(res => STORAGE.get(keys, res));
    if (Array.isArray(keys)) {
      const out = {}; for (const k of keys) out[k] = lsGet(k); return out;
    } else {
      const out = {}; out[keys] = lsGet(keys); return out;
    }
  }
  async function storeSet(obj) {
    if (STORAGE) return new Promise(res => STORAGE.set(obj, res));
    lsSet(obj);
  }
  // ---------------------------------------------------------------------------

  function setStatus(text, ok) {
    const s = document.getElementById("status");
    s.textContent = text;
    s.className = ok ? "status ok" : "status err";
  }

  function decorateError(message, hint) {
    const known = [
      { match: /Calendar access was not granted/i,
        guide: "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions.\nIf you haven’t opened the app yet, run it once so iPadOS can show the permission dialog." },
      { match: /Reminders access was not granted/i,
        guide: "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions.\nIf you haven’t opened the app yet, run it once so iPadOS can show the permission dialog." },
      { match: /Contacts access.*not granted/i,
        guide: "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions." },
      { match: /No date found/i,
        guide: "Select text that includes a date/time (e.g. “Fri 3pm”), or use ‘Create Reminder’ instead." }
    ];
    const extra = hint || (known.find(k => k.match.test(message))?.guide);
    return extra ? `${message} — ${extra}` : message;
  }

  // ---- send to background (works in Safari's popup)
  function runtimeSendMessage(msg) {
    return new Promise((resolve, reject) => {
      if (!RUNTIME || !RUNTIME.sendMessage) return reject(new Error("runtime.sendMessage unavailable"));
      try {
        const done = (resp) => {
          const err = (C && C.runtime && C.runtime.lastError) || null;
          if (err) reject(new Error(err.message || String(err)));
          else resolve(resp);
        };
        const maybe = RUNTIME.sendMessage(msg, done);
        if (maybe && typeof maybe.then === "function") maybe.then(resolve).catch(reject);
      } catch (e) {
        reject(e);
      }
    });
  }
  const NATIVE_MESSAGE = (action, payload) => runtimeSendMessage({ cmd: "native", action, payload });

  async function getPageContext() {
    try {
      const [tab] = await new Promise((res, rej) => {
        const ret = TABS.query({ active: true, currentWindow: true }, (t) => {
          const err = (C && C.runtime && C.runtime.lastError) || null;
          if (err) rej(new Error(err.message || String(err))); else res(t);
        });
        if (ret && typeof ret.then === "function") ret.then(res).catch(rej);
      });
      if (!tab) throw new Error("No active tab.");

      if (SCRIPTING && SCRIPTING.executeScript) {
        const results = await new Promise((res, rej) => {
          const ret = SCRIPTING.executeScript({
            target: { tabId: tab.id, allFrames: true },
            func: () => {
              function selectionFromActiveElement() {
                const el = document.activeElement;
                if (!el) return "";
                const tag = (el.tagName || "").toLowerCase();
                const type = (el.type || "").toLowerCase();
                if (tag === "textarea" || (tag === "input" && (type === "" || type === "text" || type === "search" || type === "url" || type === "tel"))) {
                  const start = el.selectionStart ?? 0;
                  const end   = el.selectionEnd   ?? 0;
                  const v = el.value || "";
                  if (end > start) return v.substring(start, end);
                  return v;
                }
                return "";
              }
              const sel = String(window.getSelection ? window.getSelection() : "") || selectionFromActiveElement();
              return { selection: sel, title: document.title || "", url: location.href || "" };
            }
          }, (r) => {
            const err = (C && C.runtime && C.runtime.lastError) || null;
            if (err) rej(new Error(err.message || String(err))); else res(r);
          });
          if (ret && typeof ret.then === "function") ret.then(res).catch(rej);
        });
        const firstWithSel = results && results.find(r => r && r.result && r.result.selection && r.result.selection.trim().length > 0);
        return (firstWithSel && firstWithSel.result) ||
               (results && results[0] && results[0].result) ||
               { selection: "", title: tab.title || "", url: tab.url || "" };
      }
      return { selection: "", title: tab.title || "", url: tab.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  async function askProStatus() {
    try {
      const resp = await NATIVE_MESSAGE("getProStatus", {});
      return !!(resp && resp.ok && resp.pro);
    } catch {
      return false;
    }
  }

  async function runAction(action) {
    const payload = await getPageContext();
    document.getElementById("sel").textContent = (payload.selection?.trim() || payload.title || "(No selection)");
    try {
      const response = await NATIVE_MESSAGE(action, payload);
      if (response?.ok) {
        setStatus(response.message || "Done.", true);
        const remember = (await storeGet(REMEMBER_KEY))[REMEMBER_KEY] === true;
        if (remember) {
          await storeSet({ [LAST_ACTION_KEY]: action });
          updateRunLast();
        }
      } else {
        const msg = decorateError((response && response.message) || "Unknown error.", response && response.hint);
        setStatus(msg, false);
      }
    } catch (err) {
      setStatus(decorateError((err && err.message) || String(err), null), false);
    }
  }

  async function updateRunLast() {
    const store = await storeGet([REMEMBER_KEY, LAST_ACTION_KEY]);
    const enabled = store[REMEMBER_KEY] === true;
    const last = store[LAST_ACTION_KEY];
    const row = document.getElementById("last-row");
    const btn = document.getElementById("btn-last");
    if (enabled && last) {
      row.style.display = "flex";
      const label = {
        autoDetect: "Auto Detect",
        createReminder: "Create Reminder",
        addEvent: "Add Calendar Event",
        extractContact: "Extract Contact",
        receiptCSV: "Receipt \u2192 CSV"
      }[last] || last;
      btn.textContent = `Run Last: ${label}`;
      btn.onclick = () => runAction(last);
    } else {
      row.style.display = "none";
    }
  }

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      const ctx = await getPageContext();
      document.getElementById("sel").textContent = (ctx.selection?.trim() || ctx.title || "(No selection)").toString();
    } catch {
      document.getElementById("sel").textContent = "(Unable to read page)";
    }

    document.getElementById("btn-auto").addEventListener("click", () => runAction("autoDetect"));
    document.getElementById("btn-rem").addEventListener("click", () => runAction("createReminder"));
    document.getElementById("btn-cal").addEventListener("click", () => runAction("addEvent"));
    document.getElementById("btn-ctc").addEventListener("click", () => runAction("extractContact"));
    document.getElementById("btn-csv").addEventListener("click", () => runAction("receiptCSV"));

    const isPro = await askProStatus();
    const wrap = document.getElementById("remember-wrap");
    if (isPro) {
      wrap.style.display = "block";
      const t = document.getElementById("remember-toggle");
      const store = await storeGet(REMEMBER_KEY);
      t.checked = store[REMEMBER_KEY] === true;
      t.addEventListener("change", async () => {
        await storeSet({ [REMEMBER_KEY]: t.checked });
        updateRunLast();
      });
      await updateRunLast();
    } else {
      wrap.style.display = "none";
    }

    // Quick preflight
    try {
      const ping = await NATIVE_MESSAGE("ping", {});
      setStatus(ping?.ok ? "Ready." : "Native bridge error.", !!ping?.ok);
    } catch {
      setStatus("Native bridge unavailable.", false);
    }
  });
})();
