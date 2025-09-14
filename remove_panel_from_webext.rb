require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')

TARGET_NAME = 'ScreenActionsWebExtension'
BAN = %w[
  SAActionPanelView.swift
  EventEditorView.swift
  ReminderEditorView.swift
  ContactEditorView.swift
  ReceiptCSVPreviewView.swift
]

def sources_phase_for(t)
  t.respond_to?(:sources_build_phase) ? t.sources_build_phase :
    t.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

t = proj.targets.find { |x| x.name == TARGET_NAME }
abort "Target #{TARGET_NAME} not found" unless t
ph = sources_phase_for(t)
abort "No sources phase for #{TARGET_NAME}" unless ph

removed = 0
ph.files.dup.each do |bf|
  ref = bf.file_ref
  next unless ref && ref.path
  bn = File.basename(ref.path)
  if BAN.include?(bn)
    bf.remove_from_project
    removed += 1
  end
end

# Also de-dupe the phase for safety
seen = {}
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

proj.save
puts "Removed #{removed} entries from #{TARGET_NAME} sources."
