#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TARGETS = [
  'Screen Actions',
  'ScreenActionsWebExtension',
  'ScreenActionsShareExtension',
  'ScreenActionsActionExtension',
  'ScreenActionsControls'
]

proj = Xcodeproj::Project.open(PROJECT)

puts "Target\tCONFIG\tPRODUCT_BUNDLE_IDENTIFIER\tDEVELOPMENT_TEAM"
TARGETS.each do |name|
  t = proj.targets.find { |tt| tt.name == name }
  next unless t
  bc = t.build_configuration_list.build_configurations.find { |c| c.name == 'Release' } ||
       t.build_configuration_list.build_configurations.first
  bs = bc.build_settings
  bid = bs['PRODUCT_BUNDLE_IDENTIFIER'] || '(unset)'
  team = bs['DEVELOPMENT_TEAM'] || '(unset)'
  puts "#{name}\t#{bc.name}\t#{bid}\t#{team}"
end
