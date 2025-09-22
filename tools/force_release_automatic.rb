#!/usr/bin/env ruby
# Sets ALL targets' Release config to Automatic signing and removes any manual
# identity/profile overrides. Keeps your team. This avoids the "automatic dev
# vs Apple Distribution" clash and lets Xcode pick App Store profiles at archive.

require 'xcodeproj'
PROJECT = 'Screen Actions.xcodeproj'
TEAM_ID = '92HEPEJ42Z'

NUKE_KEYS = %w[
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

# Project-level
proj.build_configurations.each do |bc|
  next unless bc.name == 'Release'
  bs = bc.build_settings
  NUKE_KEYS.each { |k| bs.delete(k) }
  bs['CODE_SIGN_STYLE']       = 'Automatic'
  bs['DEVELOPMENT_TEAM']      = TEAM_ID
  bs['CODE_SIGNING_ALLOWED']  = 'YES'
  bs['CODE_SIGNING_REQUIRED'] = 'YES'
end

# Target-level
proj.targets.each do |t|
  t.build_configuration_list.build_configurations.each do |bc|
    next unless bc.name == 'Release'
    bs = bc.build_settings
    NUKE_KEYS.each { |k| bs.delete(k) }
    bs['CODE_SIGN_STYLE']       = 'Automatic'
    bs['DEVELOPMENT_TEAM']      = TEAM_ID
    bs['CODE_SIGNING_ALLOWED']  = 'YES'
    bs['CODE_SIGNING_REQUIRED'] = 'YES'
  end
end

proj.save
puts "✓ Release set to Automatic signing for all targets; manual identities/profiles removed."
puts "→ Now archive again."
