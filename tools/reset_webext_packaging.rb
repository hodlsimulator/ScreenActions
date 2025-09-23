#!/usr/bin/env ruby
# Rebuilds the ScreenActionsWebExtension packaging so resources land under WebRes/,
# eliminating duplicate "Multiple commands produce ..." errors.

require 'xcodeproj'

PROJECT_PATH = 'Screen Actions.xcodeproj'
TARGET_NAME  = 'ScreenActionsWebExtension'
WEBRES_DIR   = 'ScreenActionsWebExtension/WebRes'

ROOT_FILES   = %w[background.js manifest.json popup.css popup.html popup.js]
LOCALE_FILES = %w[_locales/en/messages.json]
IMAGE_GLOB   = File.join(WEBRES_DIR, 'images', '*')

def ensure_file_ref(proj, path)
  grp = proj.main_group
  ref = grp.find_file_by_path(path)
  return ref if ref
  grp = grp.find_subpath(File.dirname(path), true)
  grp.set_source_tree('<group>')
  proj.new_file(path, grp)
end

def add_copy_phase_with_files(proj, target, name, dst_path, paths)
  phase = target.new_copy_files_build_phase(name)
  begin
    phase.symbol_dst_subfolder_spec = :resources
  rescue
    phase.dst_subfolder_spec = '7' # Resources
  end
  phase.dst_path = dst_path
  paths.each do |p|
    ref = ensure_file_ref(proj, p)
    phase.add_file_reference(ref, true)
  end
  phase
end

proj = Xcodeproj::Project.open(PROJECT_PATH)
target = proj.targets.find { |t| t.name == TARGET_NAME } or abort "Target #{TARGET_NAME.inspect} not found"

# 1) Remove any existing WebRes-related Copy Files phases.
target.copy_files_build_phases.dup.each do |ph|
  if ph.name.to_s =~ /WebRes/i || ph.display_name.to_s =~ /WebRes/i || ph.dst_path.to_s =~ /WebRes/i
    ph.remove_from_project
  end
end

# 2) Scrub stray entries from the Resources phase (root files, locales, images or anything already under WebRes).
paths_to_prune = ROOT_FILES + LOCALE_FILES + Dir.glob(IMAGE_GLOB).map { |p| File.basename(p) }
res_phase = target.resources_build_phase
res_phase.files.to_a.each do |bf|
  ref = bf.file_ref
  next unless ref
  fname = File.basename(ref.path.to_s)
  if ref.path.to_s.include?('/WebRes/') || paths_to_prune.include?(fname)
    bf.remove_from_project
  end
end

# 3) Recreate the three packing phases.
root_paths   = ROOT_FILES.map   { |f| File.join(WEBRES_DIR, f) }
locale_paths = LOCALE_FILES.map { |f| File.join(WEBRES_DIR, f) }
image_paths  = Dir.glob(IMAGE_GLOB).sort

add_copy_phase_with_files(proj, target, 'Pack WebRes – root',    'WebRes',             root_paths)
add_copy_phase_with_files(proj, target, 'Pack WebRes – locales', 'WebRes/_locales/en', locale_paths)
add_copy_phase_with_files(proj, target, 'Pack WebRes – images',  'WebRes/images',      image_paths)

proj.save
puts "✅ Repacked WebRes for target '#{TARGET_NAME}'."
puts "   – Root:    #{root_paths.size} files"
puts "   – Locales: #{locale_paths.size} files"
puts "   – Images:  #{image_paths.size} files"
