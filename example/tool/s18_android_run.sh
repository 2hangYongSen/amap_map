#!/usr/bin/env bash
# S18 Android 真机：以集成测试为入口编译 Profile 包 → 安装 → 启动 → 读 logcat 中的 S18CMD 执行主机操作。
# 用法：example/tool/s18_android_run.sh <入口 dart 文件名> [设备 id] [--no-build]
#   例：example/tool/s18_android_run.sh native_marker_test.dart 4GJBB25123025052
# 命令：tap x,y（物理像素）、meminfo 标签、gfxreset、gfxdump 标签、done。
# 输出：example/build/s18_android/<入口>/（flutter.log、结果行、截图、meminfo、gfxinfo）。
set -euo pipefail
target="${1:?需要入口文件名}"
dev="${2:-4GJBB25123025052}"
pkg=com.amap.flutter.amap_map_example
here="$(cd "$(dirname "$0")/.." && pwd)"
apk="$here/build/app/outputs/flutter-apk/app-profile.apk"
out="$here/build/s18_android/${target%.dart}"
rm -rf "$out" && mkdir -p "$out"
cd "$here"
# 有 su 才走 Root（MIUI 未开「USB 安装 / 安全设置」时）；否则用普通 adb
if adb -s "$dev" shell 'command -v su' 2>/dev/null | grep -q su; then root=1; else root=0; fi
run() { if [ "$root" = 1 ]; then adb -s "$dev" shell "su -c '$1'"; else adb -s "$dev" shell "$1"; fi; }
if [ "${3:-}" != "--no-build" ]; then
  flutter build apk --profile --target="integration_test/$target" | tail -1
  if [ "$root" = 1 ]; then
    adb -s "$dev" push "$apk" /data/local/tmp/s18.apk >/dev/null
    run 'pm install -r -t /data/local/tmp/s18.apk && rm -f /data/local/tmp/s18.apk'
  else
    adb -s "$dev" install -r -t "$apk" >/dev/null
  fi
fi
adb -s "$dev" shell am force-stop "$pkg"
adb -s "$dev" logcat -c
adb -s "$dev" logcat -G 16M >/dev/null 2>&1 || true  # 图片按块打印，缓冲要够大
adb -s "$dev" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
# 持续把 flutter 日志落盘（logcat -d 会被缓冲轮转截断）
adb -s "$dev" logcat -v raw -s flutter:I > "$out/flutter.log" &
logpid=$!
trap 'kill $logpid 2>/dev/null || true' EXIT
last=0
end=$((SECONDS + ${S18_TIMEOUT:-3600}))
finished=0
while [ $SECONDS -lt $end ] && [ $finished = 0 ]; do
  # 按序号逐条执行新命令（连续打印的多条命令不能只取最后一条）
  while read -r _ seq op arg; do
    [ "$seq" -le "$last" ] && continue
    last="$seq"
    case "$op" in
      done) echo "cmd $seq done"; finished=1; break ;;
      tap) run "input tap ${arg/,/ }" ;;
      meminfo) adb -s "$dev" shell dumpsys meminfo "$pkg" > "$out/meminfo_$arg.txt" ;;
      gfxreset) adb -s "$dev" shell dumpsys gfxinfo "$pkg" reset >/dev/null ;;
      gfxdump) adb -s "$dev" shell dumpsys gfxinfo "$pkg" > "$out/gfxinfo_$arg.txt" ;;
    esac
  done < <(grep -E '^S18CMD [0-9]+ ' "$out/flutter.log" || true)
  [ $finished = 1 ] && break
  # adb 偶尔瞬时失败：连续 5 次查不到进程才判定退出
  if adb -s "$dev" shell pidof "$pkg" >/dev/null 2>&1; then gone=0; else gone=$((${gone:-0} + 1)); fi
  if [ "${gone:-0}" -ge 5 ]; then echo "进程已退出（崩溃？）"; break; fi
  sleep 0.2
done
sleep 1
kill $logpid 2>/dev/null || true
adb -s "$dev" exec-out screencap -p > "$out/end.png"
# 结果行与分块图片还原
grep -E '^S18R ' "$out/flutter.log" | cut -d' ' -f3- > "$out/results.txt" || true
python3 - "$out" <<'PY'
import base64, collections, os, re, sys
out = sys.argv[1]; parts = collections.defaultdict(dict)
for l in open(os.path.join(out, 'flutter.log'), errors='ignore'):
    m = re.match(r'^S18IMG (\S+) (\d+)/(\d+) (\S+)', l)
    if m: parts[m[1]][int(m[2])] = (int(m[3]), m[4])
for name, p in parts.items():
    n = next(iter(p.values()))[0]
    if len(p) == n:
        open(os.path.join(out, name + '.png'), 'wb').write(base64.b64decode(''.join(p[i][1] for i in range(n))))
    else:
        print('图片不完整', name, len(p), '/', n)
PY
grep -E 'S18 (PASS|FAIL)' "$out/results.txt" | tail -2 || true
grep -q '^S18 PASS' "$out/results.txt"
