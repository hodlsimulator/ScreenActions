#!/usr/bin/env ruby
# lock_manifest.rb — normalise MV3 manifest for iOS Safari without blanking matches/hosts.
require "json"

path = ARGV[0] || File.join(__dir__, "..", "ScreenActionsWebExtension", "WebRes", "manifest.json")
abort "lock_manifest.rb: no manifest at #{path.inspect}" unless File.file?(path)

m = JSON.parse(File.read(path)); changed = false
def h!(o,k); o[k] = {} unless o[k].is_a?(Hash); end
def a!(o,k); o[k] = [] unless o[k].is_a?(Array); end

h!(m,"icons"); h!(m,"action"); h!(m,"background")
a!(m,"permissions"); a!(m,"host_permissions"); a!(m,"content_scripts")

# Ensure icons and popup paths are under WebRes/
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
changed |= (act["default_title"] != "Screen Actions"); act["default_title"] = "Screen Actions"
changed |= (act["default_popup"] != "WebRes/popup.html"); act["default_popup"] = "WebRes/popup.html"
icons.slice("48","96","128").each { |k,v| changed |= (act["default_icon"][k] != v); act["default_icon"][k] = v }

bg = m["background"]
changed |= (bg["service_worker"] != "WebRes/background.js"); bg["service_worker"] = "WebRes/background.js"

needed_perms = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
changed |= (Array(m["permissions"]).sort != needed_perms.sort); m["permissions"] = needed_perms

# Preserve existing patterns; if missing/blank, default to <all_urls>
def ensure_all_urls!(arr_key, obj)
  cur = Array(obj[arr_key]).map(&:to_s).map(&:strip)
  if cur.empty? || cur == [""] then obj[arr_key] = ["<all_urls>"]; true else false end
end
changed |= ensure_all_urls!("host_permissions", m)

cs_template = {
  "matches"    => ["<all_urls>"],
  "js"         => ["WebRes/content_selection.js"],
  "run_at"     => "document_idle",
  "all_frames" => true
}
if !m["content_scripts"].is_a?(Array) || m["content_scripts"].empty?
  m["content_scripts"] = [cs_template]; changed = true
else
  first = m["content_scripts"][0] ||= {}
  changed |= ensure_all_urls!("matches", first)
  changed |= (first["js"] != cs_template["js"]); first["js"] = cs_template["js"]
  changed |= (first["run_at"] != "document_idle"); first["run_at"] = "document_idle"
  changed |= (first["all_frames"] != true); first["all_frames"] = true
end

# default_locale omitted — locales live under WebRes/_locales
if m.key?("default_locale"); m.delete("default_locale"); changed = true; end

File.write(path, JSON.pretty_generate(m)) if changed
warn(changed ? "lock_manifest.rb: patched #{path}" : "lock_manifest.rb: ok (no changes)")
