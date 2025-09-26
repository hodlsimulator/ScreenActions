#!/usr/bin/env ruby
# pbx_kill_webext_cycle.rb — remove the phases that cause the WebExtension build cycle
# - Kills any PBXCopyFilesBuildPhase with absolute dstPath (copy-back into repo)
# - Kills any PBXShellScriptBuildPhase named "Verify packaged manifest == source"
# - Drops their IDs from the ScreenActionsWebExtension target's buildPhases list
#
# Pure text edit (no plutil). Makes a timestamped backup next to the pbxproj.

require 'time'

proj = File.join(__dir__, '..', 'Screen Actions.xcodeproj', 'project.pbxproj')
abort "pbxproj not found: #{proj}" unless File.file?(proj)

src = File.read(proj)
backup = "#{proj}.bak.#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}"
File.write(backup, src)

def remove_blocks(src, isa:, &predicate)
  removed_ids = []
  start_tag = "/* Begin #{isa} section */"
  end_tag   = "/* End #{isa} section */"

  start_i = src.index(start_tag)
  end_i   = src.index(end_tag)
  return [src, removed_ids] unless start_i && end_i && end_i > start_i

  before = src[0...start_i + start_tag.length]
  body   = src[(start_i + start_tag.length)...end_i]
  after  = src[end_i..-1]

  # Scan blocks:   <ID> /* … */ = {  …  };
  body2 = body.dup
  rx = /
    ^\s*([A-F0-9]{24})\s+\/\*.*?\*\/\s*=\s*\{\s*\n # header w/ id
    (.*?)                                           # block contents
    ^\s*\};\s*\n                                    # end of block
  /mx

  body.scan(rx).each do |id, contents|
    full_match = body2[/^\s*#{id}\s+\/\*.*?\*\/\s*=\s*\{\s*\n.*?^\s*\};\s*\n/m]
    next unless full_match

    # keep only blocks that match the given ISA
    next unless full_match.include?("isa = #{isa};")

    if predicate.call(full_match)
      removed_ids << id
      body2.sub!(full_match, '')
    end
  end

  new_src = before + body2 + after
  [new_src, removed_ids]
end

# 1) Kill copy-back CopyFiles phases (absolute dstPath)
src, removed_copy = remove_blocks(src, isa: 'PBXCopyFilesBuildPhase') do |block|
  # Example bad: dstPath = "/Users/conor/Developer/.../ScreenActionsWebExtension/WebRes/manifest.json";
  block =~ /dstPath\s*=\s*\"?\/Users\// || block =~ /dstSubfolderSpec\s*=\s*0\s*;/
end

# 2) Kill the "Verify packaged manifest == source" shell phase
src, removed_shell = remove_blocks(src, isa: 'PBXShellScriptBuildPhase') do |block|
  block =~ /name\s*=\s*\"?Verify packaged manifest == source\"?/i
end

removed_ids = (removed_copy + removed_shell).uniq

# 3) Drop those IDs from the ScreenActionsWebExtension target's buildPhases list
if removed_ids.any?
  # Find the PBXNativeTarget section
  tgt_rx = /
    (\/\* Begin PBXNativeTarget section \*\/.*?\/\* End PBXNativeTarget section \*\/)
  /mx
  native_section = src[tgt_rx, 1]
  if native_section
    # Locate the specific target block
    block_rx = /
      ^\s*([A-F0-9]{24})\s+\/\*\s*ScreenActionsWebExtension\s*\*\/\s*=\s*\{\s*\n
      (.*?)
      ^\s*\};\s*\n
    /mx
    new_section = native_section.dup
    native_section.scan(block_rx).each do |id, block|
      next unless block.include?('isa = PBXNativeTarget;')
      next unless block =~ /name\s*=\s*ScreenActionsWebExtension\s*;/

      new_block = block.dup
      removed_ids.each do |rid|
        # remove lines like:    RID /* ... */,    or RID,
        new_block.gsub!(/^\s*#{rid}\s*\/\*.*?\*\/\s*,\s*\n/m, '')
        new_block.gsub!(/^\s*#{rid}\s*,\s*\n/m, '')
      end

      old = "#{id} /* ScreenActionsWebExtension */ = {\n#{block}\n};\n"
      neu = "#{id} /* ScreenActionsWebExtension */ = {\n#{new_block}\n};\n"
      new_section.sub!(old, neu)
    end

    src.sub!(native_section, new_section)
  end
end

File.write(proj, src)
puts "Removed phases (#{removed_ids.size}): #{removed_ids.join(', ')}"
puts "Backup written to: #{backup}"
puts "OK: updated #{proj}"
