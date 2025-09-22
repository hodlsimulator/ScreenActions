#!/usr/bin/env ruby
require 'open3'
require 'json'
require 'time'

def decode(path)
  xml, st1 = Open3.capture2('/usr/bin/security', 'cms', '-D', '-i', path)
  return nil unless st1.success?
  json, st2 = Open3.capture3('plutil', '-convert', 'json', '-o', '-', '-', stdin_data: xml)
  return nil unless st2.success?
  JSON.parse(json)
rescue
  nil
end

def type_of(p)
  ent = p['Entitlements'] || {}
  return 'Development' if ent['get-task-allow']
  return 'Enterprise'  if p['ProvisionsAllDevices']
  return 'AdHoc'       if p['ProvisionedDevices'].is_a?(Array)
  'AppStore'
end

if ARGV.empty?
  warn "Usage: #{$0} /path/to/*.mobileprovision ..."
  exit 1
end

ARGV.each do |f|
  p = decode(f)
  if p.nil?
    puts "?? #{f}  (unreadable)"
    next
  end
  ent = p['Entitlements'] || {}
  team = (p['TeamIdentifier'] || p['ApplicationIdentifierPrefix'] || ['']).first
  appid = ent['application-identifier']
  uuid  = p['UUID']
  name  = p['Name']
  exp   = (Time.parse(p['ExpirationDate'].to_s) rescue nil)&.strftime('%Y-%m-%d') || '?'
  t     = type_of(p)
  bid   = appid.to_s.sub(/^#{Regexp.escape(team)}\./, '')
  puts "#{t.ljust(10)}  #{name}  UUID=#{uuid}  team=#{team}  bundleID=#{bid}  exp=#{exp}"
end
