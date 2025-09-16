require 'xcodeproj'
p = Xcodeproj::Project.open('Screen Actions.xcodeproj')

def file_ref_for(p, path)
  p.files.find{ |f| f.path == path } || p.new_file(path)
end

def ensure_src(target, ref)
  ph = target.source_build_phase
  return unless ph
  ph.add_file_reference(ref) unless ph.files_references.include?(ref)
end

def ensure_framework(target, project, name)
  path = "/System/Library/Frameworks/#{name}.framework"
  ref = project.frameworks_group.files.find{ |f| f.path == path } || project.frameworks_group.new_file(path)
  unless target.frameworks_build_phase.files_references.include?(ref)
    target.frameworks_build_phase.add_file_reference(ref)
  end
end

['ScreenActionsWebExtension','ScreenActionsWebExtension2'].each do |tn|
  t = p.targets.find{ |x| x.name == tn }; next unless t

  keep = []
  if tn == 'ScreenActionsWebExtension'
    keep << file_ref_for(p, 'ScreenActionsWebExtension/SAWebExtensionHandler.m')
    keep << file_ref_for(p, 'ScreenActionsWebExtension/WebExtensionBridge.swift')
  else
    keep << file_ref_for(p, 'ScreenActionsWebExtension2/SafariWebExtensionHandler.swift')
    keep << file_ref_for(p, 'ScreenActionsWebExtension/WebExtensionBridge.swift')
  end

  ph = t.source_build_phase
  if ph
    ph.files.dup.each do |bf|
      ref = bf.file_ref
      path = (ref && (ref.real_path || ref.path)).to_s
      remove = false
      remove ||= path.end_with?('SAWebBridge.m') || path.end_with?('SAWebBridge.mm')
      remove ||= path.include?('ScreenActionsWebExtension/') && !keep.map(&:path).include?(ref.path)
      remove && ph.remove_build_file(bf)
    end
  end

  keep.each { |r| ensure_src(t, r) }
  ensure_framework(t, p, 'EventKit')
  ensure_framework(t, p, 'Contacts')

  t.build_configuration_list.build_configurations.each do |cfg|
    s = cfg.build_settings
    s['DEVELOPMENT_TEAM'] = '92HEPEJ42Z'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s.delete('PROVISIONING_PROFILE_SPECIFIER')
    s.delete('PROVISIONING_PROFILE')
    s.delete('PROVISIONING_PROFILE_REQUIRED')
    s['CODE_SIGN_IDENTITY'] = 'Apple Development'
    s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  end
end

p.save
