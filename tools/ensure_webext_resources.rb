#!/usr/bin/env ruby
# Ensures WebRes is copied into the extension's Resources with the right subpaths.
# Requires: gem install xcodeproj
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
WEBRES  = 'ScreenActionsWebExtension/WebRes'

proj = Xcodeproj::Project.open(PROJECT)

ext = proj.targets.find { |t| t.name == 'ScreenActionsWebExtension' } ||
      proj.targets.find { |t| t.name == 'ScreenActionsWebExtension2' }
abort '✗ Web extension target not found' unless ext

def ensure_copy_phase(proj, target, name, subpath, files)
  phase = target.copy_files_build_phases.find { |ph| ph.name == name } ||
          target.new_copy_files_build_phase(name)
  phase.name = name
  if phase.respond_to?(:symbol_dst_subfolder_spec=)
    phase.symbol_dst_subfolder_spec = :resources  # Destination = Resources
  else
    phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  phase.dst_path = subpath

  files.each do |path|
    ref = proj.files.find { |f| f.path == path } || proj.new_file(path)
    phase.add_file_reference(ref) unless phase.files_references.include?(ref)
  end

  # Deduplicate any accidental repeats.
  seen = {}
  phase.files.dup.each do |bf|
    key = bf.file_ref && bf.file_ref.uuid
    if key
      if seen[key]
        phase.remove_build_file(bf)
      else
        seen[key] = true
      end
    end
  end
end

root_files   = %w[manifest.json background.js popup.html popup.css popup.js].map { |n| "#{WEBRES}/#{n}" }
locale_files = ["#{WEBRES}/_locales/en/messages.json"]
image_files  = Dir["#{WEBRES}/images/*"]

ensure_copy_phase(proj, ext, 'Copy WebRes (root)',        'WebRes',             root_files)
ensure_copy_phase(proj, ext, 'Copy WebRes (_locales/en)', 'WebRes/_locales/en', locale_files)
ensure_copy_phase(proj, ext, 'Copy WebRes (images)',      'WebRes/images',      image_files)

proj.save
puts "✓ Copy phases updated for #{ext.name}"
