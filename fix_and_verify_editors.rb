require 'xcodeproj'
proj_path = 'Screen Actions.xcodeproj'
project   = Xcodeproj::Project.open(proj_path)

def find_group(node, name)
  return node if node.respond_to?(:display_name) && node.display_name == name
  return nil unless node.respond_to?(:children)
  node.children.each do |child|
    next unless child.is_a?(Xcodeproj::Project::Object::PBXGroup)
    found = find_group(child, name)
    return found if found
  end
  nil
end

def sources_phase_for(target)
  return target.sources_build_phase if target.respond_to?(:sources_build_phase)
  return target.source_build_phase  if target.respond_to?(:source_build_phase)
  target.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def ensure_group_at_root(project, name, rel_path)
  g = find_group(project.main_group, name)
  g = project.main_group.new_group(name, rel_path) unless g
  g.path = rel_path
  g.set_source_tree('SOURCE_ROOT')   # paths relative to project root
  g
end

def remove_build_files_pointing_to(project, file_refs)
  project.targets.each do |t|
    t.build_phases.each do |ph|
      ph.files.dup.each do |bf|
        bf.remove_from_project if file_refs.include?(bf.file_ref)
      end
    end
  end
end

def remove_editor_refs(project, basenames)
  to_remove = project.files.select do |f|
    next false unless f.path
    bn = File.basename(f.path)
    wrong_place = (bn =~ /\.swift$/) && !f.real_path.exist?
    wrong_place ||= f.path.include?('Screen Actions/Editors/') # old wrong path
    is_dup = bn.end_with?(' 2.swift')
    is_old = bn =~ /_old\.swift(\.txt)?$/
    is_editor_name = basenames.include?(bn)
    # We remove bad/duplicate refs; we won't remove a good ref under the root Editors group
    (is_dup || is_old || wrong_place) && is_editor_name
  end
  remove_build_files_pointing_to(project, to_remove)
  to_remove.each(&:remove_from_project)
end

def ensure_file_ref_under_group(project, group, basename)
  existing = group.children.find { |c| c.isa == 'PBXFileReference' && c.path == basename }
  return existing if existing
  ref = group.new_file(basename)     # path is relative to group (Editors)
  ref.set_source_tree('<group>')
  ref
end

def ensure_in_sources(target, file_ref)
  ph = sources_phase_for(target)
  raise "No Sources phase for #{target.name}" unless ph
  ph.add_file_reference(file_ref) unless ph.files_references.include?(file_ref)
  # Make sure it isn't in Resources by mistake
  if target.respond_to?(:resources_build_phase) && target.resources_build_phase
    target.resources_build_phase.files.dup.each { |bf| bf.remove_from_project if bf.file_ref == file_ref }
  end
end

def in_sources?(target, file_ref)
  ph = sources_phase_for(target)
  ph && ph.files_references.include?(file_ref)
end

# Targets
app_t    = project.targets.find { |t| t.name == 'Screen Actions' }
share_t  = project.targets.find { |t| t.name == 'ScreenActionsShareExtension' }
action_t = project.targets.find { |t| t.name == 'ScreenActionsActionExtension' }
targets  = [app_t, share_t, action_t].compact
raise 'Targets not found' if targets.empty?

# Editors group at project root
editors_group = ensure_group_at_root(project, 'Editors', 'Editors')

# Editor filenames
editor_basenames = %w[
  EventEditorView.swift
  ReminderEditorView.swift
  ContactEditorView.swift
  ReceiptCSVPreviewView.swift
]

# Remove stale/duplicate/wrong-path refs
remove_editor_refs(project, editor_basenames + editor_basenames.map { |bn| bn.sub('.swift', ' 2.swift') })

# Ensure correct refs under the root Editors group
editor_refs = editor_basenames.map { |bn| ensure_file_ref_under_group(project, editors_group, bn) }

# Add to Compile Sources for all three targets
editor_refs.each { |ref| targets.each { |t| ensure_in_sources(t, ref) } }

# Ensure extensions compile the Core helpers the editors depend on (and the panel)
core_paths = %w[
  Screen Actions/Core/DataDetectors.swift
  Screen Actions/Core/CalendarService.swift
  Screen Actions/Core/RemindersService.swift
  Screen Actions/Core/ContactsService.swift
  Screen Actions/Core/CSVExporter.swift
  Screen Actions/Core/AppStorageService.swift
  Screen Actions/Core/SAActionPanelView.swift
]
core_refs = core_paths.map do |p|
  project.files.find { |f| f.path == p } ||
    begin
      r = project.main_group.new_file(p)
      r.set_source_tree('SOURCE_ROOT')
      r
    end
end
[share_t, action_t].each { |t| core_refs.each { |ref| ensure_in_sources(t, ref) } }

project.save

# Summary
def exists_abs(path)
  full = File.expand_path(path, Dir.pwd)
  [File.exist?(full), full]
end

puts "✔ Project updated.\nSummary:"
targets.each do |t|
  puts "\nTarget: #{t.name}"
  editor_basenames.each_with_index do |bn, idx|
    ref = editor_refs[idx]
    ok  = in_sources?(t, ref)
    on_disk, full = exists_abs(File.join('Editors', bn))
    puts "  - #{bn}: sources=#{ok ? '✓' : '✗'}  disk=#{on_disk ? '✓' : '✗'}  (#{full})"
  end
  core_paths.each do |p|
    ref = project.files.find { |f| f.path == p }
    ok  = ref && in_sources?(t, ref)
    on_disk, _ = exists_abs(p)
    puts "  - core #{File.basename(p)}: sources=#{ok ? '✓' : '✗'}  disk=#{on_disk ? '✓' : '✗'}"
  end
end
