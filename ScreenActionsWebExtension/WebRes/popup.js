const NATIVE_APP_ID = "com.conornolan.Screen-Actions";

async function getPageContext() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab) throw new Error("No active tab.");

  const results = await browser.scripting.executeScript({
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
  });

  const firstWithSel = results.find(r => r && r.result && r.result.selection && r.result.selection.trim().length > 0);
  return firstWithSel?.result || (results[0]?.result) || { selection: "", title: "", url: "" };
}

function setStatus(text, ok) {
  const s = document.getElementById("status");
  s.textContent = text;
  s.className = ok ? "status ok" : "status err";
}

function decorateError(message, hint) {
  const known = [
    { match: /Calendar access was not granted/i, guide: "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions." },
    { match: /Reminders access was not granted/i, guide: "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions." },
    { match: /Contacts access.*not granted/i, guide: "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions." },
    { match: /cannot connect|connectNative|native/i, guide: "Enable the extension under Settings → Safari → Extensions → Screen Actions." }
  ];
  const extra = hint || (known.find(k => k.match.test(message))?.guide);
  return extra ? `${message} — ${extra}` : message;
}

async function runAction(action) {
  try {
    const payload = await getPageContext();
    document.getElementById("sel").textContent = (payload.selection?.trim() || payload.title || "(No selection)");
    const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, { action, payload });

    if (response?.ok) {
      setStatus(response.message || "Done.", true);
      if ((action === "receiptCSV" || action === "autoDetect") && response.fileURL) {
        try { await navigator.clipboard.writeText(response.fileURL); } catch { /* best-effort */ }
      }
    } else {
      const msg = decorateError((response && response.message) || "Unknown error.", response && response.hint);
      throw new Error(msg);
    }
  } catch (err) {
    setStatus((err && err.message) || String(err), false);
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
});
