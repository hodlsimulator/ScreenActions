require 'xcodeproj'
require 'find'
p = Xcodeproj::Project.open('Screen Actions.xcodeproj')
app = p.targets.find{|t| t.name=='Screen Actions'}
ext = p.targets.find{|t| t.name=='ScreenActionsWebExtension2'}
if app && ext
  phase = app.copy_files_build_phases.find{|ph| ph.dst_subfolder_spec=='13'} || app.new_copy_files_build_phase
  phase.name = 'Embed Foundation Extensions'
  phase.dst_subfolder_spec = '13'
  pr = ext.product_reference
  phase.add_file_reference(pr) unless phase.files_references.include?(pr)
  app.add_dependency(ext) unless app.dependencies.any?{|d| d.target==ext}
end
if ext
  rph = ext.resources_build_phase
  Find.find('ScreenActionsWebExtension2/Resources'){|path|
    next if File.directory?(path)
    ref = p.files.find{|f| f.path==path} || p.new_file(path)
    rph.add_file_reference(ref) unless rph.files_references.include?(ref)
  }
  sbp = ext.source_build_phase
  seen = {}
  sbp.files.dup.each{|bf|
    r = bf.file_ref; k = r && r.uuid
    if k && seen[k]; sbp.remove_build_file(bf) else seen[k]=true end
  }
end
p.save
