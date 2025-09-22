#!/usr/bin/env ruby
require 'open3'
require 'time'
PROFDIR = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')

def pb(plist, key)
  out, st = Open3.capture2('/usr/libexec/PlistBuddy','-c',"Print :#{key}", plist)
  st.success? ? out.strip : nil
end

def decode(path)
  tmp = File.join(Dir.mktmpdir, 'p.plist')
  ok  = system('/bin/sh','-lc', %Q{/usr/bin/security cms -D -i "#{path}" > "#{tmp}"})
  return nil unless ok
  team = pb(tmp,'TeamIdentifier:0') || (pb(tmp,'ApplicationIdentifierPrefix:0') rescue nil)
  appid= pb(tmp,'Entitlements:application-identifier')
  name = pb(tmp,'Name')
  uuid = pb(tmp,'UUID')
  gtl  = pb(tmp,'Entitlements:get-task-allow') == 'true'
  exp  = (Time.parse(pb(tmp,'ExpirationDate') || '') rescue Time.at(0))
  adhoc= system('/usr/libexec/PlistBuddy','-c','Print :ProvisionedDevices', tmp, [:out,:err]=>File::NULL)
  ent  = pb(tmp,'ProvisionsAllDevices') == 'true'
  File.delete(tmp) rescue nil
  return nil unless appid && uuid
  type = gtl ? 'Development' : (ent ? 'Enterprise' : (adhoc ? 'AdHoc' : 'AppStore'))
  bid  = appid.sub(/^#{Regexp.escape(team.to_s)}\./, '')
  { name: name, uuid: uuid, team: team, type: type, bid: bid, exp: exp }
end

list = Dir["#{PROFDIR}/*.mobileprovision"].map { |p| decode(p) }.compact
if list.empty?
  puts "(no profiles installed in #{PROFDIR})"; exit 0
end
list.sort_by { |h| [h[:type], h[:bid], h[:exp]] }.each do |p|
  puts "#{p[:type].ljust(10)}  #{p[:name]}  UUID=#{p[:uuid]}  team=#{p[:team]}  bid=#{p[:bid]}  exp=#{p[:exp].strftime('%Y-%m-%d')}"
end
