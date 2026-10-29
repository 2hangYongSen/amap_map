# amap_map

[![pub package](https://img.shields.io/pub/v/amap_map.svg)](https://pub.dev/packages/amap_map)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

基于[高德开放平台地图 SDK](https://lbs.amap.com/api/) 的 Flutter 插件，支持 Android 与 iOS。

> 本仓库是 [kuloud/amap_map](https://github.com/kuloud/amap_map) 的 fork，在上游基础上增加了**原生点位**（Native Marker）能力，fork 治理见 [FORK.md](FORK.md)。

## 目录

- [特性](#特性)
- [平台与版本](#平台与版本)
- [安装](#安装)
- [快速开始](#快速开始)
- [使用指南](#使用指南)
  - [地图与覆盖物](#地图与覆盖物)
  - [地图控制器](#地图控制器)
  - [原生点位](#原生点位)
- [示例应用](#示例应用)
- [常见问题](#常见问题)
- [开发与测试](#开发与测试)
- [许可证](#许可证)

## 特性

下表列出插件已适配的高德地图能力，除特别注明外 Android 与 iOS 都支持。

| 分类 | 已适配 | 对应接口 |
| --- | --- | --- |
| 地图类型 | 普通、卫星、夜间、导航、公交 | `mapType` |
| 地图样式 | 自定义样式（传入高德控制台下载的 `style.data`、`style_extra.data`） | `customStyleOptions` |
| 语言 | 中文、英文（英文只在普通地图生效，且不能与自定义样式同时用） | `mapLanguage` |
| 图层开关 | 路况、3D 建筑、底图文字标注、POI 可点击 | `trafficEnabled` 等 |
| 控件 | 指南针、比例尺、logo 位置与边距（iOS 由插件模拟） | `compassEnabled` 等 |
| 手势 | 缩放、平移、旋转、倾斜，可分别开关 | `*GesturesEnabled` |
| 范围限制 | 缩放级别范围、地理范围 | `minMaxZoomPreference`、`limitBounds` |
| 相机 | 移到指定位置、缩放、平移、适配范围，可带动画 | `moveCamera` + `CameraUpdate` |
| 地图事件 | 单击、长按、POI 点击、相机移动中与移动结束 | `onTap` 等 |
| 定位 | 定位蓝点样式、位置回调 | `myLocationStyleOptions`、`onLocationChanged` |
| Marker | 位置、图标（默认色、asset、字节）、锚点、旋转、透明度、层级、显隐、拖动、点击 | `Marker` |
| InfoWindow | 标题与摘要、自定义 Widget 气泡 | `infoWindow`、`infoWindowAdapter` |
| 原生点位 | 文字气泡、形状与图片背景、九宫格、原生选择（本 fork 新增，见[原生点位](#原生点位)） | `Marker.nativePresentation` |
| Polyline | 颜色、宽度、透明度、纹理、大地曲线、虚线、拐角与线头样式、点击 | `Polyline` |
| Polygon | 填充色、描边色与宽度、拐角样式 | `Polygon` |
| 工具 | 截图、经纬度与屏幕坐标互转、清理缓存、审图号查询 | `AMapController` |

**暂未适配**：圆（Circle）、热力图、点聚合、海量点、图片与瓦片图层、室内地图，以及搜索、路线规划、导航等地图以外的 SDK。需要时可以在原生端自行接入，或提 Issue。

## 平台与版本

|              | Android                      | iOS      |
| ------------ | ---------------------------- | -------- |
| 高德 SDK     | 10.1.200_loc6.4.9_sea9.7.4   | 10.1.200 |
| 最低系统版本 | API 21                       | 12.0     |

- Dart `>=3.1.5 <4.0.0`，Flutter `>=3.0.0`。

## 安装

本 fork 不发布到 pub.dev（`publish_to: none`），按 git tag 引用；`x_amap_base` 需要显式声明：

```yaml
dependencies:
  amap_map:
    git:
      url: https://github.com/2hangYongSen/amap_map.git
      ref: v1.1.0-native.1
  x_amap_base: ^1.0.3
```

上游版本仍可用 `flutter pub add amap_map` 安装，但不含原生点位。iOS 依赖精确锁定 `AMap3DMap 10.1.200`。

## 快速开始

### 1. 申请 Key

在[高德开放平台](https://lbs.amap.com/)申请 Key：

- Android：[获取 Key](https://lbs.amap.com/api/poi-sdk-android/develop/create-project/get-key/?sug_index=2)，Key 需与包名和签名 SHA1 匹配。
- iOS：[获取 Key](https://lbs.amap.com/api/poi-sdk-ios/develop/create-project/get-key/?sug_index=1)，Key 需与 Bundle ID 匹配。

### 2. 初始化与隐私合规

在 `runApp` 后的**第一个** Widget 中初始化，并在用户同意隐私政策后通知 SDK（[高德合规说明](https://lbs.amap.com/news/sdkhgsy)）：

```dart
import 'package:amap_map/amap_map.dart';
// AMapApiKey、AMapPrivacyStatement 定义在 x_amap_base 中
import 'package:x_amap_base/x_amap_base.dart';

const AMapApiKey apiKey = AMapApiKey(androidKey: '你的 Android Key', iosKey: '你的 iOS Key');

@override
Widget build(BuildContext context) {
  AMapInitializer.init(context, apiKey: apiKey);
  // 用户同意隐私政策后调用；首次启动必须设置，之后无变化不需要重复调用
  AMapInitializer.updatePrivacyAgree(
      const AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true));
  return const MaterialApp(home: MapPage());
}
```

### 3. 显示地图

```dart
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  AMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AMapWidget(
        initialCameraPosition: const CameraPosition(
            target: LatLng(39.909187, 116.397451), zoom: 10),
        // 收到回调后才能通过控制器操作地图
        onMapCreated: (AMapController c) => _controller = c,
      ),
    );
  }
}
```

## 使用指南

### 地图与覆盖物

`AMapWidget` 的常用参数：

| 参数 | 说明 |
| --- | --- |
| `initialCameraPosition` | 初始中心点与缩放级别（必填） |
| `mapType` / `customStyleOptions` / `mapLanguage` | 地图类型、自定义样式、语言 |
| `myLocationStyleOptions` / `onLocationChanged` | 定位蓝点与位置回调 |
| `minMaxZoomPreference` / `limitBounds` | 缩放范围、地理范围 |
| `trafficEnabled` / `buildingsEnabled` / `labelsEnabled` / `touchPoiEnabled` | 路况、3D 建筑、底图标注、POI 可点击 |
| `compassEnabled` / `scaleEnabled` / `logoPosition` | 指南针、比例尺、logo 位置（logo 参数原生只支持 Android，iOS 由插件模拟） |
| `zoomGesturesEnabled` 等 `*GesturesEnabled` | 各类手势开关 |
| `markers` / `polylines` / `polygons` | 覆盖物集合，按 id 差量同步 |
| `infoWindowAdapter` | Marker 自定义 InfoWindow |
| `onMapCreated` | 地图创建完成，返回 `AMapController` |
| `onCameraMove` / `onCameraMoveEnd` / `onTap` / `onLongPress` / `onPoiTouched` | 交互回调 |

完整参数见 [`lib/src/amap_widget.dart`](lib/src/amap_widget.dart) 的 dartdoc。

### 地图控制器

`onMapCreated` 返回的 `AMapController`：

| 方法 | 说明 |
| --- | --- |
| `moveCamera(update, {animated, duration})` | 改变视角；iOS 设置显示区域时不支持 `duration`，固定 350ms |
| `takeSnapshot()` | 地图截图，返回 PNG 字节 |
| `toScreenCoordinate` / `fromScreenCoordinate` | 经纬度与屏幕坐标互转 |
| `clearDisk()` | 清理缓存 |
| `getMapContentApprovalNumber()` / `getSatelliteImageApprovalNumber()` | 审图号 |
| `setSelectedMarker(id)` | 设置原生点位的选中项，传 `null` 取消 |

### 原生点位

给 `Marker` 设置 `nativePresentation` 后，点位由原生端按样式绘制，不再需要 Flutter 先把每个点画成 PNG；旧的 `icon` 用法不受影响。

#### 支持的功能

以下功能 Android 与 iOS 都支持，并已通过双端真机验收。

| 分类 | 功能 |
| --- | --- |
| 内容 | 单行文字、前置图标（`iconId`），两者可单用或组合；文字超出可用宽度时尾部省略为“…” |
| 文字样式 | 字号、字重（w400～w700）、颜色、左 / 中 / 右对齐、内边距 |
| 尺寸 | 自适应文字宽度，或用 `width` / `height` 固定，`minWidth` / `maxWidth` 限制范围 |
| 形状背景 | 圆形、圆角矩形；填充色、描边色与描边宽度 |
| 图片背景 | 固定尺寸、按图片原始尺寸、九宫格拉伸（`capInsets`） |
| 装饰 | 底部居中箭头、单层阴影（形状和图片背景都可以用） |
| 锚点 | 主体中心、箭头尖端、自定义比例 |
| 图片资源 | asset 或字节；加载失败自动降级显示，asset 自动重试，恢复后换回正常外观 |
| 选择 | 点击在原生端切换选中样式，选中点可置顶；支持代码设置选中、点地图空白或重复点击取消 |
| 集合替换 | 整批切换时可保留旧点，等新点就绪后再替换（`replaceWhenReady`） |
| 诊断 | 更新与点击的耗时回执、时钟校准、清缓存，用于性能测试 |
| 兼容 | 同一地图上可与旧的 `icon` 点位混用 |

暂不支持：多行文字、渐变填充、多层阴影、动画。需要渐变或纹理时，用图片背景实现。

#### 性能对比

与“Flutter 端生成 PNG + 缓存”的普通 Marker 对比（P50，无负载）：

| 指标 | Android 原生 | Android PNG | iOS 原生 | iOS PNG |
| --- | --- | --- | --- | --- |
| 200 点全部显示 | 343～440ms | 1466～1501ms | 137ms | 411ms |
| 1000 点全部显示 | 1967～4466ms | 8642～8811ms | 457ms | 2451ms |
| 点击到选中 | 10.6～12.4ms | 18.6～19.4ms | 3.4ms | 34.0ms |
| 1000 点内存峰值 | 332～354MB | 487～506MB | 225MB | 461MB |

- 测试设备：Android 华为 BRE-AL80（60Hz，Profile），iOS iPhone 12 mini（60Hz，Release）。Android 有两次运行，给出范围；内存 Android 为 PSS，iOS 为 RSS。
- 200 点以内两种方案推送时丢帧相当。1000 点时高德 SDK 放点会占用主线程约 0.35 秒，建议同屏点数控制在 200 以内，更多时用聚合或只加载屏幕内的点。
- Android 的 PNG 方案清空点位后内存几乎不回落（旧路径生成的位图没有回收），原生方案没有这个问题。

#### 基本用法

```dart
Marker(
  markerId: 'p1',
  position: const LatLng(39.909187, 116.397451),
  nativePresentation: const NativeMarkerPresentation(
    content: NativeMarkerContent(text: '¥3000'),
    anchorType: NativeMarkerAnchorType.arrowTip, // 箭头尖端落在坐标上
    style: NativeMarkerStyle(
      background: NativeMarkerShapeBackground.roundedRect(
          fillColor: Color(0xFFFFFFFF), cornerRadius: 6),
      textColor: Color(0xFFE53935),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      maxWidth: 96, // 超出时尾部省略
      arrow: NativeMarkerArrow(width: 10, height: 6),
      shadow: NativeMarkerShadow(
          color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
    ),
  ),
)
```

- 内容为单行文字和可选的前置图标（`iconId`），两者至少有一个；文字不能含换行。
- 锚点：`bodyCenter`（主体中心，默认）、`arrowTip`（箭头尖端）、`custom`（相对主体框的 0～1 比例）。
- 样式在 Dart 端同步校验，非法时抛 `ArgumentError`，本次更新整体不发送。

#### 图片资源

图片背景和图标引用的资源通过 `AMapWidget.markerImages` 注册，点位里只写资源 id：

```dart
const MarkerImageResource bubble = MarkerImageResource.asset(
    id: 'bubble', assetName: 'assets/bubble.png', pixelRatio: 2);
final MarkerImageResource icon =
    MarkerImageResource.bytes(pngBytes, pixelRatio: 2); // 需缓存，勿每次 build 创建

AMapWidget(
  markers: markers,
  markerImages: {bubble, icon},
  onNativeMarkerError: (NativeMarkerError e) => debugPrint('${e.code} ${e.message}'),
)
```

- `pixelRatio` 表示图片的像素密度，逻辑尺寸 = 像素尺寸 / `pixelRatio`。
- `bytes` 资源在构造时复制字节并计算摘要，内容或像素比变化会得到新 id。
- 资源加载完成前点位不上图；加载失败时按降级规则显示并回调 `imageDecodeFailed`：背景失败用白色圆角默认背景、图标失败则省略图标，文字保留；背景和图标都失败且没有文字时不显示。asset 资源失败后自动重试，恢复后点位自动换回正常外观。
- asset 放在子目录时，需要在 `pubspec.yaml` 中单独声明该目录（Flutter 的目录声明不包含子目录），否则资源一直处于加载中。

#### 选择背景类型

| 设计 | 推荐写法 |
| --- | --- |
| 纯色填充、纯色描边、单层阴影 | `NativeMarkerShapeBackground`：主体与箭头是同一条路径，没有接缝，无需加载资源 |
| 渐变、纹理、装饰边框，且文字长度不固定 | `NativeMarkerImageBackground` + `capInsets`（九宫格） |
| 固定外形的图片（如自带箭头的图钉） | `NativeMarkerImageBackground` + `size`，不配 `arrow`，用 `custom` 锚点指向尖端 |

#### 九宫格（`capInsets`）

九宫格让同一张图适配不同长度的文字：图片按 `capInsets` 切成 9 块，**四角不拉伸，四边单向拉伸，中间双向拉伸**，圆角和边框在各种宽度下保持不变。

```dart
NativeMarkerStyle(
  background: NativeMarkerImageBackground(
    imageId: 'bubble',               // 96x72 像素、pixelRatio 2，即逻辑 48x36
    capInsets: EdgeInsets.all(10),   // 左右 10+10 < 48，上下 10+10 < 36
  ),
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  arrow: NativeMarkerArrow(width: 10, height: 6, color: Color(0xFFFF7043)),
)
```

- **单位**：`capInsets` 是逻辑像素，原生端乘以资源的 `pixelRatio` 换算成图片像素。
- **取值**：左右之和必须小于图片逻辑宽，上下之和必须小于逻辑高。图片尺寸要等资源加载完成才知道，超限时该点按默认背景显示，并回调一次 `invalidConfig`。
- **尺寸**：配置 `capInsets` 后，宽高与圆角矩形的计算规则相同（文字宽 + `padding`，受 `width` / `minWidth` / `maxWidth` 约束），不使用图片尺寸。
- **只拉伸不平铺**：中间区域的图案会被拉变形，装饰应放在四角。
- **箭头**：不要画进图片底边中间，否则会被拉宽。用 `NativeMarkerArrow` 单独绘制，并显式指定 `color`；图片底边颜色需与 `arrow.color` 一致，才能和主体接成一体。

#### 原生选择

给点位设置 `selectable: true` 和 `selectedStyle`，再给地图配置 `markerSelection`，点击即可在原生端切换选中外观，不需要 Dart 回传重建：

```dart
AMapWidget(
  markers: markers, // 点位：selectable: true，可选 selectedZIndex 让选中点置顶
  markerSelection: const MarkerSelectionOptions(), // 点地图空白处、重复点击都会取消
  onMarkerSelectionChanged: (MarkerSelectionChange c) =>
      setState(() => _selectedId = c.selectedId), // 只写回业务状态
)
```

- 点击时先回调 `onMarkerSelectionChanged`，再回调 `Marker.onTap`；非 `selectable` 的点只回调 `onTap`，选择不变。
- 代码中切换用 `controller.setSelectedMarker(id)`；传入当前已选中的 id 不产生任何效果，在回调里回写不会循环。
- 选中点被删除后选择保留，重新加入时自动恢复高亮；改为 `selectable: false` 时取消选择，原因为 `invalidated`。
- 点击气泡可能比调用 `setSelectedMarker` 更晚切换外观：SDK 点击路径需要等待排除双击，详见[点位选择延迟](#marker-selection-latency)。

#### 集合替换过渡

整批切换图层时，默认（`MarkerTransition.immediate()`）旧点立即删除，新点绘制完成后一起出现，Android 上中间会短暂没有点（200 点约 0.4 秒）。改用 `replaceWhenReady` 后，旧点保持可见、可点击，直到新点全部显示或超时：

```dart
markerTransition: const MarkerTransition.replaceWhenReady(
    timeout: Duration(milliseconds: 1000)), // Android 建议值
```

只删除、不新增的更新（例如清空筛选）仍立即删除。

`timeout` 只对 Android 生效。iOS 上新点在本次更新中同步显示，替换不会缺点，所以直接删除旧点，不等待超时。

#### 字重（Android）

`fontWeight` 只允许 w400 / w500 / w600 / w700。Android API 28 及以上按精确字重绘制；低于 API 28 时系统字体只有常规和粗体两档：w400、w500 显示为常规，w600、w700 显示为粗体。

#### 诊断计时

给 `onMarkerUpdateApplied` 或 `onMarkerTapApplied` 传入回调即开启诊断（两者都为空时原生不发任何回执）。开启后会启用新协议，并在地图左上角显示 8×8 的标记方块，颜色按更新轮换，用于录屏对齐。

```dart
AMapWidget(
  markers: markers,
  onMarkerUpdateApplied: (MarkerUpdateReport r) =>
      debugPrint('t2→t4 ${r.t2ToT4Ms}ms，绘制 ${r.drawCount}'), // 原生同一时钟
  onMarkerTapApplied: (MarkerTapReport t) =>
      debugPrint('点击 c1→c2 ${t.c1ToC2Ms}ms（${t.path.name}）'),
)
```

- `controller.calibrateNativeClock()` 估计 Dart 与原生时钟的偏移，`arrivalToAppliedMs` 估算“数据到达 → 原生应用完成”；结果是时钟校准估算，带不确定区间。
- `controller.clearNativeMarkerCaches()` 用于冷测试前清缓存。诊断关闭时这两个方法抛 `PlatformException`。
- 回执中的时间不等于“屏幕已显示”，实际显示时间需要录屏核对。仅建议在调试和性能测试中开启。

## 示例应用

[`example/`](example) 是按功能分组的测试应用，每个页面带测试编号和「测试步骤」说明，运行方式见 [example/README.md](example/README.md)。

<img src="https://github.com/kuloud/amap_map/raw/main/showcase/Simulator%20Screenshot%20-%20iPhone%2015%20Pro%20Max%20-%202024-01-03%20at%2017.18.55.png" width="30%"/>

## 常见问题

**Android 的 targetSdkVersion ≥ 30 时，从地图页返回闪退**

在 `AndroidManifest.xml` 的 `application` 上关闭指针标记，参见 [Tagged Pointers](https://source.android.com/devices/tech/debug/tagged-pointers)：

```xml
<application android:allowNativeHeapPointerTagging="false">
    ...
</application>
```

<a id="marker-selection-latency"></a>

**点位选择延迟：为什么点击气泡比 Flutter 按钮调用 API 慢（iOS / Android）**

两端高德 SDK 的点位点击路径都会先等待排除双击，再通知插件处理单击；`setSelectedMarker` 直接提交选择，跳过地图手势识别阶段。这个差异可以解释 AM-E50.7 示例中，点击气泡切换选中态有明显延迟，而按“选中 p2 / 取消选择”更快的现象。

| 入口 | 执行路径 |
| --- | --- |
| 点击气泡 | 触摸传递到地图 → SDK 等待排除双击 → 点位点击回调 → 原生选择与外观更新 |
| Flutter 按钮 | `setSelectedMarker` → Dart 命令队列 / MethodChannel → 原生选择与外观更新 |

两种入口共用后面的选择实现，点击路径不依赖 Dart 的 `Marker.onTap` 回传选择命令：

- iOS：[`didAnnotationViewTapped`](ios/Classes/AMapViewController.m) → `onMarkerTap` → `selectionOnMarkerTap`；它和 API 的 `setSelectedFromArgs` 都进入 [`commitSelection` → `syncTopAnnotation`](ios/Classes/OverlayController/AMapMarkerController+Selection.m)。
- Android：[`onMarkerClick`](android/src/main/java/com/amap/flutter/map/overlays/marker/MarkersController.java) → `nativeManager.onMarkerTap`；它和 API 的 `setSelected` 都进入 [`commit` → `renderer.selectionChanged`](android/src/main/java/com/amap/flutter/map/overlays/marker/nativemarker/NativeMarkerManager.java)。

以下证据于 **2026-10-27** 核对，适用于 [Android 依赖](android/build.gradle) `10.1.200_loc6.4.9_sea9.7.4` 和 [iOS 示例锁定依赖](example/ios/Podfile.lock) `AMap3DMap 10.1.200`。SDK 内部符号及实现可能随版本改变。

1. **Android SDK 字节码与系统源码。** 对 [Maven Central 同版本 SDK JAR](https://repo.maven.apache.org/maven2/com/amap/api/3dmap-location-search/10.1.200_loc6.4.9_sea9.7.4/3dmap-location-search-10.1.200_loc6.4.9_sea9.7.4.jar)提取 `.class` 后执行 `javap -p -c`，可见 `com.amap.api.col.3sl.ab`（`GlMapGestureDetector.java`）注册了 `GestureDetector.setOnDoubleTapListener`。其内部类 `ab$a.onSingleTapUp()` 直接返回 `false`；`onSingleTapConfirmed()` 才调用 `IAMapDelegate.onSingleTapConfirmed()`。实现类 `com.amap.api.col.3sl.m` 在此方法中调用 `e(MotionEvent)`，进行 Marker 命中检测并调用 `OnMarkerClickListener.onMarkerClick()`。因此，插件收到的点位点击已经经过单击确认阶段。[Android 官方文档][tap-android-api]明确说明，`onSingleTapConfirmed` 只有在确认第一次点击不会被第二次点击组成双击后才调用。[AOSP `GestureDetector`][tap-android-source]的执行代码也在首次 `ACTION_DOWN` 时安排 `sendEmptyMessageDelayed(TAP, DOUBLE_TAP_TIMEOUT)`，之后才分发单击确认。超时取自 `ViewConfiguration.getDoubleTapTimeout()`；[AOSP 默认常量为 300ms][tap-android-timeout]，系统配置可能覆盖它，不能表述为“松手后固定等待 300ms”。
2. **iOS SDK ARM64 二进制与 UIKit 契约。** 对已安装的 `example/ios/Pods/AMap3DMap/MAMapKit.framework/MAMapKit` 提取 ARM64 静态库及 `MAMapKit-arm64-master.o`，用 `llvm-objdump -dr` 检查指令和重定位符号：`-[MAMapView initGesture]` 在 `0x8f8f4` 将 `_zoomInGestureRecognizer` 的 `numberOfTapsRequired` 设为 `2`，在 `0x8fb04` 让 `_singleTapGestureRecognizer` 调用 `requireGestureRecognizerToFail:`，参数为该双击放大识别器；`-[MAMapView singleTapGesture:]` 在 `0x86200` 调用 `mapView:didAnnotationViewTapped:`。这证明点位点击回调位于等待双击失败的单击路径中。[Apple 官方文档][tap-apple-api]说明，这种依赖会延迟当前识别器离开 `possible` 状态，直到另一个识别器失败，并直接以“单击等待双击失败”为例。

iOS 上述二进制行为可概括为以下等价代码（非高德公开源码）：

```objc
_zoomInGestureRecognizer.numberOfTapsRequired = 2;
[_singleTapGestureRecognizer requireGestureRecognizerToFail:_zoomInGestureRecognizer];
// singleTapGesture: 确认后再通知 mapView:didAnnotationViewTapped:
```

Flutter 的触摸仲裁是另一个阶段。[引擎 `FlutterPlatformViews.mm`][tap-flutter-source]中，`releaseGesture` 直接把延迟识别器设为 `UIGestureRecognizerStateFailed`；`WaitUntilTouchesEnded` 策略分支位于 `blockGesture` 中。因此不能只凭本插件注册时使用的策略名称断定它造成固定延迟，改用 `EagerGestureRecognizer` 也不会自动移除高德 SDK 内部的双击等待。

社区与博客旁证：

- [Mapbox Flutter #796][tap-mapbox-issue]报告 iOS / Android 均存在约半秒的地图点击回调延迟，贡献者认为与等待双击超时有关。这是其他 SDK 的案例，只作旁证，不用于证明高德的具体实现或耗时。
- [Hacking with Swift：`require(toFail:)`][tap-swift-blog]展示手势识别器之间的失败依赖，可辅助理解 iOS 的等待机制。

**验证边界：** 本次确认的是 SDK 等待机制和调用链，没有对当前两端设备进行分段计时，不能断言全部可感知延迟都来自双击识别，也不能把默认超时当作实测耗时或保证外观更新只需几毫秒。定位具体耗时时，应记录“原生收到触摸 → SDK 点位点击回调 → 外观更新提交”的时间点；若要测到用户看到变化，还需测量实际帧呈现。API 与点击应交替切换同一点的选中 / 未选中状态，避免把重复选择同一 id 的无操作当作快速更新。

[tap-android-api]: https://developer.android.com/reference/android/view/GestureDetector.OnDoubleTapListener#onSingleTapConfirmed(android.view.MotionEvent)
[tap-android-source]: https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/view/GestureDetector.java
[tap-android-timeout]: https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/view/ViewConfiguration.java
[tap-apple-api]: https://developer.apple.com/documentation/uikit/uigesturerecognizer/require(tofail:)
[tap-flutter-source]: https://github.com/flutter/flutter/blob/ff37bef603469fb030f2b72995ab929ccfc227f0/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViews.mm
[tap-mapbox-issue]: https://github.com/mapbox/mapbox-maps-flutter/issues/796#issuecomment-2615576297
[tap-swift-blog]: https://www.hackingwithswift.com/example-code/uikit/how-to-make-gesture-recognizers-work-together-using-requiretofail

**模拟器在 `com.amap.api.col.3sl.dl$b.createContext(GlesUtility.java:73)` 闪退**

把模拟器的图形加速模式切换为 `Software`，参见 [Issue #27](https://github.com/kuloud/amap_map/issues/27)。

## 开发与测试

### 单元测试

```bash
flutter test                                                  # 插件 Dart 单测
(cd example && flutter test)                                  # 示例应用 Widget 测试
(cd example/android && ./gradlew :amap_map:testDebugUnitTest) # Android JVM 单测
```

iOS XCTest 在 Xcode 中打开 `example/ios/Runner.xcworkspace`，运行 `RunnerTests`。

### 真机集成测试

需要已连接的设备，手机亮屏、解锁。结果输出到 `example/build/s18_android/`、`example/build/s18_ios/`，属于临时目录，可能被清理。

```bash
cd example
tool/s18_android_run.sh native_marker_test.dart <设备 id>       # 资源恢复、页面进出、旧路径回归
tool/s18_android_run.sh native_marker_tap_test.dart <设备 id>   # 真实点击（主机 adb input tap）
tool/s18_android_run.sh native_marker_perf_test.dart <设备 id>  # 性能场景
tool/s18_ios_run.sh native_marker_test.dart <udid>
tool/s18_ios_run.sh native_marker_tap_test.dart <udid> S14UITests/S14UITests/testS18Commands
tool/s18_ios_run.sh native_marker_perf_test.dart <udid>
```

### 原生点位与 PNG 对比测试

一条命令跑完推送、点击、两种方案的内存，结束后在 `example/build/compare/<平台>_<时间>/summary.md` 生成汇总。两个平台可各开一个终端同时跑。

```bash
cd example
tool/compare_all.sh android <设备 id>   # 默认推送 10 轮、200 与 1000 点、内存 10 批
tool/compare_all.sh ios <udid>
RUNS=1 MEM_ROUNDS=2 COUNTS=200 tool/compare_all.sh android <设备 id>   # 冒烟
ONLY="tap mem_png" tool/compare_all.sh android <设备 id>               # 只跑部分场景
```

Android 需要在系统设置中锁定屏幕刷新率。

### 提交前检查

提交前确认 `flutter analyze` 没有新增问题。版本记录见 [CHANGELOG.md](CHANGELOG.md)，问题反馈请提交 [Issue](https://github.com/kuloud/amap_map/issues)。

## 许可证

[Apache License 2.0](LICENSE)
