#!/usr/bin/env ruby
# Pins RELEASE to Manual + Apple Distribution using the 4 UUIDs you installed.
# Includes safety checks: each UUID must be an App Store profile and match the target's bundle id.

require 'xcodeproj'
require 'open3'
require 'time'

PROJECT = 'Screen Actions.xcodeproj'
PROFDIR = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
TEAM_ID = '92HEPEJ42Z'

# === Edit only if your UUIDs change ===
UUIDS = {
  'Screen Actions'               => '017dd58d-c617-4fce-b26a-8df0290074a5', # App
  'ScreenActionsWebExtension'    => '10840d7e-35e4-4786-9db8-4dd796b1d0c8', # WebExt
  'ScreenActionsShareExtension'  => 'fe59b52e-8bdc-4b3b-a308-507b2dff1ffc', # Share
  'ScreenActionsActionExtension' => 'e1ebdb16-3b85-4d6b-a2a2-16846b077cb2', # Action
}

def pb(plist, key)
  out, st = Open3.capture2('/usr/libexec/PlistBuddy','-c',"Print :#{key}", plist)
  st.success? ? out.strip : nil
end

def decode_uuid(uuid)
  path = File.join(PROFDIR, "#{uuid}.mobileprovision")
  return { ok:false, reason:"missing file #{path}" } unless File.exist?(path)
  tmp = File.join(Dir.mktmpdir, 'p.plist')
  ok  = system('/bin/sh','-lc', %Q{/usr/bin/security cms -D -i "#{path}" > "#{tmp}"})
  return { ok:false, reason:"cannot decode #{path}" } unless ok

  appid   = pb(tmp,'Entitlements:application-identifier')
  name    = pb(tmp,'Name')
  gtl     = (pb(tmp,'Entitlements:get-task-allow') == 'true')
  exp     = (Time.parse(pb(tmp,'ExpirationDate') || '') rescue Time.at(0))
  adhoc   = system('/usr/libexec/PlistBuddy','-c','Print :ProvisionedDevices', tmp, [:out,:err]=>File::NULL)
  ent     = (pb(tmp,'ProvisionsAllDevices') == 'true')
  File.delete(tmp) rescue nil

  { ok:true, appid:appid, name:name, get_task_allow:gtl, exp:exp, adhoc:adhoc, enterprise:ent }
end

proj = Xcodeproj::Project.open(PROJECT)
pinned = []
errors = []

UUIDS.each do |tname, uuid|
  t = proj.targets.find { |x| x.name == tname }
  unless t
    errors << "Target not found: #{tname}"
    next
  end

  # Determine bundle id from Release config
  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } ||
       t.build_configuration_list.build_configurations.first
  bid = bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  unless bid && !bid.empty?
    errors << "#{tname}: PRODUCT_BUNDLE_IDENTIFIER missing"
    next
  end

  # Decode + validate the profile
  info = decode_uuid(uuid)
  unless info[:ok]
    errors << "#{tname}: #{info[:reason]}"
    next
  end
  team, appid_bid = (info[:appid] || '').split('.', 2)
  unless team == TEAM_ID && appid_bid == bid
    errors << "#{tname}: profile appid mismatch (profile #{info[:appid].inspect} vs TEAM_ID.#{bid})"
    next
  end
  if info[:get_task_allow] || info[:adhoc] || info[:enterprise]
    errors << "#{tname}: profile is not App Store (Dev/AdHoc/Enterprise)"
    next
  end
  if info[:exp] <= Time.now
    errors << "#{tname}: profile expired"
    next
  end

  # Pin Release → Manual + Distribution + UUID specifier (device SDK)
  t.build_configuration_list.build_configurations.each do |cfg|
    next unless cfg.name == 'Release'
    bs = cfg.build_settings
    bs['CODE_SIGN_STYLE'] = 'Manual'
    bs['DEVELOPMENT_TEAM'] = TEAM_ID
    bs['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
    # Using UUID avoids name collisions
    bs['PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]'] = uuid
    # Clean any conflicting keys
    %w[
      CODE_SIGN_IDENTITY
      PROVISIONING_PROFILE
      PROVISIONING_PROFILE_SPECIFIER
      PROVISIONING_PROFILE[sdk=iphoneos*]
    ].each { |k| bs.delete(k) }
  end

  pinned << "#{tname} → #{uuid}"
end

proj.save

if errors.any?
  puts "✗ Some items failed:"
  puts errors.map { |e| "  - #{e}" }.join("\n")
  exit 1
else
  puts "✓ Pinned Release to Distribution profiles:\n  - " + pinned.join("\n  - ")
  puts "→ Now archive: zsh archive_and_verify.zsh"
end
