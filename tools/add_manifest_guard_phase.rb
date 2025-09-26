#!/usr/bin/env ruby
# Inject a PBXShellScriptBuildPhase that runs tools/guard_manifest_keys.rb for ScreenActionsWebExtension.
require "xcodeproj"
PROJECT = "Screen Actions.xcodeproj"
TARGET  = "ScreenActionsWebExtension"

proj = Xcodeproj::Project.open(PROJECT)
tgt  = proj.targets.find { |t| t.name == TARGET } or abort "Target #{TARGET} not found"

# Avoid duplicates
name = "Guard manifest keys (<all_urls>)"
existing = tgt.shell_script_build_phases.find { |p| p.name == name }
phase = existing || tgt.new_shell_script_build_phase(name)
phase.shell_path = "/bin/zsh"
phase.shell_script = %Q{"$SRCROOT/tools/guard_manifest_keys.rb" "$SRCROOT/ScreenActionsWebExtension/WebRes/manifest.json"\n}
phase.input_paths  = ['$(SRCROOT)/ScreenActionsWebExtension/WebRes/manifest.json']
phase.output_paths = ['$(DERIVED_FILE_DIR)/manifest_keys_ok.stamp']

proj.save
puts "✓ Added/updated build phase: #{name}"
