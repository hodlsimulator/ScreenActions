require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')

TARGET = 'ScreenActionsWebExtension'
KEEP_DIR = '/ScreenActionsWebExtension/'

t = proj.targets.find { |x| x.name == TARGET } or abort "Target #{TARGET} not found"
ph = t.build_phases.find { |ph| ph.isa == 'PBXSourcesBuildPhase' } or abort "No sources phase for #{TARGET}"

removed = []
kept = []

ph.files.dup.each do |bf|
  ref = bf.file_ref
  next unless ref
  path = (ref.respond_to?(:real_path) && ref.real_path) ? ref.real_path.to_s : (ref.path || "")
  if path.include?(KEEP_DIR)
    kept << path
  else
    removed << path
    bf.remove_from_project
  end
end

# Deduplicate any leftovers
seen = {}
ph.files.dup.each do |bf|
  ref = bf.file_ref
  next unless ref
  key = (ref.respond_to?(:real_path) && ref.real_path) ? ref.real_path.to_s : (ref.path || ref.uuid)
  if seen[key]
    removed << key
    bf.remove_from_project
  else
    seen[key] = true
  end
end

proj.save
puts "Removed #{removed.size} files from #{TARGET} sources."
puts "Kept:"
kept.each { |p| puts "  - #{p}" }
