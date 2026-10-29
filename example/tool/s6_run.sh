#!/usr/bin/env bash
# S6 Android SDK 实验执行脚本（宿主 Activity 见 android/app/src/debug/.../experiments）。
# 用法：example/tool/s6_run.sh <A1|A2|A3|A4|A5|A6|X1> [额外 am 参数...]
# 结果：example/build/s6/<exp>/ 下的 logcat、设备侧日志与 PNG。
set -euo pipefail
EXP="${1:?exp id}"
shift || true
PKG=com.amap.flutter.amap_map_example
ACT="$PKG/.experiments.ExpHost"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/s6/$EXP${S6_TAG:+_$S6_TAG}"
DEV_DIR="/sdcard/Android/data/$PKG/files/s6"
mkdir -p "$OUT"

if adb shell dumpsys window | grep -q "isKeyguardShowing=true"; then
  echo "设备处于锁屏状态，请先解锁并保持亮屏" >&2; exit 3
fi
adb shell am force-stop "$PKG"
adb shell rm -rf "$DEV_DIR"
adb logcat -c
adb shell am start -W -n "$ACT" --es exp "$EXP" "$@" >/dev/null

# 华为等机型会屏蔽应用 Log.i，以设备侧日志文件为准
log() { adb shell cat "$DEV_DIR/$EXP.log" 2>/dev/null || true; }
# 等待日志中出现某个标记（最多 $2 秒）
wait_for() {
  local pat="$1" sec="${2:-120}" i=0
  until log | grep -q -- "$pat"; do
    sleep 1; i=$((i + 1))
    if [ "$i" -ge "$sec" ]; then echo "timeout waiting $pat" >&2; return 1; fi
    if ! adb shell pidof "$PKG" >/dev/null; then echo "process died" >&2; return 2; fi
  done
}
# 执行日志里尚未执行的 TAP 行（编号大于 $1），返回最后一个编号
do_taps() {
  local from="$1" last="$1"
  while read -r n x y label; do
    if [ "$n" -gt "$from" ]; then
      # </dev/null：防止 adb 吞掉 while 循环的 stdin
      adb shell input tap "$x" "$y" </dev/null; sleep 1.2; last="$n"
    fi
  done < <(log | sed -n 's/.* TAP \([0-9]*\) \([0-9]*\) \([0-9]*\) \(.*\)$/\1 \2 \3 \4/p')
  echo "$last"
}
step() { adb shell am start -n "$ACT" --es step "$1" >/dev/null 2>&1; }

# S6_RECORD=1：全程录屏（screenrecord 单段上限 180s），结束后拉回 OUT/record.mp4
if [ "${S6_RECORD:-0}" = 1 ]; then
  adb shell rm -f /sdcard/s6_record.mp4
  adb shell screenrecord --time-limit 180 /sdcard/s6_record.mp4 </dev/null &
  REC_PID=$!
fi

case "$EXP" in
  A1)
    wait_for READY_FOR_LIFECYCLE 900
    # 20 次前后台切换（回 Home 再回来，触发 TextureView 销毁与 GL 重建）
    for i in $(seq 1 "${S6_CYCLES:-20}"); do
      adb shell input keyevent KEYCODE_HOME; sleep 1.5
      adb shell am start -n "$ACT" >/dev/null 2>&1; sleep 2.5
    done
    # 摘下/挂回 MapView，强制 SurfaceTexture 销毁与 GL 表面重建
    for i in $(seq 1 "${S6_DETACH:-5}"); do
      step detach; sleep 3.5
    done
    # 模拟低内存（onTrimMemory）
    for lv in RUNNING_LOW RUNNING_CRITICAL; do
      adb shell am send-trim-memory "$PKG" "$lv" || true; sleep 3
    done
    adb shell input keyevent KEYCODE_HOME; sleep 1
    adb shell am send-trim-memory "$PKG" COMPLETE || true; sleep 2
    adb shell am start -n "$ACT" >/dev/null 2>&1; sleep 4
    adb shell dumpsys meminfo "$PKG" | sed -n '1,40p' > "$OUT/meminfo.txt"
    # 退出页面触发 onDestroy → 之后回收全部像素
    adb shell input keyevent KEYCODE_BACK; sleep 4
    ;;
  A4)
    # 多阶段：每出现一次 WAIT_TAPS 就执行新的 TAP 行，然后 step=next，直到 DONE
    last=0; k=0
    until log | grep -q DONE; do
      k=$((k + 1))
      until [ "$(log | grep -c WAIT_TAPS)" -ge "$k" ] || log | grep -q DONE; do sleep 1; done
      log | grep -q DONE && break
      last=$(do_taps "$last"); sleep 1
      step next; sleep 1
    done
    ;;
  *)
    wait_for DONE "${S6_TIMEOUT:-600}"
    ;;
esac

if [ -n "${REC_PID:-}" ]; then
  adb shell pkill -INT screenrecord || true
  wait "$REC_PID" 2>/dev/null || true
  sleep 1
  adb pull /sdcard/s6_record.mp4 "$OUT/record.mp4" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/s6_record.mp4
fi
log > "$OUT/device_log.txt"
cp "$OUT/device_log.txt" "$OUT/logcat_s6.txt"
adb logcat -d | grep -iE "recycled bitmap|FATAL EXCEPTION|E AndroidRuntime|Fatal signal|DEBUG   : (signal|backtrace)" > "$OUT/logcat_errors.txt" || true
adb pull "$DEV_DIR/." "$OUT/" >/dev/null 2>&1 || true
echo "process alive: $(adb shell pidof "$PKG" || echo no)" >> "$OUT/logcat_s6.txt"
grep -E "RESULT|VERIFY|ROUND|EV |WARN|EXC" "$OUT/logcat_s6.txt" | sed 's/^.*S6EXP: //' || true
echo "errors: $(wc -l < "$OUT/logcat_errors.txt") lines -> $OUT"
