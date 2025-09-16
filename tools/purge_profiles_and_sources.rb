require 'xcodeproj'
p = Xcodeproj::Project.open('Screen Actions.xcodeproj')

def dedupe_sources!(t)
  ph=t.source_build_phase or return
  seen={}
  ph.files.dup.each do |bf|
    ref=bf.file_ref
    key = ref && ref.uuid
    if key && seen[key]
      ph.remove_build_file(bf)
    else
      seen[key]=true
    end
  end
end

[p.build_configuration_list, *p.targets.map(&:build_configuration_list)].compact.each do |bcl|
  bcl.build_configurations.each do |cfg|
    s=cfg.build_settings
    s.keys.grep(/PROVISIONING_PROFILE/).each{|k| s.delete(k)}
    s.keys.grep(/CODE_SIGN_STYLE/).each{|k| s[k]='Automatic'}
    s['DEVELOPMENT_TEAM']='92HEPEJ42Z'
  end
end

%w[ScreenActionsWebExtension ScreenActionsWebExtension2].each do |tn|
  t=p.targets.find{|x| x.name==tn} or next

  attrs=(p.root_object.attributes['TargetAttributes'] ||= {})
  tattrs=(attrs[t.uuid] ||= {})
  tattrs['ProvisioningStyle']='Automatic'
  tattrs['DevelopmentTeam']='92HEPEJ42Z'

  t.build_configuration_list.build_configurations.each do |cfg|
    s=cfg.build_settings
    s.keys.grep(/PROVISIONING_PROFILE/).each{|k| s.delete(k)}
    s.keys.grep(/CODE_SIGN_STYLE/).each{|k| s[k]='Automatic'}
    s['DEVELOPMENT_TEAM']='92HEPEJ42Z'
    s['CODE_SIGN_IDENTITY']='Apple Development'
    s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES']='YES'
    s['SWIFT_OBJC_BRIDGING_HEADER']=''
    s['CODE_SIGN_ENTITLEMENTS']=(tn=='ScreenActionsWebExtension2' ?
      'ScreenActionsWebExtension2/ScreenActionsWebExtension2.entitlements' :
      'ScreenActionsWebExtension/ScreenActionsWebExtension.entitlements')
    cfg.base_configuration_reference = nil if cfg.respond_to?(:base_configuration_reference)
  end

  ph=t.source_build_phase
  ph.files.dup.each{|bf| ph.remove_build_file(bf)} if ph

  if tn=='ScreenActionsWebExtension2'
    ref1 = p.files.find{|f| f.path=='ScreenActionsWebExtension2/SafariWebExtensionHandler.swift'} || p.new_file('ScreenActionsWebExtension2/SafariWebExtensionHandler.swift')
    ref2 = p.files.find{|f| f.path=='ScreenActionsWebExtension/WebExtensionBridge.swift'} || p.new_file('ScreenActionsWebExtension/WebExtensionBridge.swift')
    t.source_build_phase.add_file_reference(ref1)
    t.source_build_phase.add_file_reference(ref2)
  else
    ref1 = p.files.find{|f| f.path=='ScreenActionsWebExtension/SAWebExtensionHandler.m'} || p.new_file('ScreenActionsWebExtension/SAWebExtensionHandler.m')
    ref2 = p.files.find{|f| f.path=='ScreenActionsWebExtension/WebExtensionBridge.swift'} || p.new_file('ScreenActionsWebExtension/WebExtensionBridge.swift')
    t.source_build_phase.add_file_reference(ref1)
    t.source_build_phase.add_file_reference(ref2)
  end

  %w(EventKit Contacts).each do |fw|
    path="/System/Library/Frameworks/#{fw}.framework"
    ref=p.frameworks_group.files.find{|f| f.path==path} || p.frameworks_group.new_file(path)
    t.frameworks_build_phase.add_file_reference(ref) unless t.frameworks_build_phase.files_references.include?(ref)
  end

  dedupe_sources!(t)
end

p.save
