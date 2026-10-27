#!/usr/bin/env bash
# S17 iOS 真机点击计时：以 integration_test/native_marker_tap_diag_test.dart 为入口编译 Release，
# 由 UI 测试 S14UITests/testS17Taps 读页面命令执行真实点击，结果与截图取回 example/build/s17_ios/。
# 用法：example/tool/s17_ios_run.sh [设备 id]；手机需解锁、亮屏。
set -euo pipefail
dev="${1:-00008101-000110682E90001E}"  # 默认 IP-12-mini
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/build/s17_ios"
rm -rf "$out" && mkdir -p "$out"
cd "$here"
# 写入 FLUTTER_TARGET；Xcode 构建阶段据此编译 Dart 入口（Debug 包无调试器无法启动，用 Release）
flutter build ios --release --config-only -t integration_test/native_marker_tap_diag_test.dart | tail -1
cd ios
xcodebuild test -workspace Runner.xcworkspace -scheme S14 -destination "id=$dev" -configuration Release \
  -derivedDataPath ../build/s17dd -allowProvisioningUpdates \
  -only-testing:S14UITests/S14UITests/testS17Taps \
  -resultBundlePath "$out/result.xcresult" >"$out/xcodebuild.log" 2>&1 || echo "xcodebuild exit $?"
xcrun xcresulttool export attachments --path "$out/result.xcresult" --output-path "$out" >/dev/null 2>&1 || true
grep -E "S17UI|error:|\*\* TEST" "$out/xcodebuild.log" | tail -20
# Dart 的判定结果写在 App 容器 tmp/s17_result.txt
xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer \
  --domain-identifier com.autonavi.amapflutterdemo --source tmp/s17_result.txt \
  --destination "$out/s17_result.txt" >/dev/null 2>&1 || echo "取回结果失败"
cat "$out/s17_result.txt" 2>/dev/null || true
# 恢复默认入口，避免影响日常 flutter run
(cd "$here" && flutter build ios --config-only >/dev/null 2>&1) || true
grep -q "^S17 PASS" "$out/s17_result.txt"
