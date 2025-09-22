#!/usr/bin/env ruby
require 'xcodeproj'
PROJECT='Screen Actions.xcodeproj'
WEBRES='ScreenActionsWebExtension/WebRes'
TARGETS=['ScreenActionsWebExtension','ScreenActionsWebExtension2']

proj = Xcodeproj::Project.open(PROJECT)
ext  = proj.targets.find { |t| TARGETS.include?(t.name) } or abort '✗ web-ext target not found'

# Remove any old phase with the same name
ext.copy_files_build_phases.dup.each { |ph| ext.build_phases.delete(ph) if ph.name == 'Copy Root (images)' }

# New phase: copy WebRes/images/* → appex root/images
ph = ext.new_copy_files_build_phase('Copy Root (images)')
if ph.respond_to?(:symbol_dst_subfolder_spec=)
  ph.symbol_dst_subfolder_spec = :resources
else
  ph.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
end
ph.dst_path = 'images'
Dir["#{WEBRES}/images/*"].each do |path|
  ref = proj.files.find { |f| f.path == path } || proj.new_file(path)
  ph.add_file_reference(ref)
end

proj.save
puts "✓ Added root images phase"
