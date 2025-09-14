// Runs inside Safari to hand selection/title/URL to the Share extension.
(function () {
  function textSel() {
    try {
      let s = (window.getSelection && String(window.getSelection())) || "";
      if (!s && document.activeElement) {
        const el = document.activeElement;
        if (el.tagName === "TEXTAREA" || el.tagName === "INPUT") {
          const v = el.value || "";
          if (typeof el.selectionStart === "number" && typeof el.selectionEnd === "number") {
            s = v.substring(el.selectionStart, el.selectionEnd);
          } else {
            s = v;
          }
        }
        if (el.isContentEditable) {
          s = el.innerText || el.textContent || "";
        }
      }
      s = s.replace(/\s+/g, " ").trim();
      if (!s) {
        const meta = document.querySelector('meta[name="description"]');
        s = (meta && meta.content) ? meta.content.trim() : "";
      }
      return s.slice(0, 4000);
    } catch (_) { return ""; }
  }

  function pageTitle() {
    try {
      const og = document.querySelector('meta[property="og:title"]');
      return (og && og.content) ? og.content : (document.title || "");
    } catch (_) { return ""; }
  }

  function canonicalURL() {
    try {
      const link = document.querySelector('link[rel="canonical"]');
      if (link && link.href) return link.href;
      const og = document.querySelector('meta[property="og:url"]');
      if (og && og.content) return og.content;
      return (document.location && document.location.href) || "";
    } catch (_) { return ""; }
  }

  function run() {
    const results = {
      selection: textSel(),
      title: pageTitle(),
      url: canonicalURL()
    };
    const dict = {};
    dict["NSExtensionJavaScriptPreprocessingResultsKey"] = results;
    return dict;
  }

  return run();
})();
