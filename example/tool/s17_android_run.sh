#!/usr/bin/env bash
# S17 Android 真机点击计时：编译测试入口 → 安装 → 启动 → 读 logcat 命令执行 input tap。
# 用法：example/tool/s17_android_run.sh [设备 id] [--no-build]
# 设备有 su 时用 Root 安装与点击（MIUI 未开「USB 安装 / 安全设置」的情况），否则用普通 adb。
set -euo pipefail
dev="${1:-z5byp7twhy69tkvs}"
pkg=com.amap.flutter.amap_map_example
here="$(cd "$(dirname "$0")/.." && pwd)"
apk="$here/build/app/outputs/flutter-apk/app-debug.apk"
out="$here/build/s17" && mkdir -p "$out"
cd "$here"
# 有 su 才走 Root：安装绕过 MIUI「USB 安装」拦截、点击绕过注入权限；否则用普通 adb
if adb -s "$dev" shell 'command -v su' 2>/dev/null | grep -q su; then sudo_='su -c'; else sudo_=''; fi
run() { if [ -n "$sudo_" ]; then adb -s "$dev" shell "su -c '$1'"; else adb -s "$dev" shell "$1"; fi; }
if [ "${2:-}" != "--no-build" ]; then
  flutter build apk --debug --target=integration_test/native_marker_tap_diag_test.dart | tail -1
  if [ -n "$sudo_" ]; then
    adb -s "$dev" push "$apk" /data/local/tmp/s17.apk >/dev/null
    run 'pm install -r -t /data/local/tmp/s17.apk && rm -f /data/local/tmp/s17.apk'
  else
    adb -s "$dev" install -r -t "$apk"
  fi
fi
adb -s "$dev" shell am force-stop "$pkg"
adb -s "$dev" logcat -c
adb -s "$dev" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
last=0
end=$((SECONDS + 300))
while [ $SECONDS -lt $end ]; do
  line="$(adb -s "$dev" logcat -d -s flutter:I | grep -E 'S17CMD [0-9]+ ' | tail -1 || true)"
  seq="$(echo "$line" | sed -E 's/.*S17CMD ([0-9]+) .*/\1/')"
  if [ -n "$line" ] && [ "$seq" != "$last" ]; then
    last="$seq"
    op="$(echo "$line" | sed -E 's/.*S17CMD [0-9]+ ([a-z]+).*/\1/')"
    echo "cmd $seq $op"
    [ "$op" = done ] && break
    if [ "$op" = tap ]; then
      xy="$(echo "$line" | sed -E 's/.*S17CMD [0-9]+ tap ([0-9]+),([0-9]+).*/\1 \2/')"
      run "input tap $xy"
    fi
  fi
  sleep 0.3
done
sleep 1
adb -s "$dev" exec-out screencap -p > "$out/s17_android_end.png"
adb -s "$dev" logcat -d -s flutter:I > "$out/flutter.log"
grep -E "S17 (PASS|FAIL|taps)" "$out/flutter.log" | tail -3
grep -q "S17 PASS" "$out/flutter.log"
