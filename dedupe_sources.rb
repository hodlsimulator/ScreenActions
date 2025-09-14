require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')

def sources_phase_for(t)
  t.respond_to?(:sources_build_phase) ? t.sources_build_phase :
    t.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' }
end

targets = ['Screen Actions','ScreenActionsShareExtension','ScreenActionsActionExtension']
proj.targets.select { |t| targets.include?(t.name) }.each do |t|
  ph = sources_phase_for(t)
  next unless ph
  seen = {}
  removed = 0
  ph.files.dup.each do |bf|
    ref = bf.file_ref
    next unless ref
    # Key by real absolute path if possible, else path/uuid
    key = (ref.respond_to?(:real_path) && ref.real_path) ? ref.real_path.to_s : (ref.path || ref.display_name || ref.uuid)
    if seen[key]
      bf.remove_from_project
      removed += 1
    else
      seen[key] = true
    end
  end
  puts "Target #{t.name}: removed #{removed} duplicate entries from Compile Sources"
end

proj.save
