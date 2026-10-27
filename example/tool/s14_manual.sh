#!/usr/bin/env bash
# S14 手动复测：在真机上以“手动模式”启动某个实验，屏幕顶部用中文提示每一步要做的手势。
# 用法：
#   example/tool/s14_manual.sh install          # 首次：编译 Release 并安装到手机
#   example/tool/s14_manual.sh <I0|I1|I2|I3|I4|X1>  # 启动实验（会先结束旧进程）
#   example/tool/s14_manual.sh pull             # 取回手机上的日志和截图到 example/build/s14_manual/
set -euo pipefail
dev="${S14_DEVICE:-00008101-000110682E90001E}"  # 默认 IP-12-mini，可用环境变量换设备
bundle=com.autonavi.amapflutterdemo
here="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:?参数}" in
  install)
    cd "$here/ios"
    xcodebuild build -workspace Runner.xcworkspace -scheme Runner -configuration Release \
      -destination "id=$dev" -derivedDataPath ../build/s14dd -allowProvisioningUpdates -quiet
    xcrun devicectl device install app --device "$dev" ../build/s14dd/Build/Products/Release-iphoneos/Runner.app
    ;;
  pull)
    out="$here/build/s14_manual" && mkdir -p "$out"
    xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer \
      --domain-identifier "$bundle" --source Documents/s14 --destination "$out"
    ls "$out"
    ;;
  *)
    # 启动参数会写入 NSUserDefaults：-S14Exp 选实验，-S14Manual YES 打开手动提示
    # 偶发 CoreDeviceError 10004（拿不到进程号，App 其实已启动或被旧调试会话占用），自动重试一次
    launch() {
      xcrun devicectl device process launch --device "$dev" --terminate-existing "$bundle" -- \
        -S14Exp "$1" -S14Manual YES
    }
    launch "$1" || { echo "启动报错，2 秒后重试…"; sleep 2; launch "$1"; }
    ;;
esac
