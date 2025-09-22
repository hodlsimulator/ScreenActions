#!/usr/bin/env ruby
# Pins Release to MANUAL signing with Apple Distribution + App Store profile for each target.
require 'xcodeproj'
require 'open3'
require 'json'
require 'time'

PROJECT  = 'Screen Actions.xcodeproj'
TEAM_ID  = '92HEPEJ42Z' # <-- your team
TARGETS  = [
  'Screen Actions',
  'ScreenActionsWebExtension',
  'ScreenActionsShareExtension',
  'ScreenActionsActionExtension',
  'ScreenActionsControls'
]

def decode_profile(path)
  xml, st1 = Open3.capture2('/usr/bin/security', 'cms', '-D', '-i', path)
  return nil unless st1.success?
  json, st2 = Open3.capture3('plutil', '-convert', 'json', '-o', '-', '-', stdin_data: xml)
  return nil unless st2.success?
  JSON.parse(json)
rescue
  nil
end

def load_profiles
  dir = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
  Dir["#{dir}/*.mobileprovision"].map do |p|
    d = decode_profile(p) or next
    ent = d['Entitlements'] || {}
    {
      name: d['Name'],
      uuid: d['UUID'],
      team: (d['TeamIdentifier'] || d['ApplicationIdentifierPrefix'] || ['']).first,
      appid: ent['application-identifier'],
      get_task_allow: !!ent['get-task-allow'],
      provisions_all: !!d['ProvisionsAllDevices'],
      has_devices: d['ProvisionedDevices'].is_a?(Array),
      expires: (Time.parse(d['ExpirationDate'].to_s) rescue Time.at(0)),
      path: p
    }
  end.compact
end

def appstore_profile_for(profiles, team, bundle_id)
  wanted = "#{team}.#{bundle_id}"
  profiles.select { |p|
    p[:team] == team &&
    p[:appid] == wanted &&
    p[:expires] > Time.now &&
    !p[:get_task_allow] && !p[:provisions_all] && !p[:has_devices]
  }.sort_by { |p| p[:expires] }.reverse.first
end

proj = Xcodeproj::Project.open(PROJECT)
profiles = load_profiles

pinned   = []
missing  = []

TARGETS.each do |name|
  t = proj.targets.find { |tt| tt.name == name }
  next unless t

  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } ||
       t.build_configuration_list.build_configurations.first
  bs = bc.build_settings
  bid = bs['PRODUCT_BUNDLE_IDENTIFIER'] or next

  prof = appstore_profile_for(profiles, TEAM_ID, bid)
  if prof
    # Manual + Distribution on device SDK with explicit profile
    bs['CODE_SIGN_STYLE'] = 'Manual'
    bs['DEVELOPMENT_TEAM'] = TEAM_ID
    bs['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
    bs['PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]'] = prof[:name]
    # remove generic overrides that cause conflicts
    %w[CODE_SIGN_IDENTITY PROVISIONING_PROFILE PROVISIONING_PROFILE_SPECIFIER].each { |k| bs.delete(k) }
    pinned << "#{name} → #{prof[:name]}"
  else
    # Fall back: clear identity/profile so there’s no conflict; stays Automatic for now
    bs.delete('CODE_SIGN_IDENTITY')
    bs.delete('CODE_SIGN_IDENTITY[sdk=iphoneos*]')
    bs.delete('PROVISIONING_PROFILE')
    bs.delete('PROVISIONING_PROFILE_SPECIFIER')
    bs.delete('PROVISIONING_PROFILE[sdk=iphoneos*]')
    bs['CODE_SIGN_STYLE'] = 'Automatic'
    bs['DEVELOPMENT_TEAM'] = TEAM_ID
    missing << "#{name} (#{bid})"
  end
end

proj.save
puts "✓ Pinned (Release → Manual, Distribution):"
pinned.each { |s| puts "  - #{s}" }
unless missing.empty?
  puts "\n⚠️  No App Store profile found for:"
  missing.each { |s| puts "  - #{s}" }
  puts "Create App Store profiles in Xcode → Settings → Accounts → Manage Profiles for those bundle IDs, then re-run this script."
end
puts "\n→ Finally: zsh archive_and_verify.zsh"
