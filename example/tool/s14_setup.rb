# S14：把实验源码加入 Runner target，新增 S14UITests（UI 测试）target 和共享 scheme S14。
# 可重复执行（已存在的条目会跳过）。用法：ruby example/tool/s14_setup.rb
require 'xcodeproj'

root = File.expand_path('../ios', __dir__)
proj = Xcodeproj::Project.open(File.join(root, 'Runner.xcodeproj'))
runner = proj.targets.find { |t| t.name == 'Runner' }
team = runner.build_configurations.first.build_settings['DEVELOPMENT_TEAM']

# 1. 实验源码 → Runner
group = proj.main_group['Runner']['Experiments'] || proj.main_group['Runner'].new_group('Experiments', 'Experiments')
Dir[File.join(root, 'Runner/Experiments/*.{h,m}')].sort.each do |f|
  name = File.basename(f)
  ref = group.files.find { |r| r.path == name } || group.new_file(name)
  runner.add_file_references([ref]) if name.end_with?('.m') && runner.source_build_phase.files_references.none? { |r| r == ref }
end

# 2. UI 测试 target
ui = proj.targets.find { |t| t.name == 'S14UITests' }
unless ui
  ui = proj.new_target(:ui_test_bundle, 'S14UITests', :ios, '13.0')
  ui.add_dependency(runner)
end
ui.build_configurations.each do |c|
    s = c.build_settings
    s['PRODUCT_NAME'] = '$(TARGET_NAME)' # 工程级没有 PRODUCT_NAME，缺了会生成 "-Runner.app"
    s['TEST_TARGET_NAME'] = 'Runner'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.autonavi.amapflutterdemo.S14UITests'
    s['DEVELOPMENT_TEAM'] = team
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['CLANG_ENABLE_OBJC_ARC'] = 'YES'
end
unless ui.source_build_phase.files_references.any? { |r| r.path == 'S14UITests.m' }
  ugroup = proj.main_group['S14UITests'] || proj.main_group.new_group('S14UITests', 'S14UITests')
  ref = ugroup.files.find { |r| r.path == 'S14UITests.m' } || ugroup.new_file('S14UITests.m')
  ui.add_file_references([ref])
end
proj.save

# 3. 共享 scheme：只测 S14UITests，不改动 Runner scheme
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(runner)
scheme.add_test_target(ui)
scheme.set_launch_target(runner)
scheme.test_action.build_configuration = 'Debug' # 真机由 s14_run.sh 传 -configuration Release（测帧率）
scheme.save_as(proj.path, 'S14', true)
puts 'ok'
