#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'
require 'set'

PROJECT   = 'Screen Actions.xcodeproj'
TOOLS_DIR = 'tools'
EXTS      = %w[rb zsh py]

abort "✗ #{PROJECT} not found" unless File.exist?(PROJECT)
abort "✗ #{TOOLS_DIR} not found" unless Dir.exist?(TOOLS_DIR)

proj  = Xcodeproj::Project.open(PROJECT)
root  = proj.main_group

# Ensure a proper 'tools' group anchored at SOURCE_ROOT/tools
tools = root.groups.find { |g| g.display_name == 'tools' } || root.new_group('tools', TOOLS_DIR)
tools.set_path(TOOLS_DIR)
tools.set_source_tree('SOURCE_ROOT')

# Build the list of real files on disk
disk_files = Dir.glob(File.join(TOOLS_DIR, "*.{#{EXTS.join(',')}}")).sort
disk_basenames = disk_files.map { |p| File.basename(p) }
disk_abs = disk_files.map { |p| File.expand_path(p) }.to_set

# Remove any stale/duplicate refs (red items, wrong path, abs-path refs, etc.)
(tools.files.dup).each do |f|
  real = begin f.real_path.to_s rescue '' end
  keep = File.exist?(real) && File.dirname(real) == File.expand_path(TOOLS_DIR)
  tools.remove_reference(f) unless keep
end

# Also remove duplicates to these files elsewhere in the project
proj.files.dup.each do |f|
  next unless f != nil
  rp = begin f.real_path.to_s rescue '' end
  next if rp.empty?
  if disk_abs.include?(rp) && f.parent != tools
    f.remove_from_project
  end
end

# Add missing files back RELATIVE to the tools group (so they won't be red)
disk_basenames.each do |bn|
  next if tools.files.any? { |f| f.path == bn }
  tools.new_file(bn) # path is relative to the 'tools' group
end

proj.save
puts "✓ Rebuilt 'tools' group with #{disk_basenames.size} files, paths relative to #{TOOLS_DIR}/"
puts "→ In Xcode, if prompted, click “Revert”."
