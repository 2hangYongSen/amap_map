# amap_map 示例应用

按功能分组的测试应用，通过 `amap_map: path: ../` 直接使用仓库中的插件源码。首页每一项都有固定测试编号和功能说明，进入页面后点右上角「测试步骤」查看操作与预期结果。

## 运行

1. 在 `lib/const_config.dart` 配置高德 Key。Android Key 必须与包名和构建签名匹配。
2. 运行：

   ```bash
   cd example
   flutter pub get
   flutter run --release -d <设备ID>
   ```

3. 打安装包：`flutter build apk --release`，输出在 `build/app/outputs/flutter-apk/app-release.apk`。

> Release 包目前使用 Demo 调试签名，只用于测试，正式发布需配置自己的签名。

定位权限在进入定位页时才申请，首页不申请电话、存储和定位权限。

Android 真机可以直接打开某个页面（`route` 为测试目录里的 slug）：

```bash
adb shell am start -n com.amap.flutter.amap_map_example/.MainActivity --es route /native-marker-image
```

## 测试目录

| 分组 | 编号 | 内容 |
| --- | --- | --- |
| 基础功能 | AM-D01 / D01.1 / D02 | 基础地图、多实例、事件 |
| 地图配置 | AM-D15～D15.3 | 类型、完整配置、自定义样式、语言 |
| 控件与手势 | AM-D16～D16.3 | UI、手势、缩放范围、地理范围 |
| 定位功能 | AM-D17 | 权限与定位蓝点 |
| 点标记与信息窗口 | AM-E50～E50.6 | 属性、初始与动态点位、图片、自定义窗口、原生点位形状、原生点位图片 |
| 线与面覆盖物 | AM-D20 / D40～D40.2 | 多边形、折线、纹理、大地曲线 |
| 地图控制 | AM-D03 / D04 / D05 | 相机、POI、截图 |
| 性能对照 | AM-P01 | 固定数据 0 / 100 / 200 点 |

编号参考腾讯 Demo 的组织方式，不代表两套 SDK 的功能完全相同。高德插件没有 SurfaceView 模式切换入口。

原生点位示例使用的图片在 `assets/native_marker/`，该子目录已在 `pubspec.yaml` 中单独声明。

## 性能测试

- 基础流畅度先测 AM-D01。AM-P01 使用固定坐标、稳定 ID 和默认 Marker 图标，不代表原生点位方案。
- AM-D02 的日志用独立的 `ValueNotifier` 面板，最多保留 50 条，相机移动日志最多每 250ms 更新一次，记录日志不会重建地图 Widget。
- 对比时使用同一台真机、Release 包、相同视野与刷新率，等底图加载完成再测，避开省电模式和过热。
- 页面不会把回调频率或 Flutter 帧率当作原生地图 FPS。深入测量请用 Profile 模式和 Android Perfetto / System Trace。

## 自动化检查

```bash
flutter test
flutter analyze --no-fatal-infos
```

Widget 测试覆盖菜单、路由、说明窗口和状态逻辑，不能代替 Android / iOS 真机上的显示与性能验收。

## 真机验证记录

### 2026-10-22 Android（BRE-AL80，Release）

- AM-D17：定位蓝点显示，首次定位自动聚焦到当前位置，支持手动回到当前位置。
- AM-E50 / E50.2：添加后图标可见；计数反映 Dart 端期望数量，不代表原生已显示完成。
- AM-E50.3：地图正常创建，起点图标可切换为终点图标。
- AM-E50.4：添加后点击 Marker，Flutter 自定义窗口显示标题。
- AM-D40.1：添加后绿色箭头纹理折线可见。
- AM-D15.2：开关和资源读取已修复，协议测试确认开关与样式字节已发送；但内置样式开关前后真机底图没有明显变化，**视觉验收未通过**。原因尚不确定（旧样式文件、SDK 兼容或授权），需要用高德平台当前导出的有效样式文件对照验证。

根因修复：Android asset 转换器原先读取未初始化的 FlutterLoader，改用 Flutter 引擎提供的 loader；位置转换误把海拔当作纬度校验，已改正；相机移动通道补上了成功应答；定位页会保留地图就绪前收到的位置，权限授予后再创建定位地图。

以上结果只覆盖列出的主要操作，不能代替所有属性组合、iOS 和性能回归。
