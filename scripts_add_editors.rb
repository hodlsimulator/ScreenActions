require 'xcodeproj'
proj_path = 'Screen Actions.xcodeproj'
project   = Xcodeproj::Project.open(proj_path)

def find_group(node, name)
  return node if node.respond_to?(:display_name) && node.display_name == name
  return nil unless node.respond_to?(:children)
  node.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      found = find_group(child, name)
      return found if found
    end
  end
  nil
end

app_t    = project.targets.find { |t| t.name == 'Screen Actions' }
share_t  = project.targets.find { |t| t.name == 'ScreenActionsShareExtension' }
action_t = project.targets.find { |t| t.name == 'ScreenActionsActionExtension' }
targets  = [app_t, share_t, action_t].compact
raise "Targets not found" if targets.empty?

root_group           = project.main_group
screen_actions_group = find_group(root_group, 'Screen Actions') || root_group
editors_group        = find_group(screen_actions_group, 'Editors') || screen_actions_group.new_group('Editors', 'Editors')

# Remove broken/duplicate refs (…' 2.swift', *_old.swift, missing on disk)
project.files.dup.each do |f|
  next unless f.path
  bad = f.path.end_with?(' 2.swift') || f.path =~ /_old\.swift(\.txt)?$/ || !f.real_path.exist?
  if bad
    project.targets.each do |t|
      t.build_phases.each do |ph|
        ph.files.each { |bf| bf.remove_from_project if bf.file_ref == f }
      end
    end
    f.remove_from_project
  end
end

def ensure_file_ref(project, group, rel_path)
  project.files.find { |f| f.path == rel_path } || group.new_file(rel_path)
end

def sources_phase_for(target)
  return target.sources_build_phase if target.respond_to?(:sources_build_phase)
  return target.source_build_phase  if target.respond_to?(:source_build_phase)
  # Fallback search
  target.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def remove_from_resources_if_present(target, file_ref)
  res = target.respond_to?(:resources_build_phase) ? target.resources_build_phase : nil
  return unless res
  res.files.each { |bf| bf.remove_from_project if bf.file_ref == file_ref }
end

def ensure_in_sources(target, file_ref)
  ph = sources_phase_for(target)
  raise "No Sources build phase for #{target.name}" unless ph
  unless ph.files_references.include?(file_ref)
    ph.add_file_reference(file_ref)
  end
  remove_from_resources_if_present(target, file_ref)
end

# Editors we want
editor_files = %w[
  Editors/EventEditorView.swift
  Editors/ReminderEditorView.swift
  Editors/ContactEditorView.swift
  Editors/ReceiptCSVPreviewView.swift
]
editor_refs = editor_files.map { |p| ensure_file_ref(project, editors_group, p) }
editor_refs.each { |ref| targets.each { |t| ensure_in_sources(t, ref) } }

# Make sure extensions compile the Core helpers they depend on
core_files = %w[
  Screen Actions/Core/DataDetectors.swift
  Screen Actions/Core/CalendarService.swift
  Screen Actions/Core/RemindersService.swift
  Screen Actions/Core/ContactsService.swift
  Screen Actions/Core/CSVExporter.swift
  Screen Actions/Core/AppStorageService.swift
]
core_files.each do |p|
  ref = project.files.find { |f| f.path == p } || screen_actions_group.new_file(p)
  [share_t, action_t].each { |t| ensure_in_sources(t, ref) }
end

project.save
puts "✔ Updated project: editors wired to all targets; stale refs removed."
