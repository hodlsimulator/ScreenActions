require 'xcodeproj'
p = Xcodeproj::Project.open('Screen Actions.xcodeproj')

def target_by_name(p, n); p.targets.find{|t| t.name==n}; end
def file_ref_for(p, path); p.files.find{|f| f.path==path} || p.new_file(path); end
def clear_sources(t); ph=t.source_build_phase; return unless ph; ph.files.dup.each{|bf| ph.remove_build_file(bf)}; end
def add_src(t, ref); ph=t.source_build_phase; ph.add_file_reference(ref) unless ph.files_references.include?(ref); end
def ensure_fw(t,p,name)
  path="/System/Library/Frameworks/#{name}.framework"
  ref=p.frameworks_group.files.find{|f| f.path==path} || p.frameworks_group.new_file(path)
  t.frameworks_build_phase.add_file_reference(ref) unless t.frameworks_build_phase.files_references.include?(ref)
end

p.build_configuration_list.build_configurations.each do |cfg|
  s=cfg.build_settings
  s.delete('PROVISIONING_PROFILE_SPECIFIER')
  s.delete('PROVISIONING_PROFILE')
  s.delete('PROVISIONING_PROFILE_REQUIRED')
end

['ScreenActionsWebExtension','ScreenActionsWebExtension2'].each do |tn|
  t=target_by_name(p, tn); next unless t

  attrs=(p.root_object.attributes['TargetAttributes'] ||= {})
  tattrs=(attrs[t.uuid] ||= {})
  tattrs['ProvisioningStyle']='Automatic'
  tattrs['DevelopmentTeam']='92HEPEJ42Z'

  t.build_configuration_list.build_configurations.each do |cfg|
    s=cfg.build_settings
    s['DEVELOPMENT_TEAM']='92HEPEJ42Z'
    s['CODE_SIGN_STYLE']='Automatic'
    s.delete('PROVISIONING_PROFILE_SPECIFIER')
    s.delete('PROVISIONING_PROFILE')
    s.delete('PROVISIONING_PROFILE_REQUIRED')
    s['CODE_SIGN_IDENTITY']='Apple Development'
    s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES']='YES'
    s['SWIFT_OBJC_BRIDGING_HEADER']=''
    s['CODE_SIGN_ENTITLEMENTS']=(tn=='ScreenActionsWebExtension2' ? 'ScreenActionsWebExtension2/ScreenActionsWebExtension2.entitlements' : 'ScreenActionsWebExtension/ScreenActionsWebExtension.entitlements')
  end

  clear_sources(t)
  if tn=='ScreenActionsWebExtension2'
    add_src(t, file_ref_for(p, 'ScreenActionsWebExtension2/SafariWebExtensionHandler.swift'))
    add_src(t, file_ref_for(p, 'ScreenActionsWebExtension/WebExtensionBridge.swift'))
  else
    add_src(t, file_ref_for(p, 'ScreenActionsWebExtension/SAWebExtensionHandler.m'))
    add_src(t, file_ref_for(p, 'ScreenActionsWebExtension/WebExtensionBridge.swift'))
  end

  ensure_fw(t,p,'EventKit')
  ensure_fw(t,p,'Contacts')
end

p.save
