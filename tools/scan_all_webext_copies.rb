#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
NAMES   = %w[background.js manifest.json popup.css popup.html popup.js messages.json]

proj = Xcodeproj::Project.open(PROJECT)

proj.targets.each do |t|
  # Only look at app extensions or anything that might be packing the WebExtension
  next unless t.respond_to?(:copy_files_build_phases)

  bad = []
  good = []

  t.copy_files_build_phases.each do |ph|
    dst = (ph.respond_to?(:dst_path) ? ph.dst_path.to_s : '')
    items = []
    ph.files.each do |bf|
      r = bf.file_ref
      next unless r
      p = r.path.to_s
      b = File.basename(p)
      if NAMES.include?(b) || p.include?('/images/') || p.include?('_locales/en')
        items << p
      end
    end
    next if items.empty?

    rec = { target: t.name, phase_name: ph.name, dst: dst, items: items, uuid: ph.uuid }
    if dst.empty? || (!dst.start_with?('WebRes') && !dst.include?('/WebRes'))
      bad << rec
    else
      good << rec
    end
  end

  unless bad.empty? && good.empty?
    puts "== TARGET: #{t.name}"
    good.each do |r|
      puts "  ✅ #{r[:phase_name]}  dst=#{r[:dst]}  (#{r[:items].size} items)"
    end
    bad.each do |r|
      puts "  ❌ #{r[:phase_name]}  dst=#{r[:dst].inspect}  (#{r[:items].size} items)  UUID=#{r[:uuid]}"
      r[:items].each { |p| puts "     • #{p}" }
    end
  end
end
