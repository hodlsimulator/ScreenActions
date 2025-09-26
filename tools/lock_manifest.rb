#!/usr/bin/env ruby
# lock_manifest.rb — normalise MV3 manifest for iOS Safari (idempotent; never hard-fails)
require "json"

path = ARGV[0] || File.join(__dir__, "..", "ScreenActionsWebExtension", "WebRes", "manifest.json")
unless File.file?(path)
  warn "lock_manifest.rb: no manifest at #{path.inspect} (skip)"; exit 0
end

m = JSON.parse(File.read(path)); changed = false
def h!(o,k); o[k] = {}  unless o[k].is_a?(Hash);  end
def a!(o,k); o[k] = [] unless o[k].is_a?(Array); end

h!(m,"icons"); h!(m,"action"); h!(m,"background")
a!(m,"permissions"); a!(m,"host_permissions"); a!(m,"content_scripts")

# Manifest is packaged under WebRes/, but Safari resolves paths from the *extension root*.
# Your copy phases place files under WebRes/... in the appex. Use WebRes/... everywhere.
icons = {
  "48"=>"WebRes/images/icon-48-squircle.png",
  "64"=>"WebRes/images/icon-64-squircle.png",
  "96"=>"WebRes/images/icon-96-squircle.png",
  "128"=>"WebRes/images/icon-128-squircle.png",
  "256"=>"WebRes/images/icon-256-squircle.png",
  "512"=>"WebRes/images/icon-512-squircle.png"
}
icons.each { |k,v| changed |= (m.dig("icons",k) != v); m["icons"][k] = v }

act = m["action"]; act["default_icon"] ||= {}
changed |= (act["default_title"] != "Screen Actions");     act["default_title"] = "Screen Actions"
changed |= (act["default_popup"] != "WebRes/popup.html");  act["default_popup"] = "WebRes/popup.html"
icons.slice("48","96","128").each { |k,v| changed |= (act["default_icon"][k] != v); act["default_icon"][k] = v }

bg = m["background"]
changed |= (bg["service_worker"] != "WebRes/background.js"); bg["service_worker"] = "WebRes/background.js"

need = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
changed |= (Array(m["permissions"]).sort != need.sort); m["permissions"] = need

# Never blanks
if m["host_permissions"].empty? || m["host_permissions"].include?("")
  m["host_permissions"] = ["<all_urls>"]; changed = true
end

cs = [{
  "matches"    => ["<all_urls>"],
  "js"         => ["WebRes/content_selection.js"],
  "run_at"     => "document_idle",
  "all_frames" => true
}]
changed |= (m["content_scripts"] != cs); m["content_scripts"] = cs

# No default_locale unless you ship _locales at bundle root
if m.key?("default_locale"); m.delete("default_locale"); changed = true; end

if changed
  File.write(path, JSON.pretty_generate(m))
  warn "lock_manifest.rb: patched #{path}"
else
  warn "lock_manifest.rb: ok (no changes)"
end
