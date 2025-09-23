#!/usr/bin/env ruby
# Fix doubled WebRes paths and duplicated refs. Re-seed canonical refs RELATIVE
# to ScreenActionsWebExtension/WebRes and rebuild the three Copy Files phases.

require 'xcodeproj'
require 'set'

PROJECT   = 'Screen Actions.xcodeproj'
WEBRESDIR = 'ScreenActionsWebExtension/WebRes'
ROOT_FILES   = %w[manifest.json background.js popup.html popup.css popup.js]
LOCALE_FILES = ['_locales/en/messages.json']

proj = Xcodeproj::Project.open(PROJECT)

ext = proj.targets.find { |t| t.name == 'ScreenActionsWebExtension' } ||
      proj.targets.find { |t| t.name == 'ScreenActionsWebExtension2' }
abort '✗ web-extension target not found' unless ext

# 1) Remove any existing file refs that point inside WebRes (nukes dupes)
webres_abs = File.expand_path(WEBRESDIR)
proj.files.dup.each do |f|
  next unless f
  begin real = f.real_path.to_s rescue '' end
  next if real.empty?
  f.remove_from_project if real.start_with?(webres_abs + File::SEPARATOR)
end

# 2) Remove old "Copy WebRes" phases
ext.copy_files_build_phases.dup.each do |ph|
  ext.build_phases.delete(ph) if ph.name&.include?('Copy WebRes')
end

# 3) Create a clean group anchored at SOURCE_ROOT/WebRes and add RELATIVE refs
root = proj.main_group
group = root.groups.find { |g| g.display_name == 'WebRes (sources)' } || root.new_group('WebRes (sources)')
group.set_path(WEBRESDIR)
group.set_source_tree('SOURCE_ROOT')

def add_rel(group, rel)
  group.files.find { |fr| fr.path == rel } || group.new_file(rel)  # 'rel' relative to group's path
end

root_refs   = ROOT_FILES.select { |n| File.exist?(File.join(WEBRESDIR, n)) }
                        .map    { |n| add_rel(group, n) }

locale_refs = LOCALE_FILES.select { |n| File.exist?(File.join(WEBRESDIR, n)) }
                          .map    { |n| add_rel(group, n) }

image_refs = []
img_dir = File.join(WEBRESDIR, 'images')
if Dir.exist?(img_dir)
  Dir[File.join(img_dir, '*')].sort.each do |abs|
    image_refs << add_rel(group, File.join('images', File.basename(abs)))
  end
end

# 4) Rebuild the three Copy Files phases → Resources/WebRes/(…)
def mk_copy(ext, name, dst_path, refs)
  ph = ext.new_copy_files_build_phase(name)
  if ph.respond_to?(:symbol_dst_subfolder_spec=)
    ph.symbol_dst_subfolder_spec = :resources
  else
    ph.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  ph.dst_path = dst_path
  refs.each { |r| ph.add_file_reference(r) unless ph.files_references.include?(r) }
  # Deduplicate build files
  seen = {}
  ph.files.dup.each do |bf|
    key = bf.file_ref&.uuid
    if key
      seen[key] ? ph.remove_build_file(bf) : seen[key] = true
    end
  end
end

mk_copy(ext, 'Copy WebRes (root)',        'WebRes',             root_refs)
mk_copy(ext, 'Copy WebRes (_locales/en)', 'WebRes/_locales/en', locale_refs)
mk_copy(ext, 'Copy WebRes (images)',      'WebRes/images',      image_refs)

proj.save
puts "✓ Fixed WebRes refs and rebuilt copy phases."
