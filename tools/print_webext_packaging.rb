#!/usr/bin/env ruby
require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')
t = proj.targets.find { |x| x.name == 'ScreenActionsWebExtension' }
names = %w[background.js manifest.json popup.css popup.html popup.js messages.json]
puts "== Resources"
t.resources_build_phase.files.each do |bf|
  r = bf.file_ref
  puts "  RES #{r.path}" if names.include?(File.basename(r.path.to_s)) || r.path.to_s.include?('/images/') || r.path.to_s.include?('_locales/en')
end
t.copy_files_build_phases.each do |ph|
  puts "== Copy: #{ph.name}  dst=#{ph.dst_path}"
  ph.files.each do |bf|
    r = bf.file_ref
    puts "  CF  #{r.path}"
  end
end
