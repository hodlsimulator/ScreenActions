#!/usr/bin/env ruby
# Fix doubled WebRes paths, re-seed canonical refs RELATIVE to WebRes, and
# rebuild Copy Files phases to flatten packaging (manifest at Resources/).

require 'xcodeproj'
require 'set'

PROJECT   = 'Screen Actions.xcodeproj'
WEBRESDIR = 'ScreenActionsWebExtension/WebRes'
ROOT      = %w[manifest.json background.js popup.html popup.css popup.js]
LOCALES   = ['_locales/en/messages.json']

proj = Xcodeproj::Project.open(PROJECT)
ext  = proj.targets.find { |t| t.name == 'ScreenActionsWebExtension' } ||
       proj.targets.find { |t| t.name == 'ScreenActionsWebExtension2' }
abort '✗ web-extension target not found' unless ext

# 1) Nuke all file refs that point anywhere under WebRes (clears dupes)
webres_abs = File.expand_path(WEBRESDIR)
proj.files.dup.each do |f|
  next unless f
  real = (begin f.real_path.to_s rescue '' end)
  next if real.empty?
  f.remove_from_project if real.start_with?(webres_abs + File::SEPARATOR)
end

# 2) Remove old "Copy WebRes" phases
ext.copy_files_build_phases.dup.each { |ph| ext.build_phases.delete(ph) if ph.name&.include?('WebRes') }

# 3) Create a clean group anchored at SOURCE_ROOT/WebRes; add RELATIVE refs
root = proj.main_group
group = root.groups.find { |g| g.display_name == 'WebRes (sources)' } || root.new_group('WebRes (sources)')
group.set_path(WEBRESDIR)
group.set_source_tree('SOURCE_ROOT')

def add_rel(group, rel) group.files.find { |fr| fr.path == rel } || group.new_file(rel) end

root_refs   = ROOT.select   { |n| File.exist?(File.join(WEBRESDIR, n)) }.map { |n| add_rel(group, n) }
locale_refs = LOCALES.select{ |n| File.exist?(File.join(WEBRESDIR, n)) }.map { |n| add_rel(group, n) }

img_refs = []
img_dir  = File.join(WEBRESDIR, 'images')
if Dir.exist?(img_dir)
  Dir[File.join(img_dir, '*')].sort.each { |abs| img_refs << add_rel(group, File.join('images', File.basename(abs))) }
end

# 4) Flatten copy phases → Resources/<file>, Resources/images/<file>, Resources/_locales/en/messages.json
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
    k = bf.file_ref&.uuid
    if k
      seen[k] ? ph.remove_build_file(bf) : seen[k] = true
    end
  end
end

mk_copy(ext, 'Copy WebExtension (root)',        '',                 root_refs)
mk_copy(ext, 'Copy WebExtension (_locales/en)', '_locales/en',      locale_refs)
mk_copy(ext, 'Copy WebExtension (images)',      'images',           img_refs)

# 5) Info.plist: SFSafariWebExtensionManifestPath = manifest.json (flattened)
bs = ext.build_configuration_list.build_configurations.first.build_settings
plist_rel = bs['INFOPLIST_FILE'] or abort '✗ INFOPLIST_FILE not set'
plist_path = File.expand_path(plist_rel)
plist = File.read(plist_path)
plist = plist.gsub(/<key>SFSafariWebExtensionManifestPath<\/key>\s*<string>.*?<\/string>/m,
                   '<key>SFSafariWebExtensionManifestPath</key><string>manifest.json</string>')
File.write(plist_path, plist)

proj.save
puts "✓ WebRes refs flattened and copy phases rebuilt (manifest at Resources/manifest.json)."
