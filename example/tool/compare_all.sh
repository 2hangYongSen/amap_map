#!/usr/bin/env bash
# AM-P02 一键对照测试：跑推送、点击、原生内存、PNG 内存，最后生成 summary.md。
# 用法：example/tool/compare_all.sh <android|ios> [设备 id]
#   环境变量：RUNS（推送每组轮数，默认 10）、COUNTS（点数，默认 200,1000）、
#             MEM_ROUNDS（内存连续推送批数，默认 10）、ONLY（只跑部分场景，默认 "push tap mem_native mem_png"）
#   冒烟：RUNS=1 MEM_ROUNDS=2 COUNTS=200 example/tool/compare_all.sh android <设备>
# 输出：example/build/compare/<平台>_<月日_时分秒>/：各场景原始结果、日志、summary.md。
# 两个平台可各开一个终端同时跑。手机需亮屏、解锁，刷新率在系统设置里锁定。
set -uo pipefail

# 整个脚本包在函数里：bash 先读完函数再执行，运行中改动本文件不影响本次运行
main() {
  plat="${1:?需要平台 android 或 ios}"
  dev="${2:-}"
  runs="${RUNS:-10}" counts="${COUNTS:-200,1000}" mem_rounds="${MEM_ROUNDS:-10}"
  only=" ${ONLY:-push tap mem_native mem_png} "
  here="$(cd "$(dirname "$0")/.." && pwd)"
  dir="$here/build/compare/${plat}_$(date +%m%d_%H%M%S)"
  cd "$here" || exit 1
  local d="--dart-define" push_def="--dart-define=COMPARE_RUNS=$runs --dart-define=COMPARE_COUNTS=$counts"
  case "$plat" in
    android)
      [ -n "$dev" ] || dev="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
      [ -n "$dev" ] || { echo "没有已连接的安卓设备"; exit 1; }
      runner=tool/s18_android_run.sh src=build/s18_android/marker_compare_test
      model="$(adb -s "$dev" shell getprop ro.product.model | tr -d '\r')" ;;
    ios)
      dev="${dev:-00008101-000110682E90001E}"
      runner=tool/s18_ios_run.sh src=build/s18_ios/marker_compare_test
      # 开跑前确认已配对、开发者模式已开，否则每个场景都会白编译一次
      local info
      info="$(xcrun devicectl device info details --device "$dev" 2>&1)" || {
        echo "iOS 设备不可用：$(echo "$info" | grep -m1 -E 'ERROR|error')"; exit 1; }
      echo "$info" | grep -qiE 'developerModeStatus: *enabled' || {
        echo "iOS 设备未开开发者模式：设置 → 隐私与安全性 → 开发者模式"; exit 1; }
      model="$(echo "$info" | awk -F': ' '/marketingName/ {print $2; exit}')"
      model="${model:-iOS}" ;;
    *) echo "平台只能是 android 或 ios"; exit 2 ;;
  esac
  mkdir -p "$dir"  # 设备检查通过后才建目录，避免留下空目录
  echo "设备 ${model}（${dev}），输出 ${dir}"
  # 安卓的推送和点击合成一次运行，少编译一次；iOS 点击要走 UI 测试，只能分开
  if [ "$plat" = android ]; then
    local sc=""
    [[ "$only" == *" push "* ]] && sc="push_off,push_heavy"
    [[ "$only" == *" tap "* ]] && sc="${sc:+$sc,}tap"
    [ -n "$sc" ] && step push_tap 3600 "$push_def $d=COMPARE_SCENARIOS=$sc"
  else
    [[ "$only" == *" push "* ]] && step push 3000 "$push_def $d=COMPARE_SCENARIOS=push_off,push_heavy"
    [[ "$only" == *" tap "* ]] && step tap 1200 "$d=COMPARE_SCENARIOS=tap" S14UITests/S14UITests/testS18Commands
  fi
  for s in native png; do
    [[ "$only" == *" mem_$s "* ]] && step "mem_$s" 1200 \
      "$d=COMPARE_SCENARIOS=mem $d=COMPARE_SCHEME=$s $d=COMPARE_COUNTS=$counts $d=COMPARE_MEM_ROUNDS=$mem_rounds"
  done
  summarize
}

# step <名称> <超时秒> <编译参数> [iOS UI 测试名]：跑一次入口，结果放到 $dir/<名称>/，失败记入 failed.txt
step() {
  local name="$1" t0=$SECONDS args=(marker_compare_test.dart "$dev")
  [ -n "${4:-}" ] && args+=("$4")
  echo "[$(date +%H:%M:%S)] 开始 $name"
  S18_TIMEOUT="$2" S18_DEFINES="$3" "$runner" "${args[@]}" > "$dir/$name.log" 2>&1
  mkdir -p "$dir/$name"
  if [ "$plat" = android ]; then
    cp -r "$src"/. "$dir/$name/" 2>/dev/null
  else  # iOS 的 s18/ 里可能有其他入口的旧文件，只取本入口
    cp "$src/s18/marker_compare_test.txt" "$dir/$name/results.txt" 2>/dev/null
  fi
  local res="$dir/$name/results.txt" why=""
  if [ ! -s "$res" ]; then why="没有结果文件"
  elif ! grep -q '^S18 PASS' "$res"; then why="$(grep -m1 -E '^S18 FAIL' "$res" || tail -1 "$dir/$name.log")"
  fi
  # 编译参数要真的生效：结果头里的轮数应等于 RUNS
  if [[ "$name" == push* ]] && [ -s "$res" ] && ! grep -q "\"runs\":$runs[,}]" "$res" 2>/dev/null; then
    why="${why:+${why}；}结果里的轮数不是 ${runs}，编译参数可能没生效"
  fi
  local took=$(( (SECONDS - t0) / 60 ))
  if [ -z "$why" ]; then echo "[$(date +%H:%M:%S)] $name 通过（${took} 分钟）"
  else echo "[$(date +%H:%M:%S)] ${name} 失败（${took} 分钟）：${why}"; echo "${name}：${why}" >> "$dir/failed.txt"; fi
}

# 汇总所有场景目录，生成 summary.md（AI 写报告只读这一份）
summarize() {
  local inputs=()
  for p in "$dir"/*/; do [ -s "$p/results.txt" ] && inputs+=("${p%/}"); done
  {
    echo "# AM-P02 $plat 汇总"
    echo
    echo "- 时间：$(date '+%Y-%m-%d %H:%M')；设备：${model}；推送每组 ${runs} 轮；点数 ${counts}；内存 ${mem_rounds} 批"
    echo "- 代码版本：$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- ../android ../ios ../lib 2>/dev/null || echo '（插件有未提交改动）')"
    [ -f "$dir/failed.txt" ] && { echo "- 失败场景："; sed 's/^/  - /' "$dir/failed.txt"; }
    echo
    [ ${#inputs[@]} -gt 0 ] && python3 tool/compare_summary.py "${inputs[@]}"
  } > "$dir/summary.md"
  echo "汇总：$dir/summary.md"
  [ ! -f "$dir/failed.txt" ]
}

main "$@"
