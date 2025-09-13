async function getPageContext() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const [{ result }] = await browser.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => ({
      selection: String(window.getSelection ? window.getSelection() : "") || "",
      title: document.title || "",
      url: location.href || ""
    })
  });
  return result;
}

function setStatus(text, ok) {
  const s = document.getElementById("status");
  s.textContent = text;
  s.className = ok ? "ok" : "err";
}

async function runAction(action) {
  try {
    const payload = await getPageContext();
    document.getElementById("sel").textContent =
      payload.selection?.trim() || payload.title || "(No selection)";

    // Native messaging to Swift handler
    const response = await browser.runtime.sendNativeMessage("application.id", {
      action,
      payload
    });

    if (response?.ok) {
      setStatus(response.message || "Done.", true);

      // If a CSV was produced, copy its URL to the clipboard for quick paste
      if (action === "receiptCSV" && response.fileURL) {
        await navigator.clipboard.writeText(response.fileURL);
      }
    } else {
      throw new Error(response?.message || "Unknown error.");
    }
  } catch (err) {
    setStatus(err.message || String(err), false);
  }
}

document.addEventListener("DOMContentLoaded", async () => {
  try {
    const ctx = await getPageContext();
    document.getElementById("sel").textContent =
      (ctx.selection?.trim() || ctx.title || "(No selection)").toString();
  } catch {
    document.getElementById("sel").textContent = "(Unable to read page)";
  }

  document.getElementById("btn-rem").addEventListener("click", () => runAction("createReminder"));
  document.getElementById("btn-cal").addEventListener("click", () => runAction("addEvent"));
  document.getElementById("btn-ctc").addEventListener("click", () => runAction("extractContact"));
  document.getElementById("btn-csv").addEventListener("click", () => runAction("receiptCSV"));
});
