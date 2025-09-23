#!/usr/bin/env ruby
# Remove any root-level background.js/manifest.json/popup.* copies from *all* targets.
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
NAMES   = %w[background.js manifest.json popup.css popup.html popup.js]

proj = Xcodeproj::Project.open(PROJECT)

proj.targets.each do |t|
  # Remove from Copy Bundle Resources
  if t.respond_to?(:resources_build_phase)
    t.resources_build_phase.files.to_a.each do |bf|
      ref = bf.file_ref or next
      base = File.basename(ref.path.to_s)
      path = ref.path.to_s
      if NAMES.include?(base) && !path.include?('/WebRes/')
        bf.remove_from_project
      end
    end
  end

  # Remove from Copy Files phases that don't target WebRes
  if t.respond_to?(:copy_files_build_phases)
    t.copy_files_build_phases.dup.each do |ph|
      dst = (ph.respond_to?(:dst_path) ? ph.dst_path.to_s : '')
      to_webres = dst.start_with?('WebRes')
      ph.files.to_a.each do |bf|
        ref = bf.file_ref or next
        base = File.basename(ref.path.to_s)
        path = ref.path.to_s
        if NAMES.include?(base) && (!to_webres || !path.include?('/WebRes/'))
          bf.remove_from_project
        end
      end
      ph.remove_from_project if ph.files.empty? && !to_webres
    end
  end
end

proj.save
puts "✅ Removed root-level duplicates of #{NAMES.join(', ')}"
