#!/usr/bin/env ruby
# Lists installed App Store (Distribution) provisioning profiles for each target's bundle id.
require 'xcodeproj'
require 'open3'
require 'json'
require 'time'

PROJECT  = 'Screen Actions.xcodeproj'
TARGETS  = [
  'Screen Actions',
  'ScreenActionsWebExtension',
  'ScreenActionsShareExtension',
  'ScreenActionsActionExtension',
  'ScreenActionsControls'
]

def decode_profile(path)
  # security cms -D -> plist (XML); convert to JSON for easy parsing
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
      appid: ent['application-identifier'], # e.g. TEAMID.com.conornolan.Screen-Actions
      get_task_allow: !!ent['get-task-allow'],
      provisions_all: !!d['ProvisionsAllDevices'],
      has_devices: d['ProvisionedDevices'].is_a?(Array),
      expires: (Time.parse(d['ExpirationDate'].to_s) rescue Time.at(0)),
      path: p
    }
  end.compact
end

def type_of(p)
  return 'Development' if p[:get_task_allow]
  return 'Enterprise'  if p[:provisions_all]
  return 'AdHoc'       if p[:has_devices]
  'AppStore'
end

proj = Xcodeproj::Project.open(PROJECT)
profiles = load_profiles

puts "Target → BundleID"
TARGETS.each do |name|
  t = proj.targets.find { |tt| tt.name == name } or next
  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } ||
       t.build_configuration_list.build_configurations.first
  bs = bc.build_settings
  team = bs['DEVELOPMENT_TEAM']
  bid  = bs['PRODUCT_BUNDLE_IDENTIFIER']
  next unless team && bid

  wanted = "#{team}.#{bid}"
  candidates = profiles.select { |p| p[:appid] == wanted && p[:expires] > Time.now }
  appstore  = candidates.select { |p| type_of(p) == 'AppStore' }.sort_by { |p| p[:expires] }.reverse

  puts "• #{name} → #{bid}"
  if appstore.empty?
    puts "  (no App Store profiles installed for #{wanted})"
  else
    appstore.each { |p| puts "  AppStore: #{p[:name]} (UUID #{p[:uuid]}) exp #{p[:expires].strftime('%Y-%m-%d')}" }
  end
end
