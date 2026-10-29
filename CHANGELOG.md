## 1.1.0-native.1
2026-10-27（fork 首个版本，基于上游 1.0.15 `5c91d70`）
* 原生点位：`Marker.nativePresentation` 由原生端绘制文字、图标、形状背景（圆形、圆角矩形加箭头、阴影、描边）与图片背景（固定尺寸、九宫格），Dart 不再为每个点生成 PNG
* 图片资源：`AMapWidget.markerImages`（asset / bytes），资源失败时按默认背景降级，asset 按 1s、4s、16s 自动重试并恢复
* 原生选择：`selectable`、`selectedStyle`、`selectedZIndex`、`markerSelection`、`onMarkerSelectionChanged`、`AMapController.setSelectedMarker`；iOS 选中点用高层 Annotation 置顶
* 集合替换：`markerTransition: MarkerTransition.replaceWhenReady(timeout)`，旧点在新点就绪前保持可见、可点击（iOS 同步完成，不等待）
* 诊断计时：`onMarkerUpdateApplied`、`onMarkerTapApplied`（含 c1→c2 期间的 `drawCount`）、`calibrateNativeClock`、`clearNativeMarkerCaches`、标记方块
* 新协议只在使用新能力时启用；未使用时载荷与 1.0.15 相同，旧 `Marker.icon` 行为不变
* 修复（iOS）：`fromBytes` 图标之间切换不更新（F-1）；`didAddAnnotationViews` 类型判断（F-2）
* 修复（Android）：资源失败后重新登记时改用最新来源（与 iOS 一致）
* 已知问题（Android）：100 点冷更新 P95 比旧路径慢约 230ms，更新期间卡顿帧比例高于旧路径（见报告 §6）
* iOS podspec 版本与 Dart 包同步，`AMap3DMap` 精确锁定 10.1.200；`publish_to: none`
* 双端真机验收报告：`docs/superpowers/experiments/2026-10-27-s18/report.md`

## 1.0.15
2025-03-21
* add MapConfiguration and serialize utils
* add compatibility with Color.fromARGB()
* code lint

## 1.0.14
2025-03-12
* code lint

## 1.0.13
2025-03-11
* 升级amap android sdk版本 10.1.200_loc6.4.9_sea9.7.4 | 2025-03-11
* 升级amap iOS sdk版本 10.1.200 | 2024-12-26
* 修复问题：android 构建异常，过期接口 io.flutter.view.FlutterMain 替换
* 修复问题：android 构建异常，过期接口 PluginRegistry.Registrar 替换


## 1.0.12
2024-08-26
* code lint

## 1.0.11
2024-08-25
* 升级amap iOS sdk版本 10.0.900 | 2024-08-23
* code lint

## 1.0.10
2024-08-25
* 移除extension实现机制
* 添加 getMapContentApprovalNumber / getSatelliteImageApprovalNumber（参见example#ShowMapPage）
* 添加 InfoWindowAdapter（参见example#CustomInfoWindowDemoPage）,结合 infoWindowEnable 和 BaseInfoWindowAdapter 自行实现具体逻辑
* permission_handler 11.3.0 -> 11.3.1

## 1.0.9
2024-08-24
* 设置地图语言，支持中文、英文（按SDK描述：1、不能和自定义地图样式同时使用；2、英文状态只在标准地图生效）

## 1.0.8
2024-07-29.
* 升级amap android sdk版本 10.0.800_loc6.4.5_sea9.7.2 | 2024-07-19 

## 1.0.7
2024-07-28.
* Close Issue [#10](https://github.com/kuloud/amap_map/issues/10) 添加Logo位置设置，参见example: map_ui_options.dart

## 1.0.6
2024-06-27.
* 升级amap android sdk版本 V10.0.700_loc6.4.5_sea9.7.2 | 2024-05-13 `看高德更新日志，应该是计划后续版本捆绑loc+search一起更新了`

## 1.0.5
2024-03-20.
* 升级amap android sdk版本 V10.0.600 2024-03-15
* 升级amap ios sdk版本 V10.0.600 2024-03-15
* [example] 适配迁移Gradle声明性插件 https://docs.flutter.dev/release/breaking-changes/flutter-gradle-plugin-apply
* permission_handler 11.1.0 -> 11.3.0

## 1.0.4
2024-01-04.
* 添加 InfoWindowExtension，支持自定义 InfoWindow 样式

## 1.0.3+1
2024-01-03.
* 处理lint，更新文档

## 1.0.3
2024-01-03.
* AMapController 添加 toScreenCoordinate / fromScreenCoordinate，实现屏幕坐标和经纬度的互相转换

## 1.0.2
2023-12-30.
* 增加插件支持

## 1.0.1
2023-12-29.
* 移除 `AMapWidget` 中的 `apiKey` / `privacyStatement` 字段

## 1.0.0+8
2023-12-29.
* 废弃 `AMapWidget` 中的 `apiKey` / `privacyStatement` 字段，使用 `AMapInitializer` 初始化

## 1.0.0+7 - 2023-12-26.
* github action automate publish support

## 1.0.0+6 - 2023-12-26.
* update android sdk version 9.8.3
* update iOS sdk version 9.7.0 

## 1.0.0+1 - 2023-12-22.
* fork from https://pub.dev/packages/amap_flutter_map