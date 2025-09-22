# // verify_webext_guard.rb — Accept either SAWebExtensionHandler (Obj-C) or SafariWebExtensionHandler (Swift)
#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Screen Actions.xcodeproj'
failures = []
def fail(f, m); f << "✗ #{m}"; end
def ok(m) puts "✓ #{m}"; end

abort "Project not found: #{project_path}" unless File.exist?(project_path)
p = Xcodeproj::Project.open(project_path)

app = p.targets.find { |t| t.name == 'Screen Actions' }
ext = p.targets.find { |t| t.name == 'ScreenActionsWebExtension2' } || p.targets.find { |t| t.name == 'ScreenActionsWebExtension' }

app ? ok("Found app target: #{app.name}") : fail(failures, 'App target “Screen Actions” is missing')
ext ? ok("Found web-extension target: #{ext.name}") : fail(failures, 'Web-extension target is missing')

if app && ext
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
  if app.dependencies.any? { |d| d.target == ext }
    ok 'App has a target dependency on the web-extension'
  else
    fail(failures, 'App target dependency on web-extension is missing')
  end
end

if ext
  bs = ext.build_configuration_list.build_configurations.first.build_settings
  info_rel = bs['INFOPLIST_FILE']
  if info_rel && File.exist?(info_rel)
    plist = File.read(info_rel)
    { 'NSExtensionPointIdentifier' => 'com.apple.Safari.web-extension',
      'SFSafariWebExtensionManifestPath' => 'WebRes/manifest.json' }.each do |k,v|
      (plist.include?(k) && plist.include?(v)) ? ok("Info.plist has #{k}=#{v}") : fail(failures, "Info.plist missing/mismatched: #{k}=#{v}")
    end
    if plist.include?('NSExtensionPrincipalClass') &&
       (plist.include?('SAWebExtensionHandler') || plist.include?('SafariWebExtensionHandler'))
      ok 'Principal class is set (SAWebExtensionHandler / SafariWebExtensionHandler)'
    else
      fail(failures, 'Principal class not set correctly')
    end
  else
    fail(failures, 'Web-extension Info.plist not found from build settings')
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
