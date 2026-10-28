#!/usr/bin/env bash
# S18 iOS 真机：以集成测试为入口编译 Release → 安装 → 启动；
# 没有指定 UI 测试时直接用 devicectl 启动 App，轮询 App tmp/s18/<结果文件> 直到 PASS/FAIL；
# 指定 UI 测试（如 S14UITests/testS18Taps）时由 xcodebuild test 执行真实点击。
# 用法：example/tool/s18_ios_run.sh <入口 dart 文件名> [设备 udid] [UI 测试名]
# 输出：example/build/s18_ios/<入口>/（结果、截图）。手机需解锁、亮屏。
set -euo pipefail
target="${1:?需要入口文件名}"
dev="${2:-00008101-000110682E90001E}"  # 默认 IP-12-mini
uitest="${3:-}"
bundle=com.autonavi.amapflutterdemo
here="$(cd "$(dirname "$0")/.." && pwd)"
name="${target%.dart}"
out="$here/build/s18_ios/$name"
rm -rf "$out" && mkdir -p "$out"
cd "$here"
fetch() {  # 取回 App 容器 tmp/s18 目录
  xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer \
    --domain-identifier "$bundle" --source tmp/s18 --destination "$out/s18" >/dev/null 2>&1 || true
}
if [ -n "$uitest" ]; then
  # UI 测试路径：Xcode 构建阶段按 FLUTTER_TARGET 编译 Dart 入口
  # shellcheck disable=SC2086
  flutter build ios --release --config-only -t "integration_test/$target" ${S18_DEFINES:-} | tail -1
  (cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme S14 -destination "id=$dev" \
    -configuration Release -derivedDataPath ../build/s17dd -allowProvisioningUpdates \
    -only-testing:"$uitest" -resultBundlePath "$out/result.xcresult" >"$out/xcodebuild.log" 2>&1) \
    || echo "xcodebuild exit $?"
  grep -E "S18UI|error:|\*\* TEST" "$out/xcodebuild.log" | tail -20 || true
else
  # S18_DEFINES：可选的额外编译参数（如 --dart-define=COMPARE_COUNTS=200）
  # shellcheck disable=SC2086
  flutter build ios --release -t "integration_test/$target" ${S18_DEFINES:-} | tail -1
  xcrun devicectl device install app --device "$dev" build/ios/iphoneos/Runner.app >/dev/null
  xcrun devicectl device process launch --device "$dev" --terminate-existing "$bundle" >/dev/null
  end=$((SECONDS + ${S18_TIMEOUT:-3600}))
  while [ $SECONDS -lt $end ]; do
    sleep 15
    fetch
    # 只看本入口的结果文件（tmp/s18 里可能还有其他入口上次留下的文件）
    if grep -qsE '^S18 (PASS|FAIL)' "$out/s18/$name.txt"; then break; fi
  done
fi
fetch
# 恢复默认入口，避免影响日常 flutter run
(flutter build ios --config-only >/dev/null 2>&1) || true
grep -sE '^S18 (PASS|FAIL)' "$out/s18/$name.txt" | tail -2 || true
grep -qsE '^S18 PASS' "$out/s18/$name.txt"
