#!/usr/bin/env ruby
# Retargets ALL WebExtension Copy Files phases to pack under WebRes/,
# deletes duplicates, and removes any stray entries from the Resources phase.

require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TARGET  = 'ScreenActionsWebExtension'

ROOT_FILES = %w[background.js manifest.json popup.css popup.html popup.js]

def ref_kind(ref)
  p = ref.path.to_s
  b = File.basename(p)
  return :images  if p.include?('/images/') || File.dirname(p).split('/').include?('images') || b =~ /^icon-.*\.png$/ || b == 'toolbar-icon.svg'
  return :locales if p.include?('_locales/en') || b == 'messages.json'
  return :root    if ROOT_FILES.include?(b)
  nil
end

proj = Xcodeproj::Project.open(PROJECT)
t = proj.targets.find { |x| x.name == TARGET } or abort "❌ Target not found: #{TARGET}"

# 1) Strip stray entries from "Copy Bundle Resources"
t.resources_build_phase.files.to_a.each do |bf|
  k = ref_kind(bf.file_ref)
  bf.remove_from_project if k
end

# 2) Collect refs from ALL existing WebRes-related copy phases, then remove them
root_refs, loc_refs, img_refs = [], [], []
to_delete = []

t.copy_files_build_phases.each do |ph|
  touched = false
  ph.files.to_a.each do |bf|
    k = ref_kind(bf.file_ref)
    next unless k
    touched = true
    case k
    when :root    then root_refs << bf.file_ref
    when :locales then loc_refs  << bf.file_ref
    when :images  then img_refs  << bf.file_ref
    end
  end
  to_delete << ph if touched || ph.name.to_s =~ /Copy WebExtension|Copy Root|Pack WebRes/i
end

root_refs.uniq!; loc_refs.uniq!; img_refs.uniq!
to_delete.each { |ph| ph.remove_from_project }

# 3) Create exactly three clean packers
def new_phase(t, name, dst)
  ph = t.new_copy_files_build_phase(name)
  if ph.respond_to?(:symbol_dst_subfolder_spec)
    ph.symbol_dst_subfolder_spec = :resources
  else
    ph.dst_subfolder_spec = '7' # Resources
  end
  ph.dst_path = dst
  ph
end

ph_root = new_phase(t, 'Pack WebRes – root',    'WebRes')
ph_loc  = new_phase(t, 'Pack WebRes – locales', 'WebRes/_locales/en')
ph_img  = new_phase(t, 'Pack WebRes – images',  'WebRes/images')

root_refs.each { |r| ph_root.add_file_reference(r, true) }
loc_refs.each  { |r| ph_loc.add_file_reference(r,  true) }
img_refs.each  { |r| ph_img.add_file_reference(r,  true) }

proj.save
puts "✅ Retargeted. root=#{root_refs.size} locales=#{loc_refs.size} images=#{img_refs.size}"
