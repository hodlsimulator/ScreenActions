#!/usr/bin/env ruby
# Adds WebRes/content_selection.js to the WebRes "root" Copy Files phase
# without using group.find_subpath (works with FS-synchronised root groups).

require "xcodeproj"

PROJECT = "Screen Actions.xcodeproj"
TARGETS = ["ScreenActionsWebExtension", "ScreenActionsWebExtension2"]
FILE    = "ScreenActionsWebExtension/WebRes/content_selection.js"

proj = Xcodeproj::Project.open(PROJECT)
tgt  = proj.targets.find { |t| TARGETS.include?(t.name) } or abort "✗ Web extension target not found"

# Find or create the WebRes root copy phase
root = tgt.copy_files_build_phases.find { |ph|
  n = ph.name.to_s; n =~ /WebRes/i && n =~ /root/i
}
unless root
  root = tgt.new_copy_files_build_phase("Pack WebRes – root")
  if root.respond_to?(:symbol_dst_subfolder_spec=)
    root.symbol_dst_subfolder_spec = :resources
  else
    root.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  root.dst_path = "WebRes"
end

# Find or create a file reference for the JS (no group traversal)
ref = proj.files.find { |f|
  (f.path == FILE) ||
  (f.path.to_s.end_with?("/content_selection.js")) ||
  (f.respond_to?(:real_path) && f.real_path.to_s.end_with?(FILE))
}
ref ||= proj.new_file(FILE)

# Add to phase if missing
root.add_file_reference(ref, true) unless root.files_references.include?(ref)

# De-dupe any accidental repeats
seen = {}
root.files.dup.each do |bf|
  id = bf.file_ref&.uuid
  next unless id
  if seen[id] then root.remove_build_file(bf) else seen[id] = true end
end

proj.save
puts "✓ Added #{FILE} to '#{root.name}' (dst=#{root.dst_path})"
