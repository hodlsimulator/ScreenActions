require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')

KEEP_TARGETS = ['Screen Actions','ScreenActionsShareExtension','ScreenActionsActionExtension']
EDITORS_BASENAMES = %w[
  EventEditorView.swift
  ReminderEditorView.swift
  ContactEditorView.swift
  ReceiptCSVPreviewView.swift
]
PANEL_BASENAME = 'SAActionPanelView.swift'

def sources_phase_for(t)
  t.respond_to?(:sources_build_phase) ? t.sources_build_phase :
    t.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def remove_from_sources(target, &file_match)
  ph = sources_phase_for(target)
  return 0 unless ph
  removed = 0
  ph.files.dup.each do |bf|
    ref = bf.file_ref
    next unless ref && ref.path
    if file_match.call(File.basename(ref.path))
      bf.remove_from_project
      removed += 1
    end
  end
  removed
end

def dedupe_sources(target)
  ph = sources_phase_for(target)
  return 0 unless ph
  seen = {}
  removed = 0
  ph.files.dup.each do |bf|
    ref = bf.file_ref
    next unless ref
    key = ref.respond_to?(:real_path) && ref.real_path ? ref.real_path.to_s : (ref.path || ref.uuid)
    if seen[key]
      bf.remove_from_project
      removed += 1
    else
      seen[key] = true
    end
  end
  removed
end

puts "Targets:"
proj.targets.each { |t| puts "  - #{t.name}" }

proj.targets.each do |t|
  next if KEEP_TARGETS.include?(t.name)

  # Remove SAActionPanelView.swift and all editor files from non-keep targets
  rem_panel   = remove_from_sources(t) { |bn| bn == PANEL_BASENAME }
  rem_editors = remove_from_sources(t) { |bn| EDITORS_BASENAMES.include?(bn) }
  deduped     = dedupe_sources(t)

  puts "Sanitised #{t.name}: removed panel=#{rem_panel}, editors=#{rem_editors}, deduped=#{deduped}"
end

# Dedupe keep targets too (in case)
proj.targets.select { |t| KEEP_TARGETS.include?(t.name) }.each do |t|
  d = dedupe_sources(t)
  puts "Deduped #{t.name}: removed #{d} duplicates"
end

proj.save
