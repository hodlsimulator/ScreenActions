#!/usr/bin/env ruby
# Re-seed the WebRes file references in the Xcode project so copy phases
# definitely pull the files from ScreenActionsWebExtension/WebRes (no dups).

require 'xcodeproj'
require 'set'

PROJECT = 'Screen Actions.xcodeproj'
WEBRES  = 'ScreenActionsWebExtension/WebRes'
FILES   = %w[
  manifest.json
  background.js
  popup.html
  popup.css
  popup.js
  _locales/en/messages.json
]

proj = Xcodeproj::Project.open(PROJECT)

ext = proj.targets.find { |t| t.name == 'ScreenActionsWebExtension' } ||
      proj.targets.find { |t| t.name == 'ScreenActionsWebExtension2' }
abort '✗ Web-extension target not found' unless ext

# 1) Remove any existing refs to these WebRes files anywhere in the project.
wanted = FILES.map { |n| File.join(WEBRES, n) }.to_set
proj.files.dup.each do |f|
  next unless f && f.path && wanted.include?(f.path)
  f.remove_from_project
end

# 2) Create a clean group and add canonical refs (relative to SOURCE_ROOT).
root = proj.main_group
group = root.groups.find { |g| g.display_name == 'WebRes (sources)' } ||
        root.new_group('WebRes (sources)', WEBRES)
group.set_path(WEBRES)
group.set_source_tree('SOURCE_ROOT')

FILES.each do |name|
  path = File.join(WEBRES, name)
  next unless File.exist?(path)
  group.new_file(path)
end

proj.save
puts "✓ Reseeded WebRes references under 'WebRes (sources)'."
