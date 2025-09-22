#!/usr/bin/env ruby
# Rewrites "(browser|chrome).runtime.sendNativeMessage('host', payload)"
# to      "(browser|chrome).runtime.sendNativeMessage(payload)"
# (required on iOS Safari; host arg is invalid and causes SFErrorDomain=3)

DEFAULT_PATHS = [
  'ScreenActionsWebExtension/WebRes/background.js',
  'ScreenActionsWebExtension/WebRes/popup.js'
]

paths = ARGV.empty? ? DEFAULT_PATHS : ARGV
paths.each do |p|
  unless File.file?(p)
    warn "skip (missing): #{p}"
    next
  end
  src = File.read(p)
  fixed = src.gsub(/((?:browser|chrome)\.runtime\.sendNativeMessage\()\s*(['"]).*?\2\s*,\s*/m) { Regexp.last_match(1) }
  if fixed != src
    File.write(p, fixed)
    puts "✓ Rewrote #{p}"
  else
    puts "… no changes for #{p}"
  end
end
