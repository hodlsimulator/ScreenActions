#!/usr/bin/env ruby
# Purge any root-level copies of WebRes files from ScreenActionsWebExtension and recreate clean WebRes packers.

require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TARGET  = 'ScreenActionsWebExtension'
WEBRES  = 'ScreenActionsWebExtension/WebRes'

ROOT_FILES   = %w[background.js manifest.json popup.css popup.html popup.js]
LOCALE_FILES = %w[_locales/en/messages.json]
IMAGES_DIR   = File.join(WEBRES, 'images')

def ensure_ref(proj, rel_path)
  ref = proj.main_group.find_file_by_path(rel_path)
  return ref if ref
  grp = proj.main_group.find_subpath(File.dirname(rel_path), true)
  grp.set_source_tree('<group>')
  proj.new_file(rel_path, grp)
end

def clear_from_resources_phase!(target, names)
  removed = 0
  phase = target.resources_build_phase
  phase.files.to_a.each do |bf|
    ref = bf.file_ref
    next unless ref
    name = File.basename(ref.path.to_s)
    path = ref.path.to_s
    if names.include?(name) || path.include?('/WebRes/') || path.start_with?('WebRes') || path.include?('ScreenActionsWebExtension/WebRes')
      bf.remove_from_project
      removed += 1
    end
  end
  removed
end

def clear_from_copy_files_phases!(target, names)
  removed = 0
  target.copy_files_build_phases.dup.each do |ph|
    dst = (ph.respond_to?(:dst_path) ? ph.dst_path.to_s : '')
    to_webres = dst.include?('WebRes')
    ph.files.to_a.each do |bf|
      ref = bf.file_ref
      next unless ref
      name = File.basename(ref.path.to_s)
      path = ref.path.to_s
      if names.include?(name) || path.include?('/WebRes/') || path.start_with?('WebRes') || path.include?('ScreenActionsWebExtension/WebRes')
        # Only purge from phases that *don’t* target WebRes
        if !to_webres
          bf.remove_from_project
          removed += 1
        end
      end
    end
    # Drop empty, non-WebRes copy phases entirely
    if ph.files.empty? && !to_webres
      ph.remove_from_project
    end
  end
  removed
end

def ensure_copy_phase!(proj, target, name, dst_path, rel_paths)
  phase = target.copy_files_build_phases.find { |p| p.name == name }
  unless phase
    phase = target.new_copy_files_build_phase(name)
    if phase.respond_to?(:symbol_dst_subfolder_spec)
      phase.symbol_dst_subfolder_spec = :resources
    else
      phase.dst_subfolder_spec = '7' # Resources
    end
  end
  phase.dst_path = dst_path
  # reset contents
  phase.files.to_a.each { |bf| bf.remove_from_project }
  rel_paths.each do |p|
    ref = ensure_ref(proj, p)
    phase.add_file_reference(ref, true)
  end
end

proj = Xcodeproj::Project.open(PROJECT)
target = proj.targets.find { |t| t.name == TARGET } or abort("❌ Target #{TARGET.inspect} not found")

# 1) Purge from Resources build phase
names = ROOT_FILES + ['messages.json'] + Dir.glob(File.join(IMAGES_DIR, '*')).map { |p| File.basename(p) }
pruned1 = clear_from_resources_phase!(target, names)

# 2) Purge from *any* Copy Files phases that don’t point at WebRes
pruned2 = clear_from_copy_files_phases!(target, names)

# 3) Recreate the three WebRes packers
root_paths   = ROOT_FILES.map   { |f| File.join(WEBRES, f) }
locale_paths = LOCALE_FILES.map { |f| File.join(WEBRES, f) }
image_paths  = Dir.glob(File.join(IMAGES_DIR, '*')).sort

ensure_copy_phase!(proj, target, 'Pack WebRes – root',    'WebRes',             root_paths)
ensure_copy_phase!(proj, target, 'Pack WebRes – locales', 'WebRes/_locales/en', locale_paths)
ensure_copy_phase!(proj, target, 'Pack WebRes – images',  'WebRes/images',      image_paths)

proj.save
puts "✅ Purged duplicates (resources: #{pruned1}, copy phases: #{pruned2}) and rebuilt WebRes packers."
