#!/usr/bin/env ruby
# Fails the build if host_permissions/matches are blank.
require "json"

path = ARGV[0] || File.join(__dir__, "..", "ScreenActionsWebExtension", "WebRes", "manifest.json")
m = JSON.parse(File.read(path))

def blank_list?(v)
  a = Array(v).map {|s| s.to_s.strip }
  a.empty? || a == [""] || a.all?(&:empty?)
end

errors = []
errors << "host_permissions is blank" if blank_list?(m["host_permissions"])
cs0 = (Array(m["content_scripts"]).first || {})
errors << "content_scripts[0].matches is blank" if blank_list?(cs0["matches"])

if errors.any?
  warn "✗ manifest.json errors:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
else
  puts "✓ manifest keys look good"
end
