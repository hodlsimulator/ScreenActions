#!/usr/bin/env ruby
# lock_manifest.rb — keep MV3 manifest valid for Safari packaging.
# Usage: ruby tools/lock_manifest.rb <path/to/ScreenActionsWebExtension/WebRes/manifest.json>

require 'json'
path = ARGV[0] or abort("lock_manifest.rb: missing MANIFEST path")
json = JSON.parse(File.read(path))
changed = false

# Normalise paths to be RELATIVE TO the manifest location (WebRes/).
def dewebres(v)
  return v unless v.is_a?(String)
  v.start_with?('WebRes/') ? v.sub(/\AWebRes\//, '') : v
end

# action.default_popup
if json['action'].is_a?(Hash)
  want = 'popup.html'
  cur = json['action']['default_popup']
  fixed = dewebres(cur || want)
  if fixed != cur || fixed != want
    json['action']['default_popup'] = want
    changed = true
  end
end

# background.service_worker
if json['background'].is_a?(Hash)
  want = 'background.js'
  cur = json['background']['service_worker']
  fixed = dewebres(cur || want)
  if fixed != cur || fixed != want
    json['background']['service_worker'] = want
    changed = true
  end
end

# icons
if json['icons'].is_a?(Hash)
  json['icons'].keys.each do |k|
    fixed = dewebres(json['icons'][k])
    if fixed != json['icons'][k]
      json['icons'][k] = fixed
      changed = true
    end
  end
end

# permissions (order-insensitive; include what's needed)
want_perms = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
cur_perms  = json['permissions'].is_a?(Array) ? json['permissions'] : []
if cur_perms.sort != want_perms.sort
  json['permissions'] = want_perms
  changed = true
end

# host_permissions — needed for content_scripts "<all_urls>" on Safari.
want_hosts = ['<all_urls>']
if json['host_permissions'] != want_hosts
  json['host_permissions'] = want_hosts
  changed = true
end

# content_scripts — inject selection streamer everywhere.
cs_want = [{
  'matches' => ['<all_urls>'],
  'js' => ['content_selection.js'],
  'run_at' => 'document_idle',
  'all_frames' => true
}]
cur_cs = json['content_scripts']
if cur_cs != cs_want
  json['content_scripts'] = cs_want
  changed = true
end

if changed
  File.write(path, JSON.pretty_generate(json))
  STDERR.puts "lock_manifest.rb: patched #{path}"
else
  STDERR.puts "lock_manifest.rb: ok (no changes)"
end
