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

def sources_phase_for(target)
  target.respond_to?(:sources_build_phase) ? target.sources_build_phase :
  target.respond_to?(:source_build_phase)  ? target.source_build_phase  :
  target.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def ensure_group_at_root(project, name, path)
  g = find_group(project.main_group, name)
  unless g
    g = project.main_group.new_group(name, path)
  else
    g.path = path
  end
  # Make it relative to SOURCE_ROOT
  g.set_source_tree('SOURCE_ROOT')
  g
end

def remove_build_files_pointing_to(project, file_refs)
  project.targets.each do |t|
    t.build_phases.each do |ph|
      ph.files.dup.each do |bf|
        if file_refs.include?(bf.file_ref)
          bf.remove_from_project
        end
      end
    end
  end
end

def remove_file_refs_by_basenames(project, basenames)
  to_remove = project.files.select { |f| f.path && basenames.include?(File.basename(f.path)) }
  remove_build_files_pointing_to(project, to_remove)
  to_remove.each(&:remove_from_project)
end

def ensure_file_ref(project, group, basename)
  # Prefer a ref whose basename matches and lives under the Editors group
  existing = project.files.find { |f| f.path && File.basename(f.path) == basename && f.group == group }
  return existing if existing
  ref = group.new_file(basename)
  ref.set_source_tree('<group>') # relative to group path ("Editors")
  ref
end

def ensure_in_sources(target, file_ref)
  ph = sources_phase_for(target)
  raise "No Sources phase for #{target.name}" unless ph
  ph.add_file_reference(file_ref) unless ph.files_references.include?(file_ref)
  # Make sure it isn't accidentally in Resources
  if target.respond_to?(:resources_build_phase) && target.resources_build_phase
    target.resources_build_phase.files.dup.each do |bf|
      bf.remove_from_project if bf.file_ref == file_ref
    end
  end
end

# Targets
app_t    = project.targets.find { |t| t.name == 'Screen Actions' }
share_t  = project.targets.find { |t| t.name == 'ScreenActionsShareExtension' }
action_t = project.targets.find { |t| t.name == 'ScreenActionsActionExtension' }
targets  = [app_t, share_t, action_t].compact
raise 'Targets not found' if targets.empty?

# 1) Create/fix a root-level "Editors" group that points at repo-root Editors/
editors_group = ensure_group_at_root(project, 'Editors', 'Editors')

# 2) Remove any stale/duplicate refs to editor files (wrong paths, " 2.swift", etc.)
editor_basenames = %w[
  EventEditorView.swift
  ReminderEditorView.swift
  ContactEditorView.swift
  ReceiptCSVPreviewView.swift
  ContactEditorView\ 2.swift
  EventEditorView\ 2.swift
  ReminderEditorView\ 2.swift
  ReceiptCSVPreviewView\ 2.swift
]
remove_file_refs_by_basenames(project, editor_basenames)

# 3) Add correct refs under the root Editors group (paths are just basenames)
refs = editor_basenames.first(4).map { |bn| ensure_file_ref(project, editors_group, bn) }

# 4) Ensure they’re in Compile Sources for app + both extensions
refs.each do |ref|
  targets.each { |t| ensure_in_sources(t, ref) }
end

# 5) Ensure extensions also compile Core helpers the editors need
core_rel_paths = %w[
  Screen Actions/Core/DataDetectors.swift
  Screen Actions/Core/CalendarService.swift
  Screen Actions/Core/RemindersService.swift
  Screen Actions/Core/ContactsService.swift
  Screen Actions/Core/CSVExporter.swift
  Screen Actions/Core/AppStorageService.swift
]
core_refs = core_rel_paths.map do |p|
  project.files.find { |f| f.path == p } ||
    begin
      # create a file ref if missing (under main group so path stays absolute from SOURCE_ROOT)
      r = project.main_group.new_file(p)
      r.set_source_tree('SOURCE_ROOT')
      r
    end
end
[share_t, action_t].each { |t| core_refs.each { |ref| ensure_in_sources(t, ref) } }

project.save
puts "✔ Project fixed: Editors group at root, correct file refs, sources phases updated."
