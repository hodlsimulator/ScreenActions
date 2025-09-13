// Runs inside Safari to hand selection/title/URL to the Share extension.
function run() {
  var selection = "";
  try { selection = (window.getSelection && window.getSelection().toString()) || ""; } catch (e) {}

  var title = "";
  try { title = document.title || ""; } catch (e) {}

  var url = "";
  try { url = (document.location && document.location.href) || ""; } catch (e) {}

  var results = { selection: selection, title: title, url: url };
  var dict = {};
  dict["NSExtensionJavaScriptPreprocessingResultsKey"] = results;
  return dict;
}
run();
