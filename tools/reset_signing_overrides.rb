#!/usr/bin/env ruby
# Wipes manual Code Sign Identity / Provisioning Profile overrides at
# both project- and target-level for ALL configurations, then sets
# CODE_SIGN_STYLE=Automatic and pins your team. This avoids
# "conflicting provisioning settings" during archive.

require 'xcodeproj'
PROJECT = 'Screen Actions.xcodeproj'
TEAM_ID = '92HEPEJ42Z'  # your team

REMOVE_KEYS = %w[
  CODE_SIGN_IDENTITY
  CODE_SIGN_IDENTITY[sdk=iphoneos*]
  PROVISIONING_PROFILE
  PROVISIONING_PROFILE_SPECIFIER
  PROVISIONING_PROFILE[sdk=iphoneos*]
  OTHER_CODE_SIGN_FLAGS
].freeze

def scrub!(bc, team)
  bs = bc.build_settings
  # remove any exact or variant keys
  REMOVE_KEYS.each { |k| bs.delete(k) }
  bs.keys.grep(/PROVISIONING_PROFILE|CODE_SIGN_IDENTITY/i).each { |k| bs.delete(k) }

  bs['CODE_SIGN_STYLE']       = 'Automatic'
  bs['DEVELOPMENT_TEAM']      = team
  bs['CODE_SIGNING_ALLOWED']  = 'YES'
  bs['CODE_SIGNING_REQUIRED'] = 'YES'
end

proj = Xcodeproj::Project.open(PROJECT)

# Project-level
proj.build_configurations.each { |bc| scrub!(bc, TEAM_ID) }

# Target-level
proj.targets.each do |t|
  t.build_configuration_list.build_configurations.each { |bc| scrub!(bc, TEAM_ID) }
end

proj.save
puts "✓ Cleared manual signing overrides; set Automatic signing for all targets/configs (team #{TEAM_ID})."
puts "→ Re-archive with: zsh archive_and_verify.zsh"
