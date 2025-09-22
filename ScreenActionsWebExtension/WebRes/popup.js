// popup.js — native bridge with iOS Share Sheet fallback
(function () {
  const API = globalThis.browser || globalThis.chrome;

  const REMEMBER_KEY = "sa.rememberLastAction.enabled";
  const LAST_ACTION_KEY = "sa.rememberLastAction.value";

  // Send a message to the background worker, which in turn calls sendNativeMessage.
  const NATIVE_MESSAGE = (action, payload) =>
    new Promise((resolve, reject) => {
      try {
        const msg = { cmd: "native", action, payload };
        const cb = (resp) => {
          const err = globalThis.chrome?.runtime?.lastError || null;
          if (err) return reject(new Error(err.message || String(err)));
          resolve(resp);
        };
        const maybe = API.runtime.sendMessage(msg, cb);
        if (maybe?.then) maybe.then(resolve).catch(reject);
      } catch (e) {
        reject(e);
      }
    });

  function setStatus(text, ok) {
    const s = document.getElementById("status");
    s.textContent = text;
    s.className = ok ? "status ok" : "status err";
  }

  function decorateError(message, hint) {
    const known = [
      {
        match: /Calendar access was not granted/i,
        guide:
          "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions.\nIf you haven’t opened the app yet, run it once so iPadOS can show the permission dialog."
      },
      {
        match: /Reminders access was not granted/i,
        guide:
          "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions.\nIf you haven’t opened the app yet, run it once so iPadOS can show the permission dialog."
      },
      {
        match: /Contacts access.*not granted/i,
        guide: "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions."
      },
      {
        match: /No date found/i,
        guide: "Select text that includes a date/time (e.g. “Fri 3pm”), or use ‘Create Reminder’ instead."
      }
    ];
    const extra = hint || (known.find(k => k.match.test(message))?.guide);
    return extra ? `${message} — ${extra}` : message;
  }

  // ---- Share Sheet Fallback (iOS friendly) ----------------------------------
  function sharePayloadString(payload) {
    const sel = (payload.selection || "").trim();
    const title = (payload.title || "").trim();
    const url = (payload.url || "").trim();
    const base = sel || title || url || "(No selection)";
    return url && base.indexOf(url) === -1 ? `${base}\n${url}` : base;
  }

  async function fallbackShare(action, payload) {
    const text = sharePayloadString(payload);
    if (!navigator.share) {
      throw new Error("Native bridge unavailable and Share Sheet not supported on this device.");
    }
    setStatus("Opening iOS Share Sheet… choose “Screen Actions”.", true);
    await navigator.share({ text });
    const label = {
      autoDetect: "Auto",
      createReminder: "Reminder",
      addEvent: "Calendar Event",
      extractContact: "Contact",
      receiptCSV: "Receipt → CSV"
    }[action] || "Action";
    setStatus(`${label}: handed off via Share Sheet.`, true);
    return { ok: true, message: "Shared to Screen Actions." };
  }
  // ----------------------------------------------------------------------------

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
                  if (
                    tag === "textarea" ||
                    (tag === "input" &&
                      (type === "" || type === "text" || type === "search" || type === "url" || type === "tel"))
                  ) {
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
        const firstWithSel =
          results && results.find((r) => r && r.result && r.result.selection && r.result.selection.trim().length > 0);
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
      // If native is blocked, don’t gate the UI here
      return false;
    }
  }

  // Treat any native-bridge failure as "use the Share Sheet" (iOS-friendly).
  function isBridgeFailure(message) {
    const m = message || "";
    return /sendNativeMessage unavailable/i.test(m) ||
           /Invalid call to runtime\.sendNativeMessage/i.test(m) ||
           /SFErrorDomain/i.test(m) ||
           /Host.*not.*found/i.test(m) ||
           /Native.*disconnected/i.test(m) ||
           /connectNative/i.test(m);
  }

  async function runAction(action) {
    const payload = await getPageContext();
    document.getElementById("sel").textContent = (payload.selection?.trim() || payload.title || "(No selection)");
    try {
      // First: try native
      const response = await NATIVE_MESSAGE(action, payload);
      if (response?.ok) {
        setStatus(response.message || "Done.", true);
        const remember = (await new Promise((res) => API.storage.local.get(REMEMBER_KEY, res)))[REMEMBER_KEY] === true;
        if (remember) {
          await new Promise((res) => API.storage.local.set({ [LAST_ACTION_KEY]: action }, res));
          updateRunLast();
        }
        return;
      }
      const msg = decorateError((response && response.message) || "Unknown error.", response && response.hint);
      throw new Error(msg);
    } catch (err) {
      const m = (err && err.message) || String(err);
      if (isBridgeFailure(m)) {
        try {
          await fallbackShare(action, payload);
          return;
        } catch (shareErr) {
          setStatus((shareErr && shareErr.message) || String(shareErr), false);
          return;
        }
      }
      setStatus(decorateError(m, null), false);
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

    setStatus("Ready.", true);
  });
})();
