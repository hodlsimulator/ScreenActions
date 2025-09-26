#!/usr/bin/env ruby
# Remove any Copy Files phase in the ScreenActionsWebExtension target that tries to
# copy the packaged manifest back into the repo (causes cycles / key stripping).
# Updated to use `plutil -convert objc` (modern replacement for the old "openstep").

require "json"

ROOT = File.expand_path(File.join(__dir__, ".."))
PROJ = File.join(ROOT, "Screen Actions.xcodeproj", "project.pbxproj")

def run_plutil_to_json(path)
  out = `plutil -convert json -o - "#{path}" 2>&1`
  unless $?.success?
    abort "plutil→json failed:\n#{out}"
  end
  out
end

def write_pbxproj_from_json(json_str, dest_path)
  # Write back in ObjC/OpenStep syntax (modern plutil uses 'objc' not 'openstep')
  IO.popen(%W[plutil -convert objc -o #{dest_path} -], "w") do |io|
    io.write(json_str)
  end
  io_status = $?.exitstatus
  abort "plutil→objc failed (exit #{io_status})" unless io_status == 0
end

raw = run_plutil_to_json(PROJ)
pbx = JSON.parse(raw)
objects = pbx.fetch("objects")

# Find the WebExtension target
tgt = objects.values.find { |o| o["isa"] == "PBXNativeTarget" && o["name"] == "ScreenActionsWebExtension" }
abort "Target ScreenActionsWebExtension not found in #{PROJ}" unless tgt

phase_ids = Array(tgt["buildPhases"]).dup
removed = []

phase_ids.each do |pid|
  ph = objects[pid] or next
  next unless ph["isa"] == "PBXCopyFilesBuildPhase"

  name    = (ph["name"] || "").to_s
  dst     = (ph["dstPath"] || "").to_s
  subspec = ph["dstSubfolderSpec"]

  # Heuristics: any Copy Files phase that appears to push files back into the repo
  # or is clearly a “verify/copy manifest back” thing.
  suspicious =
    name.match?(/copy\s*back|manifest/i) ||
    dst.start_with?("/") && dst.include?("/ScreenActionsWebExtension/WebRes") ||
    dst.include?("ScreenActionsWebExtension/WebRes") && dst.include?("SRCROOT")

  if suspicious
    # Remove the PBXCopyFilesBuildPhase and its PBXBuildFile children (if any)
    Array(ph["files"]).each do |bfid|
      bf = objects[bfid]
      objects.delete(bfid) if bf && bf["isa"] == "PBXBuildFile"
    end
    objects.delete(pid)
    tgt["buildPhases"].delete(pid)
    removed << "#{name.empty? ? pid : name} (dst=#{dst.inspect} spec=#{subspec.inspect})"
  end
end

# Write back
write_pbxproj_from_json(JSON.pretty_generate(pbx), PROJ)

if removed.empty?
  STDERR.puts "No copy-back phases found. Nothing to remove."
else
  STDERR.puts "Removed phases:"
  removed.each { |r| STDERR.puts "- #{r}" }
end
STDERR.puts "OK: fixed build phases for ScreenActionsWebExtension."
