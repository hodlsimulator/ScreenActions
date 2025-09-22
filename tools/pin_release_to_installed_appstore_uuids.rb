#!/usr/bin/env ruby
# Pins RELEASE to Manual + Apple Distribution using the INSTALLED App Store
# provisioning profiles found in ~/Library/MobileDevice/Provisioning Profiles.
# Matches profiles by application-identifier = TEAMID.BUNDLEID (exact) and picks
# the newest (non-expired) App Store profile per target.

require 'xcodeproj'
require 'open3'
require 'json'
require 'time'

PROJECT   = 'Screen Actions.xcodeproj'
PROFDIR   = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
TEAM_ID   = '92HEPEJ42Z'
TARGETS   = {
  'Screen Actions'                => 'com.conornolan.Screen-Actions',
  'ScreenActionsWebExtension'     => 'com.conornolan.Screen-Actions.ScreenActionsWebExtension',
  'ScreenActionsShareExtension'   => 'com.conornolan.Screen-Actions.ScreenActionsShareExtension',
  'ScreenActionsActionExtension'  => 'com.conornolan.Screen-Actions.ScreenActionsActionExtension',
}

def decode(path)
  xml, st1 = Open3.capture2('/usr/bin/security','cms','-D','-i',path)
  return nil unless st1.success?
  out, st2 = Open3.capture2('plutil','-convert','json','-o','-','-', stdin_data: xml)
  return nil unless st2.success?
  JSON.parse(out)
rescue
  nil
end

def appstore_profile?(plist)
  ent = plist['Entitlements'] || {}
  gtl = !!ent['get-task-allow']
  enterprise = !!plist['ProvisionsAllDevices']
  adhoc = plist.key?('ProvisionedDevices')
  !gtl && !enterprise && !adhoc
end

# Index installed App Store profiles by bundle id
index = Hash.new { |h,k| h[k] = [] }
Dir["#{PROFDIR}/*.mobileprovision"].each do |f|
  p = decode(f) or next
  ent  = p['Entitlements'] || {}
  team = (p['TeamIdentifier'] || p['ApplicationIdentifierPrefix'] || ['']).first
  appid = ent['application-identifier'] or next
  next unless team == TEAM_ID
  bid = appid.sub(/^#{Regexp.escape(TEAM_ID)}\./, '')
  next unless appstore_profile?(p)
  exp = Time.parse(p['ExpirationDate'].to_s) rescue Time.at(0)
  next if exp <= Time.now
  index[bid] << { uuid: p['UUID'], name: p['Name'], exp: exp, path: f }
end

proj = Xcodeproj::Project.open(PROJECT)
pinned   = []
missing  = []

TARGETS.each do |tname, bid|
  t = proj.targets.find { |tt| tt.name == tname }
  next unless t
  best = (index[bid] || []).max_by { |h| h[:exp] }
  if best
    t.build_configuration_list.build_configurations.each do |cfg|
      next unless cfg.name == 'Release'
      bs = cfg.build_settings
      bs['CODE_SIGN_STYLE'] = 'Manual'
      bs['DEVELOPMENT_TEAM'] = TEAM_ID
      bs['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
      # Specifier accepts a UUID; using UUID avoids name collisions.
      bs['PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]'] = best[:uuid]
      # Remove generic overrides that can conflict
      %w[
        CODE_SIGN_IDENTITY
        PROVISIONING_PROFILE
        PROVISIONING_PROFILE_SPECIFIER
        PROVISIONING_PROFILE[sdk=iphoneos*]
      ].each { |k| bs.delete(k) }
    end
    pinned << "#{tname} → #{best[:uuid]} (#{best[:name]})"
  else
    missing << "#{tname} (#{bid})"
  end
end

proj.save
puts "✓ Pinned Release to App Store profiles:\n  - " + pinned.join("\n  - ") unless pinned.empty?
unless missing.empty?
  puts "⚠️  No installed App Store profile found for:\n  - " + missing.join("\n  - ")
  exit 1
end
