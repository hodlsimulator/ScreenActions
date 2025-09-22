#!/usr/bin/env ruby
require 'xcodeproj'
require 'open3'
require 'time'
require 'tmpdir'

PROJECT  = 'Screen Actions.xcodeproj'
PROFDIR  = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
TARGETS  = [
  'Screen Actions',
  'ScreenActionsWebExtension',
  'ScreenActionsShareExtension',
  'ScreenActionsActionExtension',
  'ScreenActionsControlsExtension',
  'ScreenActionsControls'
]
TEAM_ID  = '92HEPEJ42Z'

def pb(plist, key)
  out, st = Open3.capture2('/usr/libexec/PlistBuddy','-c',"Print :#{key}", plist)
  st.success? ? out.strip : nil
end

def decode_profile(path)
  tmp = File.join(Dir.mktmpdir, 'p.plist')
  ok  = system('/bin/sh','-lc', %Q{/usr/bin/security cms -D -i "#{path}" > "#{tmp}"})
  return nil unless ok
  appid  = pb(tmp,'Entitlements:application-identifier')
  uuid   = pb(tmp,'UUID')
  name   = pb(tmp,'Name')
  gtl    = pb(tmp,'Entitlements:get-task-allow') == 'true'
  expraw = pb(tmp,'ExpirationDate')
  exp    = (Time.parse(expraw) rescue Time.at(0))
  adhoc  = system('/usr/libexec/PlistBuddy','-c','Print :ProvisionedDevices', tmp, [:out,:err]=>File::NULL)
  ent    = pb(tmp,'ProvisionsAllDevices') == 'true'
  File.delete(tmp) rescue nil
  return nil unless appid && uuid
  {appid: appid, uuid: uuid, name: name, get_task_allow: gtl, expires: exp, adhoc: adhoc, enterprise: ent}
end

def type_of(p)
  return 'Development' if p[:get_task_allow]
  return 'Enterprise'  if p[:enterprise]
  return 'AdHoc'       if p[:adhoc]
  'AppStore'
end

proj = Xcodeproj::Project.open(PROJECT)
wanted = {}
TARGETS.each do |tname|
  t = proj.targets.find { |tt| tt.name == tname } or next
  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } || t.build_configuration_list.build_configurations.first
  bid = bc&.build_settings&.fetch('PRODUCT_BUNDLE_IDENTIFIER', nil)
  wanted[tname] = bid if bid
end

profiles = Dir["#{PROFDIR}/*.mobileprovision"].map { |p| decode_profile(p) }.compact

puts "Target → BundleID"
wanted.each do |tname, bid|
  hits = profiles.select do |p|
    next false unless p[:expires] > Time.now
    team, id = p[:appid].split('.', 2)
    team == '92HEPEJ42Z' && id == bid && type_of(p) == 'AppStore'
  end.sort_by { |p| p[:expires] }.reverse
  puts "• #{tname} → #{bid}"
  if hits.empty?
    puts "  (no App Store profiles installed for 92HEPEJ42Z.#{bid})"
  else
    hits.each { |p| puts "  AppStore: #{p[:name]} (UUID #{p[:uuid]}) exp #{p[:expires].strftime('%Y-%m-%d')}" }
  end
end
