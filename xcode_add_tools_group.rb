#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'

PROJECT   = 'Screen Actions.xcodeproj'
TOOLS_DIR = 'tools'
FILES     = Dir.glob(File.join(TOOLS_DIR, '*.{rb,zsh,py}'))

abort "✗ #{PROJECT} not found" unless File.exist?(PROJECT)
FileUtils.mkdir_p(TOOLS_DIR)

proj  = Xcodeproj::Project.open(PROJECT)
root  = proj.main_group
tools = root.groups.find { |g| g.display_name == 'tools' }

tools ||= root.new_group('tools', TOOLS_DIR)
tools.set_path(TOOLS_DIR)
tools.set_source_tree('SOURCE_ROOT')

# Remove any stale "red" refs to these files outside the tools group
FILES.each do |abs|
  bn = File.basename(abs)
  proj.files.select { |f| f.display_name == bn && f.parent != tools }.each(&:remove_from_project)
end

# Add missing files to the tools group
FILES.each do |abs|
  bn = File.basename(abs)
  next if tools.files.any? { |f| f.path == bn || f.real_path.to_s == File.expand_path(abs) }
  tools.new_file(abs)
end

proj.save
puts "✓ Created/updated 'tools' group and attached #{FILES.map { |f| File.basename(f) }.join(', ')}"
puts "→ If Xcode prompts that the project changed, click “Revert”."
