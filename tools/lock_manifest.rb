#!/usr/bin/env ruby
# Ensures the packaged WebExtension manifest has the right permissions and content script.
# Usage: ruby tools/lock_manifest.rb <path-to-packaged-manifest.json>
require 'json'

path = ARGV[0] or abort("lock_manifest.rb: missing MANIFEST path")
json = JSON.parse(File.read(path))

changed = false

# host_permissions → <all_urls>
if json['host_permissions'] != ['<all_urls>']
  json['host_permissions'] = ['<all_urls>']
  changed = true
end

# content_scripts → inject our selection streamer on all pages
need_script = true
if json['content_scripts'].is_a?(Array)
  json['content_scripts'].each do |cs|
    if cs.is_a?(Hash) &&
       cs['js'].is_a?(Array) && cs['js'].include?('WebRes/content_selection.js') &&
       cs['matches'].is_a?(Array) && cs['matches'].include?('<all_urls>')
      need_script = false
      break
    end
  end
else
  json['content_scripts'] = []
end

if need_script
  json['content_scripts'] = [{
    'matches'   => ['<all_urls>'],
    'js'        => ['WebRes/content_selection.js'],
    'run_at'    => 'document_idle',
    'all_frames'=> true
  }]
  changed = true
end

# Optional: keep permissions list predictable
perms = json['permissions'].is_a?(Array) ? json['permissions'] : []
want  = %w[activeTab tabs scripting clipboardWrite nativeMessaging storage]
if perms.sort != want.sort
  json['permissions'] = want
  changed = true
end

if changed
  File.write(path, JSON.pretty_generate(json))
  STDERR.puts "lock_manifest.rb: patched #{path}"
else
  STDERR.puts "lock_manifest.rb: ok (no changes)"
end
