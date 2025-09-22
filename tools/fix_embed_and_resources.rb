#!/usr/bin/env ruby
# Ensures: (1) App embeds the Web Extension appex, (2) App depends on it, and
# (3) the Web Extension target has Copy Files phases for WebRes/* (kept under WebRes/…).
# Requires: gem install xcodeproj

require 'xcodeproj'
PROJECT       = 'Screen Actions.xcodeproj'
APP_NAME      = 'Screen Actions'
EXT_CANDIDATES= ['ScreenActionsWebExtension','ScreenActionsWebExtension2']
WEBRES        = 'ScreenActionsWebExtension/WebRes'

proj = Xcodeproj::Project.open(PROJECT)
app = proj.targets.find { |t| t.name == APP_NAME } or abort '✗ App target not found'
ext = EXT_CANDIDATES.map { |n| proj.targets.find { |t| t.name == n } }.compact.first or abort '✗ Web-extension target not found'

# (1) Embed Foundation Extensions phase on app → PlugIns (13)
embed = app.copy_files_build_phases.find { |ph| ph.dst_subfolder_spec.to_s == '13' } || app.new_copy_files_build_phase('Embed Foundation Extensions')
if embed.respond_to?(:symbol_dst_subfolder_spec=)
  embed.symbol_dst_subfolder_spec = :plugins
else
  embed.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:plugins]
end
ext_product = ext.product_reference
embed.add_file_reference(ext_product) unless embed.files_references.include?(ext_product)

# (2) Target dependency
app.add_dependency(ext) unless app.dependencies.any? { |d| d.target == ext }

# (3) Copy WebRes into the appex's Resources under WebRes/*
def ensure_copy_phase(proj, target, name, subpath, files)
  phase = target.copy_files_build_phases.find { |ph| ph.name == name } || target.new_copy_files_build_phase(name)
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
ensure_copy_phase(proj, ext, 'Copy WebRes (_locales/en)',  'WebRes/_locales/en', locale_files)
ensure_copy_phase(proj, ext, 'Copy WebRes (images)',       'WebRes/images',      image_files)

proj.save
puts "✓ Embedded #{ext.name} into #{app.name} and ensured WebRes copy phases."
