#!/usr/bin/env ruby
# Adds WebRes/content_selection.js to the WebRes "root" Copy Files phase for the Safari Web Extension.

require "xcodeproj"

PROJECT = "Screen Actions.xcodeproj"
WEBEXT_TARGETS = ["ScreenActionsWebExtension", "ScreenActionsWebExtension2"]
FILE_PATH = "ScreenActionsWebExtension/WebRes/content_selection.js"

proj = Xcodeproj::Project.open(PROJECT)
ext  = proj.targets.find { |t| WEBEXT_TARGETS.include?(t.name) } or abort "✗ Web extension target not found"

# Find a WebRes root copy phase (support both dash/en-dash).
root_phase = ext.copy_files_build_phases.find { |ph|
  n = ph.name.to_s
  n.match?(/WebRes/i) && n.match?(/root/i)
}
unless root_phase
  root_phase = ext.new_copy_files_build_phase("Pack WebRes – root")
  if root_phase.respond_to?(:symbol_dst_subfolder_spec=)
    root_phase.symbol_dst_subfolder_spec = :resources
  else
    root_phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  root_phase.dst_path = "WebRes"
end

# Ensure file ref exists and add it
parent = proj.main_group.find_subpath("ScreenActionsWebExtension/WebRes", true)
parent.set_source_tree("")
ref = parent.files.find { |f| f.path == File.basename(FILE_PATH) } || proj.new_file(FILE_PATH, parent)
root_phase.add_file_reference(ref, true) unless root_phase.files_references.include?(ref)

# Dedupe
seen = {}
root_phase.files.dup.each do |bf|
  key = bf.file_ref&.uuid
  if key
    if seen[key] then root_phase.remove_build_file(bf) else seen[key] = true end
  end
end

proj.save
puts "✓ Added #{FILE_PATH} to '#{root_phase.name}' (dst=#{root_phase.dst_path})"
