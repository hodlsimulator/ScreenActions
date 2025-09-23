#!/usr/bin/env ruby
# Purge duplicate root copies of WebRes files and rebuild clean WebRes packers
# for target "ScreenActionsWebExtension" without using find_subpath.

require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TARGET  = 'ScreenActionsWebExtension'
WEBRES  = 'ScreenActionsWebExtension/WebRes'

ROOT_FILES   = %w[background.js manifest.json popup.css popup.html popup.js]
LOCALE_FILES = %w[_locales/en/messages.json]
IMAGES_DIR   = File.join(WEBRES, 'images')

proj = Xcodeproj::Project.open(PROJECT)
target = proj.targets.find { |t| t.name == TARGET } or abort("❌ Target #{TARGET.inspect} not found")

# ---- helpers ---------------------------------------------------------------

def bfs_groups(root_group)
  out, q = [], [root_group]
  until q.empty?
    g = q.shift
    out << g
    g.children.each { |c| q << c if c.respond_to?(:children) } # groups only
  end
  out
end

def find_group_named(proj, name)
  bfs_groups(proj.main_group).find { |g|
    [g.display_name, g.name, g.path].compact.any? { |s| s.to_s == name }
  }
end

def ensure_group_chain(proj, rel_path)
  parts = rel_path.split('/').reject(&:empty?)
  g = proj.main_group
  parts.each do |part|
    child = g.children.find { |c| c.respond_to?(:children) && (c.display_name == part || c.name == part || c.path == part) }
    unless child
      child = proj.new_group(part, part, :group)
      g << child
    end
    g = child
  end
  g
end

def ensure_file_ref_in_group(proj, group, rel_path)
  ref = proj.files.find { |f| f.path == rel_path }
  return ref if ref
  proj.new_file(rel_path, group)
end

def remove_from_resources!(target, matcher)
  removed = 0
  target.resources_build_phase.files.to_a.each do |bf|
    ref = bf.file_ref
    next unless ref && matcher.call(ref)
    bf.remove_from_project
    removed += 1
  end
  removed
end

def remove_from_non_webres_copy_phases!(target, matcher)
  removed = 0
  target.copy_files_build_phases.dup.each do |ph|
    dst = (ph.respond_to?(:dst_path) ? ph.dst_path.to_s : '')
    to_webres = dst.downcase.include?('webres')
    ph.files.to_a.each do |bf|
      ref = bf.file_ref
      next unless ref && matcher.call(ref)
      unless to_webres
        bf.remove_from_project
        removed += 1
      end
    end
    ph.remove_from_project if ph.files.empty? && !to_webres
  end
  removed
end

def ensure_copy_phase(proj, target, name, dst_path)
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
  # clear
  phase.files.to_a.each { |bf| bf.remove_from_project }
  phase
end

# ---- 1) Purge any root-level copies & stray WebRes refs from Resources -----

image_names = Dir.glob(File.join(IMAGES_DIR, '*')).map { |p| File.basename(p) }
names_to_scrub = ROOT_FILES + ['messages.json'] + image_names

matcher = lambda { |ref|
  p = ref.path.to_s
  n = File.basename(p)
  n && names_to_scrub.include?(n) || p.include?('/WebRes/')
}

removed_res  = remove_from_resources!(target, matcher)
removed_copy = remove_from_non_webres_copy_phases!(target, matcher)

# ---- 2) Recreate the three WebRes packing phases ---------------------------

ext_group    = find_group_named(proj, 'ScreenActionsWebExtension') || ensure_group_chain(proj, 'ScreenActionsWebExtension')
webres_group = find_group_named(proj, 'WebRes') || ensure_group_chain(proj, 'ScreenActionsWebExtension/WebRes')

root_paths   = ROOT_FILES.map   { |f| File.join(WEBRES, f) }
locale_paths = LOCALE_FILES.map { |f| File.join(WEBRES, f) }
image_paths  = Dir.glob(File.join(IMAGES_DIR, '*')).sort

root_phase   = ensure_copy_phase(proj, target, 'Pack WebRes – root',    'WebRes')
locale_phase = ensure_copy_phase(proj, target, 'Pack WebRes – locales', 'WebRes/_locales/en')
image_phase  = ensure_copy_phase(proj, target, 'Pack WebRes – images',  'WebRes/images')

(root_paths + locale_paths + image_paths).each do |rel|
  parent = rel.include?('/WebRes/') ? webres_group : ext_group
  ensure_file_ref_in_group(proj, parent, rel)
end

[root_phase, root_paths].transpose rescue nil
root_paths.each   { |rel| root_phase.add_file_reference(   ensure_file_ref_in_group(proj, webres_group, rel), true) }
locale_paths.each { |rel| locale_phase.add_file_reference( ensure_file_ref_in_group(proj, webres_group, rel), true) }
image_paths.each  { |rel| image_phase.add_file_reference(  ensure_file_ref_in_group(proj, webres_group, rel), true) }

proj.save
puts "✅ Purged (Resources: #{removed_res}, CopyPhases: #{removed_copy}). Rebuilt WebRes packers."
