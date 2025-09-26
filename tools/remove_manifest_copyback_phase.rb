#!/usr/bin/env ruby
# Remove any Copy Files phase in the *ScreenActionsWebExtension* target that
# copies the packaged manifest back into the repo (causes a build cycle).

require "json"

proj = File.join(__dir__, "..", "Screen Actions.xcodeproj", "project.pbxproj")
json = JSON.parse(`plutil -convert json -o - "#{proj}"`)
objs = json.fetch("objects")

# 1) Find the WebExtension target
tgt = objs.values.find { |o|
  o["isa"] == "PBXNativeTarget" && o["name"] == "ScreenActionsWebExtension"
}
abort "Target ScreenActionsWebExtension not found" unless tgt

bp_ids = Array(tgt["buildPhases"])
removed = []

bp_ids.dup.each do |bid|
  ph = objs[bid] or next
  next unless ph["isa"] == "PBXCopyFilesBuildPhase"

  name = (ph["name"] || "").downcase
  dst  = (ph["dstPath"] || "").to_s
  spec = (ph["dstSubfolderSpec"] || "").to_s

  # Legit phases copy into the product's Resources with dstSubfolderSpec=7 and
  # relative dstPath ("WebRes", "WebRes/_locales/en", "WebRes/images").
  # The bad phase copies from product → SRCROOT (absolute path).
  bad_absolute_dst = dst.start_with?("/") && dst.include?("/ScreenActionsWebExtension/WebRes")
  wrong_place      = spec != "7" && spec != 7

  if bad_absolute_dst || wrong_place || name.include?("verify packaged manifest")
    removed << [bid, ph["name"], dst, spec]
    objs.delete(bid)
    bp_ids.delete(bid)
  end
end

tgt["buildPhases"] = bp_ids

# 2) Make/repair the read-only verify script phase (no writes, no cycle)
verify_phase = objs.values.find { |o|
  o["isa"] == "PBXShellScriptBuildPhase" &&
  (o["name"] || "") =~ /Verify packaged manifest/i
}

if verify_phase
  verify_phase["shellPath"]  = "/bin/zsh"
  verify_phase["shellScript"] = %Q{"$SRCROOT/tools/verify_packaged_manifest_readonly.zsh"\n}
  verify_phase["inputPaths"]  = [
    '$(SRCROOT)/ScreenActionsWebExtension/WebRes/manifest.json',
    '$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/WebRes/manifest.json'
  ]
  verify_phase["outputPaths"] = [
    '$(DERIVED_FILE_DIR)/webres_manifest_verified.stamp'
  ]
  verify_phase["runOnlyForDeploymentPostprocessing"] = "0"
else
  # Create a small, safe verify phase at the end
  def gen_id
    (0...24).map { ("0".."9").to_a.concat(("A".."F").to_a).sample }.join
  end
  vid = gen_id
  objs[vid] = {
    "isa"=>"PBXShellScriptBuildPhase",
    "buildActionMask"=>"2147483647",
    "files"=>[],
    "inputPaths"=>[
      '$(SRCROOT)/ScreenActionsWebExtension/WebRes/manifest.json',
      '$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/WebRes/manifest.json'
    ],
    "name"=>"Verify packaged manifest == source",
    "outputPaths"=>['$(DERIVED_FILE_DIR)/webres_manifest_verified.stamp'],
    "runOnlyForDeploymentPostprocessing"=>"0",
    "shellPath"=>"/bin/zsh",
    "shellScript"=>%Q{"$SRCROOT/tools/verify_packaged_manifest_readonly.zsh"\n},
    "showEnvVarsInLog"=>"0"
  }
  tgt["buildPhases"] << vid
end

IO.popen(%W[plutil -convert openstep -o #{proj} -], "w") { |io|
  io.write(JSON.pretty_generate(json))
}

STDERR.puts "Removed phases:\n" + removed.map { |r| "- #{r[1]} (dst=#{r[2]} spec=#{r[3]}) [#{r[0]}]" }.join("\n")
STDERR.puts "OK: fixed build phases for ScreenActionsWebExtension."
