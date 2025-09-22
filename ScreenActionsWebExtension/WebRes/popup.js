// popup.js — talks to background (which talks to native); Safari-friendly APIs

(function () {
  const API = globalThis.browser || globalThis.chrome;
  const REMEMBER_KEY = "sa.rememberLastAction.enabled";
  const LAST_ACTION_KEY = "sa.rememberLastAction.value";

  function setStatus(text, ok) {
    const s = document.getElementById("status");
    s.textContent = text;
    s.className = ok ? "status ok" : "status err";
  }

  function decorateError(message, hint) {
    const known = [
      { match: /Calendar access was not granted/i, guide: "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions. If you haven’t opened the app yet, run it once so iPadOS can show the permission dialog." },
      { match: /Reminders access was not granted/i, guide: "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions. If you haven’t opened the app yet, run it once so iPadOS can show the permission dialog." },
      { match: /Contacts access.*not granted/i,       guide: "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions." },
      { match: /cannot connect|connectNative|native|helper application/i, guide: "Enable the extension under Settings → Safari → Extensions → Screen Actions, then open the Screen Actions app once and try again." },
      { match: /No date found/i,                      guide: "Select text that includes a date/time (e.g. “Fri 3pm”), or use ‘Create Reminder’ instead." }
    ];
    const extra = hint || (known.find(k => k.match.test(message))?.guide);
    return extra ? `${message} — ${extra}` : message;
  }

  function sendMessageAsync(msg) {
    return new Promise((resolve, reject) => {
      try {
        API.runtime.sendMessage(msg, (resp) => {
          const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) return reject(new Error(err.message || String(err)));
          resolve(resp);
        });
      } catch (e) {
        reject(e);
      }
    });
  }

  async function native(action, payload) {
    return await sendMessageAsync({ cmd: "native", action, payload });
  }

  async function getPageContext() {
    try {
      const [tab] = await new Promise((res, rej) =>
        API.tabs.query({ active: true, currentWindow: true }, (t) => {
          const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
          if (err) return rej(new Error(err.message || String(err)));
          res(t);
        })
      );
      if (!tab) throw new Error("No active tab.");

      // Try scripting API; fall back to title/url only if not available
      const canScript = !!(API.scripting && API.scripting.executeScript);
      if (canScript) {
        const results = await new Promise((res, rej) =>
          API.scripting.executeScript(
            {
              target: { tabId: tab.id, allFrames: true },
              func: () => {
                function selectionFromActiveElement() {
                  const el = document.activeElement;
                  if (!el) return "";
                  const tag = (el.tagName || "").toLowerCase();
                  const type = (el.type || "").toLowerCase();
                  if (tag === "textarea" || (tag === "input" && (type === "" || type === "text" || type === "search" || type === "url" || type === "tel"))) {
                    const start = el.selectionStart ?? 0;
                    const end = el.selectionEnd ?? 0;
                    const v = el.value || "";
                    if (end > start) return v.substring(start, end);
                    return v;
                  }
                  return "";
                }
                const sel = String(window.getSelection ? window.getSelection() : "") || selectionFromActiveElement();
                return { selection: sel, title: document.title || "", url: location.href || "" };
              }
            },
            (r) => {
              const err = (globalThis.chrome && chrome.runtime && chrome.runtime.lastError) || null;
              if (err) return rej(new Error(err.message || String(err)));
              res(r);
            }
          )
        );

        const firstWithSel = results && results.find(r => r && r.result && r.result.selection && r.result.selection.trim().length > 0);
        return (firstWithSel && firstWithSel.result) || (results && results[0] && results[0].result) || { selection: "", title: tab.title || "", url: tab.url || "" };
      }

      // Fallback: no scripting — use tab title/url only
      return { selection: "", title: tab.title || "", url: tab.url || "" };
    } catch {
      return { selection: "", title: document.title || "", url: "" };
    }
  }

  async function askProStatus() {
    try {
      const resp = await native("getProStatus", {});
      return !!(resp && resp.ok && resp.pro);
    } catch {
      return false;
    }
  }

  async function runAction(action) {
    try {
      const payload = await getPageContext();
      document.getElementById("sel").textContent = (payload.selection?.trim() || payload.title || "(No selection)");
      const response = await native(action, payload);
      if (response?.ok) {
        setStatus(response.message || "Done.", true);
        if ((action === "receiptCSV" || action === "autoDetect") && response.fileURL) {
          try { await navigator.clipboard.writeText(response.fileURL); } catch {}
        }
        const remember = (await new Promise((res) => API.storage.local.get(REMEMBER_KEY, res)))[REMEMBER_KEY] === true;
        if (remember) {
          await new Promise((res) => API.storage.local.set({ [LAST_ACTION_KEY]: action }, res));
          updateRunLast();
        }
      } else {
        const msg = decorateError((response && response.message) || "Unknown error.", response && response.hint);
        throw new Error(msg);
      }
    } catch (err) {
      setStatus((err && err.message) || String(err), false);
    }
  }

  async function updateRunLast() {
    const store = await new Promise((res) => API.storage.local.get([REMEMBER_KEY, LAST_ACTION_KEY], res));
    const enabled = store[REMEMBER_KEY] === true;
    const last = store[LAST_ACTION_KEY];
    const row = document.getElementById("last-row");
    const btn = document.getElementById("btn-last");
    if (enabled && last) {
      row.style.display = "flex";
      const label = { autoDetect: "Auto Detect", createReminder: "Create Reminder", addEvent: "Add Calendar Event", extractContact: "Extract Contact", receiptCSV: "Receipt \u2192 CSV" }[last] || last;
      btn.textContent = `Run Last: ${label}`;
      btn.onclick = () => runAction(last);
    } else {
      row.style.display = "none";
    }
  }

  document.addEventListener("DOMContentLoaded", async () => {
    setStatus("Ready.", true);
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
      const store = await new Promise((res) => API.storage.local.get(REMEMBER_KEY, res));
      t.checked = store[REMEMBER_KEY] === true;
      t.addEventListener("change", async () => {
        await new Promise((res) => API.storage.local.set({ [REMEMBER_KEY]: t.checked }, res));
        updateRunLast();
      });
      await updateRunLast();
    } else {
      wrap.style.display = "none";
    }
  });
})();
