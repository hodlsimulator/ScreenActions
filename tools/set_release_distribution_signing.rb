#!/usr/bin/env ruby
# Sets Release signing to Apple Distribution for the app + extensions,
# unsets any pinned dev profiles, and pins your Team.
#
# Usage:
#   gem install xcodeproj
#   ruby tools/set_release_distribution_signing.rb
#
require 'xcodeproj'

PROJECT = 'Screen Actions.xcodeproj'
TEAM_ID = '92HEPEJ42Z' # your team

APP_TARGET = 'Screen Actions'
EXT_TARGETS = [
  'ScreenActionsWebExtension',
  'ScreenActionsShareExtension',
  'ScreenActionsActionExtension',
  'ScreenActionsControls'
].freeze

def tweak_release(bs)
  # Force Distribution identity on device SDK
  bs['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  bs['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
  # Let Xcode pick the right App Store profile
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['DEVELOPMENT_TEAM'] = TEAM_ID

  # Unpin any dev/ad-hoc profiles that might force get-task-allow=true
  %w[
    PROVISIONING_PROFILE
    PROVISIONING_PROFILE_SPECIFIER
    PROVISIONING_PROFILE[sdk=iphoneos*]
  ].each { |k| bs.delete(k) }

  # Safety: don’t accidentally disable signing
  bs['CODE_SIGNING_ALLOWED']  = 'YES'
  bs['CODE_SIGNING_REQUIRED'] = 'YES'
end

proj = Xcodeproj::Project.open(PROJECT)

targets = []
(app = proj.targets.find { |t| t.name == APP_TARGET }) or abort "✗ Missing target: #{APP_TARGET}"
targets << app

EXT_TARGETS.each do |name|
  t = proj.targets.find { |tt| tt.name == name }
  targets << t if t
end

targets.each do |t|
  t.build_configuration_list.build_configurations.each do |cfg|
    next unless cfg.name == 'Release'
    tweak_release(cfg.build_settings)
  end
end

proj.save
puts "✓ Set Release signing to Apple Distribution for: #{targets.map(&:name).join(', ')}"
puts "→ Now re-archive: zsh archive_and_verify.zsh"
