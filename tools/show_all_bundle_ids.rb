#!/usr/bin/env ruby
require 'xcodeproj'
proj = Xcodeproj::Project.open('Screen Actions.xcodeproj')
puts "TARGET\t\tPRODUCT_BUNDLE_IDENTIFIER\tPRODUCT_TYPE"
proj.targets.each do |t|
  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } ||
       t.build_configuration_list.build_configurations.first
  bid = bc&.build_settings&.fetch('PRODUCT_BUNDLE_IDENTIFIER', '(unset)')
  puts "#{t.name}\t#{bid}\t#{t.product_type}"
end
