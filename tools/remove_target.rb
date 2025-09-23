#!/usr/bin/env ruby
# Deletes a target (and its product + build phases) from the Xcode project.
require 'xcodeproj'
PROJECT = 'Screen Actions.xcodeproj'
TARGETS_TO_DELETE = ['ScreenActionsWebExtension2']  # add more names if needed

proj = Xcodeproj::Project.open(PROJECT)
TARGETS_TO_DELETE.each do |name|
  t = proj.targets.find { |tt| tt.name == name }
  next unless t
  # remove product reference from groups
  proj.objects.select { |o| o.isa == 'PBXFileReference' && o == t.product_reference }.each(&:remove_from_project)
  # remove target from build configurations and project
  proj.targets.delete(t)
  proj.objects_by_uuid.delete(t.uuid)
  puts "✓ Removed target: #{name}"
end
proj.save
