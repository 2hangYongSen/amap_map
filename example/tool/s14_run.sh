#!/usr/bin/env bash
# S14 iOS SDK 实验：真机执行一个实验，取回日志和截图到 example/build/s14/<exp>/。
# 用法：example/tool/s14_run.sh <I0|I1|I2|I3|I4|X1> [设备 id]
# 前提：已执行 ruby example/tool/s14_setup.rb；手机已解锁、亮屏。
set -euo pipefail
exp="${1:?exp}"
dev="${2:-00008101-000110682E90001E}"  # 默认 IP-12-mini；模拟器传 sim:<名称>
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/build/s14/$exp"
case "$dev" in sim:*) dest="platform=iOS Simulator,id=${dev#sim:},arch=x86_64"; cfg=(-configuration Debug) ;; *) dest="id=$dev"; cfg=(-configuration Release) ;; esac
rm -rf "$out" && mkdir -p "$out"
cd "$here/ios"
# TEST_RUNNER_ 前缀的环境变量会传给 UI 测试进程（去掉前缀）
TEST_RUNNER_S14EXP="$exp" xcodebuild test -workspace Runner.xcworkspace -scheme S14 \
  -destination "$dest" "${cfg[@]}" -derivedDataPath ../build/s14dd -allowProvisioningUpdates \
  -resultBundlePath "$out/result.xcresult" >"$out/xcodebuild.log" 2>&1 || echo "xcodebuild exit $?"
xcrun xcresulttool export attachments --path "$out/result.xcresult" --output-path "$out" >/dev/null 2>&1 || true
# 附件文件名是 UUID，按 manifest 改回附件名
python3 - "$out" <<'PY'
import json, os, sys
d = sys.argv[1]
m = os.path.join(d, 'manifest.json')
if os.path.exists(m):
    for t in json.load(open(m)):
        for a in t.get('attachments', []):
            src = os.path.join(d, a['exportedFileName'])
            name = a.get('suggestedHumanReadableName') or a['exportedFileName']
            if os.path.exists(src):
                os.rename(src, os.path.join(d, name))
PY
ls "$out"
log="$(ls "$out"/*.log 2>/dev/null | grep -v xcodebuild.log | head -1 || true)"
[ -n "$log" ] && cat "$log" || grep -E "S14|error" "$out/xcodebuild.log" | tail -40
