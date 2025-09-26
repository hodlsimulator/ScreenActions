#!/usr/bin/env ruby
# Removes the WebExtension build cycle by editing the pbxproj as plain text:
#  • delete any PBXCopyFilesBuildPhase that has an absolute dstPath (copy-back into repo)
#  • delete any PBXShellScriptBuildPhase named "Verify packaged manifest == source"
#  • remove their IDs from ScreenActionsWebExtension.buildPhases
#
# Makes a timestamped backup next to the pbxproj.

require 'time'

proj = File.join(__dir__, '..', 'Screen Actions.xcodeproj', 'project.pbxproj')
abort "pbxproj not found: #{proj}" unless File.file?(proj)

lines = File.readlines(proj, chomp: false)
backup = "#{proj}.bak.#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}"
File.write(backup, lines.join)

# Pass 1: find blocks to remove (by ID) + their line ranges
ids_to_remove = []
blocks_ranges = {} # id => (start_idx..end_idx)

in_block      = false
block_start   = nil
current_id    = nil
block_kind    = nil # "PBXCopyFilesBuildPhase" | "PBXShellScriptBuildPhase" | nil
block_text    = []

def header_id(line)
  m = line.match(/^\s*([A-F0-9]{24})\s+\/\*.*\*\/\s*=\s*\{\s*$/)
  m && m[1]
end

lines.each_with_index do |line, i|
  if !in_block
    if (id = header_id(line))
      in_block    = true
      block_start = i
      current_id  = id
      block_kind  = nil
      block_text  = [line]
    end
    next
  end

  block_text << line
  if line.include?('isa = ')
    block_kind = line[/isa\s*=\s*([A-Za-z0-9_]+)\s*;/, 1] || block_kind
  end

  if line.strip == '};'
    # Decide if this block should be removed
    text = block_text.join

    remove = false
    if block_kind == 'PBXCopyFilesBuildPhase'
      # Any absolute dstPath = "/Users/..." or non-Resources dstSubfolderSpec is bad
      remove ||= !!(text =~ /dstPath\s*=\s*\"?\//)
      remove ||= !!(text =~ /dstSubfolderSpec\s*=\s*0\s*;/)
    elsif block_kind == 'PBXShellScriptBuildPhase'
      # Our problematic verifier
      remove ||= !!(text =~ /name\s*=\s*\"?Verify packaged manifest == source\"?/i)
    end

    if remove
      ids_to_remove << current_id
      blocks_ranges[current_id] = (block_start..i)
    end

    in_block    = false
    block_start = nil
    current_id  = nil
    block_kind  = nil
    block_text  = []
  end
end

if ids_to_remove.empty?
  puts "Nothing to remove. (No copy-back or verify phases found)"
else
  puts "Removing phases: #{ids_to_remove.join(', ')}"
end

# Pass 2: write file while skipping the bad blocks
out = []
skip_range = nil
lines.each_with_index do |line, i|
  if skip_range && skip_range.cover?(i)
    next
  elsif skip_range && i > skip_range.end
    skip_range = nil
  end

  # If this line starts a block we want to remove, set skip_range
  if (id = header_id(line)) && blocks_ranges.key?(id)
    skip_range = blocks_ranges[id]
    next
  end

  out << line
end

txt = out.join

# Pass 3: drop IDs from ScreenActionsWebExtension.buildPhases list
# Find the target block by its comment name and edit only the buildPhases list inside it.
target_rx = /
(^\s*[A-F0-9]{24}\s+\/\*\s*ScreenActionsWebExtension\s*\*\/\s*=\s*\{\s*\n) # header
(.*?)
(^\s*\};\s*$)                                                                # footer
/mx

txt = txt.gsub(target_rx) do |whole|
  header = $1
  body   = $2
  footer = $3

  body = body.gsub(/(buildPhases\s*=\s*\(\s*\n)(.*?)(^\s*\)\s*;\s*$)/m) do
    bh_head = $1
    list    = $2
    bh_tail = $3
    # Filter out any lines that reference our IDs
    filtered = list.lines.reject do |ln|
      ids_to_remove.any? { |rid| ln.include?(rid) }
    end
    bh_head + filtered.join + bh_tail
  end

  header + body + footer
end

File.write(proj, txt)
puts "OK: updated #{proj}\nBackup: #{backup}"
