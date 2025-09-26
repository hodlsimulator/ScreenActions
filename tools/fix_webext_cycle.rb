#!/usr/bin/env ruby
# Removes the cycle-causing phases in the *ScreenActionsWebExtension* target:
#  • any PBXCopyFilesBuildPhase that copies to an absolute dstPath (copy-back)
#  • any "Verify packaged manifest" shell phase (we'll rely on your existing verifier zsh)
require "json"

proj_path = File.join(__dir__, "..", "Screen Actions.xcodeproj", "project.pbxproj")
json = JSON.parse(`plutil -convert json -o - "#{proj_path}"`)
objs = json.fetch("objects")

tgt = objs.values.find { |o| o["isa"]=="PBXNativeTarget" && o["name"]=="ScreenActionsWebExtension" } or abort "target not found"
bids = Array(tgt["buildPhases"])
removed = []

def kill!(objs, bids, id, why, removed)
  ph = objs[id] or return
  removed << "#{why}: #{ph["isa"]} #{ph["name"] || "(unnamed)"} [#{id}]"
  objs.delete(id)
  bids.delete(id)
end

bids.dup.each do |id|
  ph = objs[id] or next
  case ph["isa"]
  when "PBXCopyFilesBuildPhase"
    dst = (ph["dstPath"] || ph["dst_path"] || "").to_s
    spec = (ph["dstSubfolderSpec"] || ph["dst_subfolder_spec"] || "").to_s
    # Any absolute dstPath (copying *out* of the product) is illegal — remove it.
    if dst.start_with?("/")
      kill!(objs, bids, id, "copy-back (absolute dstPath)", removed)
      next
    end
    # Any CopyFiles phase not targeting Resources (7) is suspicious — remove it.
    unless ["7", 7].include?(spec)
      kill!(objs, bids, id, "bad dstSubfolderSpec=#{spec}", removed)
      next
    end
  when "PBXShellScriptBuildPhase"
    name   = (ph["name"] || "").to_s
    script = (ph["shellScript"] || "").to_s
    if name =~ /verify packaged manifest/i || script =~ /verify_packaged_manifest/i || script =~ /\bcmp\b.*manifest\.json/ || script =~ /\bcp\b.*manifest\.json/
      kill!(objs, bids, id, "verify/copyback script", removed)
      next
    end
  end
end

tgt["buildPhases"] = bids

IO.popen(%W[plutil -convert openstep -o #{proj_path} -], "w") { |io| io.write(JSON.pretty_generate(json)) }
$stderr.puts removed.empty? ? "No phases removed" : "Removed:\n- " + removed.join("\n- ")
puts "OK: saved #{proj_path}"
