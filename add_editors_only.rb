require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')

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

def sources_phase_for(t)
  t.respond_to?(:sources_build_phase) ? t.sources_build_phase :
    t.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

def ensure_group_at_root(project, name, rel_path)
  g = find_group(project.main_group, name)
  g ||= project.main_group.new_group(name, rel_path)
  g.path = rel_path
  g.set_source_tree('SOURCE_ROOT')
  g
end

def ensure_file_ref_under_group(project, group, basename)
  existing = group.children.find { |c| c.isa == 'PBXFileReference' && c.path == basename }
  return existing if existing
  r = group.new_file(basename)
  r.set_source_tree('<group>') # relative to Editors/
  r
end

def ensure_in_sources(target, file_ref)
  ph = sources_phase_for(target)
  return unless ph
  ph.add_file_reference(file_ref) unless ph.files_references.include?(file_ref)
end

# Targets
app    = proj.targets.find { |t| t.name == 'Screen Actions' }
share  = proj.targets.find { |t| t.name == 'ScreenActionsShareExtension' }
action = proj.targets.find { |t| t.name == 'ScreenActionsActionExtension' }
targets = [app, share, action].compact
raise "Targets not found" if targets.empty?

# Create root-level Editors group and add four files
editors_group = ensure_group_at_root(proj, 'Editors', 'Editors')
%w[EventEditorView.swift ReminderEditorView.swift ContactEditorView.swift ReceiptCSVPreviewView.swift].each do |bn|
  ref = ensure_file_ref_under_group(proj, editors_group, bn)
  targets.each { |t| ensure_in_sources(t, ref) }
end

proj.save

# Print a tiny summary
targets.each do |t|
  ph = sources_phase_for(t)
  next unless ph
  paths = ph.files_references.map { |r| r.real_path.to_s }
  puts "Target #{t.name}:"
  %w[EventEditorView.swift ReminderEditorView.swift ContactEditorView.swift ReceiptCSVPreviewView.swift].each do |bn|
    puts "  #{bn}: #{paths.any? { |p| p.end_with?("/Editors/#{bn}") } ? '✓' : '✗'}"
  end
end
