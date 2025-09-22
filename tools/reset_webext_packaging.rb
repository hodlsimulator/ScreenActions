#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TARGETS = ['ScreenActionsWebExtension', 'ScreenActionsWebExtension2']
WEBRES  = 'ScreenActionsWebExtension/WebRes'

ROOT_FILES   = %w[manifest.json background.js popup.html popup.css popup.js].map { |n| File.join(WEBRES, n) }
LOCALE_FILES = [File.join(WEBRES, '_locales/en/messages.json')]
IMAGE_FILES  = Dir[File.join(WEBRES, 'images/*')]
ALL_FILES    = ROOT_FILES + LOCALE_FILES + IMAGE_FILES

proj = Xcodeproj::Project.open(PROJECT)
ext  = proj.targets.find { |t| TARGETS.include?(t.name) } or abort('✗ Web extension target not found')

# 1) Remove references to our web files from the Resources build phase
res = ext.resources_build_phase
res.files.dup.each do |bf|
  p = bf.file_ref && bf.file_ref.path
  res.remove_build_file(bf) if p && ALL_FILES.include?(p)
end

# 2) Remove any existing Copy Files phases we previously added
ext.copy_files_build_phases.dup.each do |ph|
  if ph.name =~ /Copy (WebRes|ExtRes)/i
    ext.build_phases.delete(ph)
  end
end

# 3) Helper to add a copy phase
def add_copy_phase(proj, target, name, subpath, files)
  ph = target.new_copy_files_build_phase(name)
  if ph.respond_to?(:symbol_dst_subfolder_spec=)
    ph.symbol_dst_subfolder_spec = :resources
  else
    ph.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  ph.dst_path = subpath
  files.each do |path|
    ref = proj.files.find { |f| f.path == path } || proj.new_file(path)
    ph.add_file_reference(ref)
  end
end

# 4) Create the canonical three phases
add_copy_phase(proj, ext, 'Copy WebRes (root)',        'WebRes',             ROOT_FILES)
add_copy_phase(proj, ext, 'Copy WebRes (_locales/en)', 'WebRes/_locales/en', LOCALE_FILES)
add_copy_phase(proj, ext, 'Copy WebRes (images)',      'WebRes/images',      IMAGE_FILES)

proj.save
puts "✓ Reset packaging for #{ext.name}"
