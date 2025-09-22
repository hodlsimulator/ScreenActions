// background.js — minimal (popup calls sendNativeMessage directly)
(function () {
  try { (globalThis.browser || globalThis.chrome)?.runtime?.onInstalled?.addListener?.(() => {
    try { console.log("[SA] background ready"); } catch {}
  }); } catch {}
})();
