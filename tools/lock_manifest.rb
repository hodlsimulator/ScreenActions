#!/usr/bin/env ruby
# lock_manifest.rb — Sanitise MV3 manifest in SOURCE before packaging.
# Idempotent: fixes blank strings and enforces the Screen Actions baseline.

require 'json'

path = ARGV[0] or abort("lock_manifest.rb: missing MANIFEST path")
json = JSON.parse(File.read(path))
changed = false

def ensure_hash!(h, key); changed = false; h[key] = {} unless h[key].is_a?(Hash); changed; end
def ensure_arr!(h, key); changed = false; h[key] = [] unless h[key].is_a?(Array); changed; end

changed |= ensure_hash!(json, 'icons')
changed |= ensure_hash!(json, 'action')
changed |= ensure_hash!(json, 'background')
changed |= ensure_arr!(json, 'permissions')
changed |= ensure_arr!(json, 'host_permissions')
changed |= ensure_arr!(json, 'content_scripts')

# Icons (keep WebRes paths)
icons = json['icons']
%w[48 64 96 128 256 512].each do |sz|
  want = "WebRes/images/icon-#{sz}-squircle.png"
  if icons[sz] != want; icons[sz] = want; changed = true; end
end

# Action
act = json['action']
if act['default_title'] != 'Screen Actions'; act['default_title'] = 'Screen Actions'; changed = true; end
if act['default_popup'] != 'WebRes/popup.html'; act['default_popup'] = 'WebRes/popup.html'; changed = true; end
act['default_icon'] ||= {}
{'48'=>'WebRes/images/icon-48-squircle.png',
 '96'=>'WebRes/images/icon-96-squircle.png',
 '128'=>'WebRes/images/icon-128-squircle.png'}.each do |k,v|
  if act['default_icon'][k] != v; act['default_icon'][k] = v; changed = true; end
end

# Background
bg = json['background']
if bg['service_worker'] != 'WebRes/background.js'; bg['service_worker'] = 'WebRes/background.js'; changed = true; end

# Permissions
want_perms = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
if (json['permissions']||[]).sort != want_perms.sort
  json['permissions'] = want_perms; changed = true
end

# Host permissions (fix blanks)
if json['host_permissions'].empty? || json['host_permissions'].include?('')
  json['host_permissions'] = ['<all_urls>']; changed = true
end

# Content script (fix blanks; keep WebRes path)
cs = [{
  'matches'    => ['<all_urls>'],
  'js'         => ['WebRes/content_selection.js'],
  'run_at'     => 'document_idle',
  'all_frames' => true
}]
if json['content_scripts'] != cs
  json['content_scripts'] = cs; changed = true
end

# Do NOT add default_locale (avoids Settings error)
if json.key?('default_locale'); json.delete('default_locale'); changed = true; end

if changed
  File.write(path, JSON.pretty_generate(json))
  STDERR.puts "lock_manifest.rb: patched #{path}"
else
  STDERR.puts "lock_manifest.rb: ok (no changes)"
end
