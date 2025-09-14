require 'xcodeproj'
proj_path = 'Screen Actions.xcodeproj'
project   = Xcodeproj::Project.open(proj_path)

def find_group(node, name)
  return node if node.respond_to?(:display_name) && node.display_name == name
  return nil unless node.respond_to?(:children)
  node.children.each do |child|
    next unless child.is_a?(Xcodeproj::Project::Object::PBXGroup)
    f = find_group(child, name)
    return f if f
  end
  nil
end

def sources_phase_for(target)
  target.respond_to?(:sources_build_phase) ? target.sources_build_phase :
  target.respond_to?(:source_build_phase)  ? target.source_build_phase  :
  target.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def ensure_group_at_root(project, name, rel_path)
  g = find_group(project.main_group, name)
  g = project.main_group.new_group(name, rel_path) unless g
  g.path = rel_path
  g.set_source_tree('SOURCE_ROOT')
  g
end

def remove_build_files_pointing_to(project, refs)
  project.targets.each do |t|
    t.build_phases.each do |ph|
      ph.files.dup.each { |bf| bf.remove_from_project if refs.include?(bf.file_ref) }
    end
  end
end

def remove_bad_refs(project)
  bad = project.files.select do |f|
    next false unless f.path
    bn = File.basename(f.path)
    f.path == 'Screen' ||              # bogus from earlier
    f.path.start_with?('Actions/Core/') ||  # split at space
    bn.end_with?(' 2.swift') ||
    bn =~ /_old\.swift(\.txt)?$/ ||
    !f.real_path.exist?
  end
  remove_build_files_pointing_to(project, bad)
  bad.each(&:remove_from_project)
end

def ensure_file_ref_by_path(project, abs_or_rel_path)
  ref = project.files.find { |f| f.path == abs_or_rel_path }
  return ref if ref
  r = project.main_group.new_file(abs_or_rel_path)
  r.set_source_tree('SOURCE_ROOT')
  r
end

def ensure_file_ref_under_group(project, group, basename)
  existing = group.children.find { |c| c.isa == 'PBXFileReference' && c.path == basename }
  return existing if existing
  r = group.new_file(basename)
  r.set_source_tree('<group>')  # relative to Editors/
  r
end

def ensure_in_sources(target, file_ref)
  ph = sources_phase_for(target)
  raise "No Sources phase for #{target.name}" unless ph
  ph.add_file_reference(file_ref) unless ph.files_references.include?(file_ref)
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

# 1) Clean bad refs from earlier attempts
remove_bad_refs(project)

# 2) Editors group at project root (matches your on-disk Editors/)
editors_group = ensure_group_at_root(project, 'Editors', 'Editors')

# 3) Ensure editor refs and add to ALL targets
editor_basenames = %w[EventEditorView.swift ReminderEditorView.swift ContactEditorView.swift ReceiptCSVPreviewView.swift]
editor_refs = editor_basenames.map { |bn| ensure_file_ref_under_group(project, editors_group, bn) }
editor_refs.each { |ref| targets.each { |t| ensure_in_sources(t, ref) } }

# 4) Ensure core refs (with proper space in path) and add to the TWO extensions
core_paths = [
  'Screen Actions/Core/DataDetectors.swift',
  'Screen Actions/Core/CalendarService.swift',
  'Screen Actions/Core/RemindersService.swift',
  'Screen Actions/Core/ContactsService.swift',
  'Screen Actions/Core/CSVExporter.swift',
  'Screen Actions/Core/AppStorageService.swift',
  'Screen Actions/Core/SAActionPanelView.swift'
]
core_refs = core_paths.map { |p| ensure_file_ref_by_path(project, p) }
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
    ref = core_refs[core_paths.index(p)]
    ok  = [share_t, action_t].include?(t) ? in_sources?(t, ref) : !!ref # app already has them
    on_disk, _ = exists_abs(p)
    puts "  - core #{File.basename(p)}: sources=#{ok ? '✓' : '✗'}  disk=#{on_disk ? '✓' : '✗'}"
  end
end
