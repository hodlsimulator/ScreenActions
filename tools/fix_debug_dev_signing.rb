#!/usr/bin/env ruby
require 'xcodeproj'
PROJECT = 'Screen Actions.xcodeproj'
TEAM_ID = '92HEPEJ42Z'
NUKE = %w[
  CODE_SIGN_IDENTITY
  CODE_SIGN_IDENTITY[sdk=iphoneos*]
  CODE_SIGN_IDENTITY[sdk=iphonesimulator*]
  PROVISIONING_PROFILE
  PROVISIONING_PROFILE_SPECIFIER
  PROVISIONING_PROFILE[sdk=iphoneos*]
  PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]
  OTHER_CODE_SIGN_FLAGS
]

proj = Xcodeproj::Project.open(PROJECT)

# Project-level Debug
proj.build_configurations.each do |bc|
  next unless bc.name == 'Debug'
  bs = bc.build_settings
  NUKE.each { |k| bs.delete(k) }
  bs['CODE_SIGN_STYLE']       = 'Automatic'
  bs['DEVELOPMENT_TEAM']      = TEAM_ID
  bs['CODE_SIGNING_ALLOWED']  = 'YES'
  bs['CODE_SIGNING_REQUIRED'] = 'YES'
end

# Target-level Debug
proj.targets.each do |t|
  t.build_configuration_list.build_configurations.each do |bc|
    next unless bc.name == 'Debug'
    bs = bc.build_settings
    NUKE.each { |k| bs.delete(k) }
    bs['CODE_SIGN_STYLE']       = 'Automatic'
    bs['DEVELOPMENT_TEAM']      = TEAM_ID
    bs['CODE_SIGNING_ALLOWED']  = 'YES'
    bs['CODE_SIGNING_REQUIRED'] = 'YES'
  end
end

proj.save
puts "✓ Debug is now Automatic (Development). Release untouched."
