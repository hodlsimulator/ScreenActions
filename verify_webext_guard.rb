#
//  verify_webext_guard.rb
//  Screen Actions
//
//  Created by . . on 9/17/25.
//

#!/usr/bin/env ruby
# Guard: verifies iOS Safari Web Extension wiring for Screen Actions.
# - Requires: gem install xcodeproj
require 'xcodeproj'

project_path = 'Screen Actions.xcodeproj'
failures = []

def fail(failures, msg)  failures << "✗ #{msg}"; end
def ok(msg)              puts "✓ #{msg}"; end

unless File.exist?(project_path)
  abort "Project not found: #{project_path}"
end

p = Xcodeproj::Project.open(project_path)

# Targets
app = p.targets.find { |t| t.name == 'Screen Actions' }
ext = p.targets.find { |t| t.name == 'ScreenActionsWebExtension2' } ||
      p.targets.find { |t| t.name == 'ScreenActionsWebExtension' }

if app then ok "Found app target: #{app.name}" else fail(failures, 'App target “Screen Actions” is missing') end
if ext then ok "Found web-extension target: #{ext.name}" else fail(failures, 'Web-extension target is missing') end

if app && ext
  # App embeds the appex (Copy Files → Embed Foundation Extensions, dst_subfolder_spec 13)
  phase = app.copy_files_build_phases.find { |ph| ph.dst_subfolder_spec.to_s == '13' }
  if phase
    ok 'App has “Embed Foundation Extensions” phase'
    pr = ext.product_reference
    if pr && phase.files_references.include?(pr)
      ok 'App embeds the web-extension appex'
    else
      fail(failures, "App does not embed #{ext.name}. Add the product to the Embed phase.")
    end
  else
    fail(failures, 'Missing “Embed Foundation Extensions” copy phase on the app target')
  end

  # App depends on extension
  if app.dependencies.any? { |d| d.target == ext }
    ok 'App has a target dependency on the web-extension'
  else
    fail(failures, 'App target dependency on web-extension is missing')
  end
end

# Extension Info.plist checks
if ext
  bs = ext.build_configuration_list.build_configurations.first.build_settings
  info_rel = bs['INFOPLIST_FILE']
  info_path = info_rel && File.exist?(info_rel) ? info_rel : nil
  if info_path
    plist = File.read(info_path)
    need = {
      'NSExtensionPointIdentifier' => 'com.apple.Safari.web-extension',
      'SFSafariWebExtensionManifestPath' => 'WebRes/manifest.json'
    }
    need.each do |k, v|
      if plist.include?(k) && plist.include?(v)
        ok "Info.plist has #{k}=#{v}"
      else
        fail(failures, "Info.plist missing or mismatched: #{k}=#{v}")
      end
    end
    if plist.include?('NSExtensionPrincipalClass') && plist.include?('SafariWebExtensionHandler')
      ok 'Principal class points at SafariWebExtensionHandler'
    else
      fail(failures, 'Principal class not set to SafariWebExtensionHandler')
    end
  else
    fail(failures, 'Web-extension Info.plist not found from build settings')
  end

  # Manifest presence
  manifest = 'ScreenActionsWebExtension/WebRes/manifest.json'
  if File.exist?(manifest)
    ok "Found manifest: #{manifest}"
  else
    fail(failures, "Manifest missing: #{manifest}")
  end

  # Entitlements setting present (we only check path; the ExtensionKit entitlement is injected by the dev profile at codesign time)
  code_sign_ent = ext.build_configuration_list.build_configurations.map { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] }.compact.uniq
  if code_sign_ent.any? { |s| s.to_s.include?('ScreenActionsWebExtension') }
    ok "Extension CODE_SIGN_ENTITLEMENTS is set (#{code_sign_ent.join(', ')})"
  else
    fail(failures, 'Extension CODE_SIGN_ENTITLEMENTS build setting is not set')
  end
end

puts
if failures.empty?
  puts '✅ All checks passed.'
  exit 0
else
  puts failures.join("\n")
  puts "\nRun your existing fix scripts if needed (e.g. tools/fix_embed_and_resources.rb)."
  exit 1
end
