#
//  verify_archive_entitlements.rb
//  Screen Actions
//
//  Created by . . on 9/17/25.
//

#!/usr/bin/env ruby
# Guard: verifies the Safari Web Extension entitlement **inside an .xcarchive**
# Usage: ruby tools/verify_archive_entitlements.rb ".provtmp/ScreenActions.xcarchive"
require 'json'
require 'open3'
require 'fileutils'

ARCHIVE_ARG = ARGV[0] or abort "Usage: #{$0} /path/to/App.xcarchive"
GROUP_ID = 'group.com.conornolan.screenactions'
NEEDED_EXT_POINT = 'com.apple.Safari.web-extension'
NEEDED_EXTKIT_KEY = 'com.apple.developer.extensionkit.extension-point-identifiers'

def ok(msg)   puts "✓ #{msg}" end
def fail!(a)  puts a.join("\n"); exit 1 end

def plutil_json(obj_path)
  out, st = Open3.capture2('plutil', '-convert', 'json', '-o', '-', obj_path)
  raise "plutil failed for #{obj_path}" unless st.success?
  JSON.parse(out)
end

def codesign_entitlements_json(signed_path)
  # Extract embedded entitlements as JSON
  raw, st = Open3.capture2('/usr/bin/codesign', '-d', '--entitlements', ':-', signed_path)
  raise "codesign failed for #{signed_path}" unless st.success?
  out, st2 = Open3.capture2('plutil', '-convert', 'json', '-o', '-', '-')
  # Feed raw via stdin to plutil (need a second process that reads STDIN)
rescue
  # Fallback: run one pipeline with Open3
  out, st = Open3.capture2('/bin/sh', '-c', %Q{/usr/bin/codesign -d --entitlements :- "#{signed_path}" | plutil -convert json -o - -})
  raise "codesign|plutil failed for #{signed_path}" unless st.success?
  JSON.parse(out)
end

failures = []

archive = File.expand_path(ARCHIVE_ARG)
abort "xcarchive not found: #{archive}" unless File.directory?(archive)

apps = Dir[File.join(archive, 'Products', 'Applications', '*.app')]
abort "No .app inside archive." if apps.empty?
app_path = apps.first
ok "Found app: #{File.basename(app_path)}"

appexes = Dir[File.join(app_path, 'PlugIns', '*.appex')]
abort "No .appex inside #{app_path}" if appexes.empty?

checked_any = false

appexes.each do |appex|
  info_plist = File.join(appex, 'Info.plist')
  begin
    info = plutil_json(info_plist)
  rescue
    failures << "✗ #{File.basename(appex)}: Info.plist unreadable"
    next
  end

  ext_dict = info['NSExtension'] || {}
  point_id = ext_dict['NSExtensionPointIdentifier']
  next unless point_id == 'com.apple.Safari.web-extension' # only check the Safari Web Extension

  checked_any = true
  ok "#{File.basename(appex)}: NSExtensionPointIdentifier is #{point_id}"

  attrs = ext_dict['NSExtensionAttributes'] || {}
  manifest_path = attrs['SFSafariWebExtensionManifestPath']
  if manifest_path == 'WebRes/manifest.json'
    ok "#{File.basename(appex)}: SFSafariWebExtensionManifestPath=#{manifest_path}"
  else
    failures << "✗ #{File.basename(appex)}: wrong SFSafariWebExtensionManifestPath (#{manifest_path.inspect})"
  end

  # Entitlements on the signed appex
  begin
    ents = codesign_entitlements_json(appex)
  rescue => e
    failures << "✗ #{File.basename(appex)}: unable to read entitlements (#{e.message})"
    next
  end

  groups = ents['com.apple.security.application-groups'] || []
  if groups.is_a?(Array) && groups.include?(GROUP_ID)
    ok "#{File.basename(appex)}: App Group present (#{GROUP_ID})"
  else
    failures << "✗ #{File.basename(appex)}: App Group missing (need #{GROUP_ID})"
  end

  extkits = ents[NEEDED_EXTKIT_KEY] || []
  if extkits.is_a?(Array) && extkits.include?(NEEDED_EXT_POINT)
    ok "#{File.basename(appex)}: #{NEEDED_EXTKIT_KEY} includes #{NEEDED_EXT_POINT}"
  else
    failures << "✗ #{File.basename(appex)}: #{NEEDED_EXTKIT_KEY} does not include #{NEEDED_EXT_POINT} (distribution profile problem?)"
  end
end

failures << "✗ No Safari Web Extension appex found to verify." unless checked_any

if failures.empty?
  puts "✅ All distribution entitlements look good."
  exit 0
else
  fail!(failures)
end
