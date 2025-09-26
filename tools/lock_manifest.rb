#!/usr/bin/env ruby
# Idempotent; safe with/without args; never fails build.
require "json"
path = ARGV[0] || File.join(__dir__, "..", "ScreenActionsWebExtension", "WebRes", "manifest.json")
unless File.file?(path)
  warn "lock_manifest.rb: no manifest at #{path.inspect} (skip)"; exit 0
end
m = JSON.parse(File.read(path)); changed = false
def h!(m,k); m[k] = {}  unless m[k].is_a?(Hash);  end
def a!(m,k); m[k] = [] unless m[k].is_a?(Array); end
h!(m,"icons"); h!(m,"action"); h!(m,"background"); a!(m,"permissions"); a!(m,"host_permissions"); a!(m,"content_scripts")

# WebRes paths (your appex packages under WebRes/)
icons = {
  "48"=>"WebRes/images/icon-48-squircle.png","64"=>"WebRes/images/icon-64-squircle.png",
  "96"=>"WebRes/images/icon-96-squircle.png","128"=>"WebRes/images/icon-128-squircle.png",
  "256"=>"WebRes/images/icon-256-squircle.png","512"=>"WebRes/images/icon-512-squircle.png"
}
icons.each { |k,v| changed |= (m["icons"][k] != v); m["icons"][k] = v }

act = m["action"]; changed |= (act["default_title"] != "Screen Actions"); act["default_title"] = "Screen Actions"
changed |= (act["default_popup"] != "WebRes/popup.html"); act["default_popup"] = "WebRes/popup.html"
act["default_icon"] ||= {}; icons.slice("48","96","128").each { |k,v| changed |= (act["default_icon"][k] != v); act["default_icon"][k]=v }

bg = m["background"]; changed |= (bg["service_worker"] != "WebRes/background.js"); bg["service_worker"] = "WebRes/background.js"

want_perms = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
changed |= (Array(m["permissions"]).sort != want_perms.sort); m["permissions"] = want_perms

if m["host_permissions"].empty? || m["host_permissions"].include?("")
  m["host_permissions"] = ["<all_urls>"]; changed = true
end
cs = [{
  "matches"=>["<all_urls>"], "js"=>["WebRes/content_selection.js"], "run_at"=>"document_idle", "all_frames"=>true
}]
changed |= (m["content_scripts"] != cs); m["content_scripts"] = cs

if m.key?("default_locale"); m.delete("default_locale"); changed = true; end
if changed
  File.write(path, JSON.pretty_generate(m)); warn "lock_manifest.rb: patched #{path}"
else
  warn "lock_manifest.rb: ok (no changes)"
end
