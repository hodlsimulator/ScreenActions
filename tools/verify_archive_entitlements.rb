#!/usr/bin/env ruby
# Guard (Sept 2025): verify the Safari Web Extension **does not** request ExtensionKit.
# Also checks: Distribution signing (get-task-allow = 0), manifest path, and App Group.

require 'json'
require 'open3'
require 'fileutils'

ARCHIVE = ARGV[0] or abort "Usage: #{$0} /path/to/App.xcarchive"

GROUP_ID   = 'group.com.conornolan.screenactions'
EXT_POINT  = 'com.apple.Safari.web-extension'
EXTKIT_KEY = 'com.apple.developer.extensionkit.extension-point-identifiers'

def ok(msg)    puts "✓ #{msg}" end
def fail!(arr) puts arr.join("\n"); exit 1 end

def plutil_json(path)
  out, st = Open3.capture2('plutil', '-convert', 'json', '-o', '-', path)
  raise "plutil failed for #{path}" unless st.success?
  JSON.parse(out)
end

def read_codesign_entitlements(path)
  # Silence codesign's stderr chatter ("Executable=…", colon deprecation) so the output is clean JSON.
  cmd = %Q{/usr/bin/codesign -d --entitlements :- "#{path}" 2>/dev/null | plutil -convert json -o - -}
  out, st = Open3.capture2('/bin/sh', '-c', cmd)
  raise "codesign|plutil failed for #{path}" unless st.success?
  JSON.parse(out)
end

failures = []

archive = File.expand_path(ARCHIVE)
abort "xcarchive not found: #{archive}" unless File.directory?(archive)

apps = Dir[File.join(archive, 'Products', 'Applications', '*.app')]
abort "No .app inside archive." if apps.empty?

app_path = apps.first
ok "Found app: #{File.basename(app_path)}"

# App entitlements: Distribution (get-task-allow = 0)
begin
  app_ents = read_codesign_entitlements(app_path)
  gta = app_ents['get-task-allow']
  if gta == false || gta == 0
    ok "App signed for distribution (get-task-allow = 0)"
  else
    failures << "✗ App not signed for distribution (get-task-allow is #{gta.inspect})"
  end
rescue => e
  failures << "✗ Unable to read app entitlements: #{e.message}"
end

# Find Safari Web Extension appex and validate
appexes = Dir[File.join(app_path, 'PlugIns', '*.appex')]
if appexes.empty?
  failures << "✗ No .appex found in #{File.basename(app_path)}"
else
  checked_any = false
  appexes.each do |appex|
    begin
      info = plutil_json(File.join(appex, 'Info.plist'))
    rescue => e
      failures << "✗ #{File.basename(appex)}: Info.plist unreadable (#{e.message})"
      next
    end

    ext = info['NSExtension'] || {}
    point = ext['NSExtensionPointIdentifier']
    next unless point == EXT_POINT
    checked_any = true
    ok "#{File.basename(appex)}: NSExtensionPointIdentifier = #{point}"

    attrs = ext['NSExtensionAttributes'] || {}
    manifest = attrs['SFSafariWebExtensionManifestPath']
    if manifest == 'WebRes/manifest.json'
      ok "#{File.basename(appex)}: SFSafariWebExtensionManifestPath = #{manifest}"
    else
      failures << "✗ #{File.basename(appex)}: wrong SFSafariWebExtensionManifestPath (#{manifest.inspect})"
    end

    begin
      ents = read_codesign_entitlements(appex)
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

    # README plan: NO ExtensionKit entitlement anywhere.
    if ents.key?(EXTKIT_KEY) && ents[EXTKIT_KEY].is_a?(Array) && !ents[EXTKIT_KEY].empty?
      failures << "✗ #{File.basename(appex)}: #{EXTKIT_KEY} present (#{ents[EXTKIT_KEY].inspect}) — remove it per the README plan."
    else
      ok "#{File.basename(appex)}: no ExtensionKit entitlement requested"
    end
  end
  failures << "✗ No Safari Web Extension appex found to verify." unless checked_any
end

if failures.empty?
  puts "✅ All checks passed (Distribution signing, correct manifest path, App Group present, and NO ExtensionKit entitlement)."
  exit 0
else
  fail!(failures)
end
