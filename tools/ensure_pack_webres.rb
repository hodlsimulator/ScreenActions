#!/usr/bin/env ruby
# Ensures the ScreenActionsWebExtension packs all WebRes files to the right places.

require 'xcodeproj'

PROJECT     = 'Screen Actions.xcodeproj'
TARGET_NAME = 'ScreenActionsWebExtension'

def ensure_phase(target, name, dst)
  ph = target.copy_files_build_phases.find { |p| p.name == name }
  unless ph
    ph = target.new_copy_files_build_phase(name)
    if ph.respond_to?(:symbol_dst_subfolder_spec)
      ph.symbol_dst_subfolder_spec = :resources
    else
      ph.dst_subfolder_spec = '7' # Resources
    end
  end
  ph.dst_path = dst
  ph.files.to_a.each { |bf| bf.remove_from_project } # clear
  ph
end

def find_or_add_ref(proj, path)
  # Try exact, then without the target prefix, then by basename under /WebRes/
  ref = proj.files.find { |f| f.path == path } ||
        proj.files.find { |f| f.path == path.sub('ScreenActionsWebExtension/', '') } ||
        proj.files.find { |f| File.basename(f.path.to_s) == File.basename(path) && f.path.to_s.include?('/WebRes/') }
  return ref if ref
  proj.new_file(path) # add to main group if missing
end

proj   = Xcodeproj::Project.open(PROJECT)
target = proj.targets.find { |t| t.name == TARGET_NAME } or abort "❌ Target #{TARGET_NAME} not found"

root_files   = %w[background.js manifest.json popup.css popup.html popup.js]
                .map { |f| "ScreenActionsWebExtension/WebRes/#{f}" }
locale_files = ["ScreenActionsWebExtension/WebRes/_locales/en/messages.json"]
image_files  = Dir.glob("ScreenActionsWebExtension/WebRes/images/*").sort

ph_root = ensure_phase(target, 'Pack WebRes – root',    'WebRes')
ph_loc  = ensure_phase(target, 'Pack WebRes – locales', 'WebRes/_locales/en')
ph_img  = ensure_phase(target, 'Pack WebRes – images',  'WebRes/images')

root_files.each   { |p| ph_root.add_file_reference(find_or_add_ref(proj, p), true) }
locale_files.each { |p| ph_loc.add_file_reference( find_or_add_ref(proj, p), true) }
image_files.each  { |p| ph_img.add_file_reference( find_or_add_ref(proj, p), true) }

proj.save
puts "✅ Ensured WebRes packers. Root=#{root_files.size} Locales=#{locale_files.size} Images=#{image_files.size}"
