#!/usr/bin/env ruby
# Flattens ScreenActionsWebExtension resources into appex root (no WebRes/)
# Requires: gem install xcodeproj
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
WEBRES  = 'ScreenActionsWebExtension/WebRes'

proj = Xcodeproj::Project.open(PROJECT)
ext = proj.targets.find { |t| t.name == 'ScreenActionsWebExtension' } ||
      proj.targets.find { |t| t.name == 'ScreenActionsWebExtension2' }
abort '✗ Web extension target not found' unless ext

def remove_copy_phase(target, name)
  ph = target.copy_files_build_phases.find { |p| p.name == name }
  target.build_phases.delete(ph) if ph
end

def ensure_copy_phase(proj, target, name, subpath, files)
  phase = target.copy_files_build_phases.find { |ph| ph.name == name } ||
          target.new_copy_files_build_phase(name)
  phase.name = name
  if phase.respond_to?(:symbol_dst_subfolder_spec=)
    phase.symbol_dst_subfolder_spec = :resources
  else
    phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:resources]
  end
  phase.dst_path = subpath

  files.each do |path|
    ref = proj.files.find { |f| f.path == path } || proj.new_file(path)
    phase.add_file_reference(ref) unless phase.files_references.include?(ref)
  end

  # Deduplicate
  seen = {}
  phase.files.dup.each do |bf|
    key = bf.file_ref && bf.file_ref.uuid
    if key
      if seen[key] then phase.remove_build_file(bf) else seen[key] = true end
    end
  end
end

# Remove the old WebRes phases if present
%w[Copy WebRes (root) Copy WebRes (_locales/en) Copy WebRes (images)].each do |n|
  remove_copy_phase(ext, n)
end

root_files   = %w[manifest.json background.js popup.html popup.css popup.js].map { |n| "#{WEBRES}/#{n}" }
locale_files = ["#{WEBRES}/_locales/en/messages.json"]
image_files  = Dir["#{WEBRES}/images/*"]

# New phases: copy directly to appex root
ensure_copy_phase(proj, ext, 'Copy ExtRes (root)',        '',                root_files)
ensure_copy_phase(proj, ext, 'Copy ExtRes (_locales/en)', '_locales/en',     locale_files)
ensure_copy_phase(proj, ext, 'Copy ExtRes (images)',      'images',          image_files)

proj.save
puts "✓ Flattened resources into appex root for #{ext.name}"
