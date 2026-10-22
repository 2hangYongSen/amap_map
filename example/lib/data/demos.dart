import 'package:flutter/material.dart';
import 'package:amap_map_example/pages/map/show_map_page.dart';
import 'package:amap_map_example/pages/map/multi_map.dart';
import 'package:amap_map_example/pages/interactive/map_events_page.dart';
import 'package:amap_map_example/pages/map/change_map_type.dart';
import 'package:amap_map_example/pages/map/map_all_config.dart';
import 'package:amap_map_example/pages/map/custom_map_style.dart';
import 'package:amap_map_example/pages/map/change_map_lang.dart';
import 'package:amap_map_example/pages/interactive/map_ui_options.dart';
import 'package:amap_map_example/pages/interactive/map_gestures_options.dart';
import 'package:amap_map_example/pages/map/min_max_zoom.dart';
import 'package:amap_map_example/pages/map/limit_map_bounds.dart';
import 'package:amap_map_example/pages/map/map_my_location.dart';
import 'package:amap_map_example/pages/overlays/marker_config.dart';
import 'package:amap_map_example/pages/overlays/marker_add_with_map.dart';
import 'package:amap_map_example/pages/overlays/marker_add_after_map.dart';
import 'package:amap_map_example/pages/overlays/marker_custom_icon.dart';
import 'package:amap_map_example/pages/overlays/custom_info_window.dart';
import 'package:amap_map_example/pages/overlays/place_polygon.dart';
import 'package:amap_map_example/pages/overlays/place_polyline.dart';
import 'package:amap_map_example/pages/overlays/polyline_texture.dart';
import 'package:amap_map_example/pages/overlays/polyline_geodesic.dart';
import 'package:amap_map_example/pages/interactive/move_camera_demo.dart';
import 'package:amap_map_example/pages/interactive/poi_click_demo.dart';
import 'package:amap_map_example/pages/interactive/snapshot_demo.dart';
import 'package:amap_map_example/pages/interactive/marker_benchmark_page.dart';

enum DemoCategory {
  basic,
  interactive,
  overlay,
  extension;

  String toDisplayTitle() {
    switch (this) {
      case basic:
        return '创建地图';
      case interactive:
        return '与地图交互';
      case overlay:
        return '在地图上绘制';
      case extension:
        return '拓展插件';
    }
  }
}

class Demo {
  const Demo({
    required this.title,
    required this.category,
    required this.subtitle,
    // Parameters below are required for non-study demos.
    this.slug,
    required this.group,
    required this.steps,
    this.configurations = const <DemoConfiguration>[],
  }) : assert(slug != null);

  final String group;
  final String steps;
  final String title;
  final DemoCategory category;
  final String subtitle;
  final String? slug;
  final List<DemoConfiguration> configurations;

  String get describe => '$slug@${category.name}';
}

class DemoConfiguration {
  const DemoConfiguration({required this.buildRoute});
  final WidgetBuilder buildRoute;
}

List<Demo> allDemos() => <Demo>[
      Demo(
          title: 'AM-D01: 基本地图显示',
          category: DemoCategory.basic,
          group: '基础功能',
          subtitle: '底图加载、拖动、缩放；基础流畅度对照',
          steps: '等待地图加载，连续拖动和双指缩放。观察底图、文字与审图号；此页不刷新连续事件日志。',
          slug: 'show-map',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => ShowMapPage())
          ]),
      Demo(
          title: 'AM-D01.1: 地图多实例',
          category: DemoCategory.basic,
          group: '基础功能',
          subtitle: '北京 / 上海双地图独立操作',
          steps: '分别拖动两张地图，确认另一张视野不受影响。返回后重复进入，检查是否黑屏或崩溃。',
          slug: 'multi-map',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const MultiMapDemoPage())
          ]),
      Demo(
          title: 'AM-D02: 地图事件',
          category: DemoCategory.basic,
          group: '基础功能',
          subtitle: '点击、长按、POI、相机事件；日志限频更新',
          steps: '点击、长按、拖动和缩放地图，检查下方事件记录。连续相机事件最多每 250ms 展示一次；这不是帧率统计。',
          slug: 'map-events',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const MapEventsPage())
          ]),
      Demo(
          title: 'AM-D15: 地图类型',
          category: DemoCategory.basic,
          group: '地图配置',
          subtitle: '普通、卫星等地图类型切换',
          steps: '逐一切换地图类型，等待底图加载，确认视野位置保持一致。',
          slug: 'map-type',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => ChangeMapTypePage())
          ]),
      Demo(
          title: 'AM-D15.1: 完整配置',
          category: DemoCategory.basic,
          group: '地图配置',
          subtitle: '路况、建筑、标注等配置组合',
          steps: '逐一操作配置项，并拖动、缩放确认效果。组合开关后返回重进，检查页面是否恢复初始配置。',
          slug: 'all-config',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const AllMapConfigDemoPage())
          ]),
      Demo(
          title: 'AM-D15.2: 自定义地图样式',
          category: DemoCategory.basic,
          group: '地图配置',
          subtitle: '内置样式加载与开关；当前样式视觉效果待验证',
          steps:
              '等待样式资源加载，开关自定义地图并比较同一视野。当前内置样式在测试 Android 设备上未观察到变化，不算验收通过；需用高德平台导出的有效样式文件复测。',
          slug: 'custom-style',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => CustomMapStylePage())
          ]),
      Demo(
          title: 'AM-D15.3: 地图语言',
          category: DemoCategory.basic,
          group: '地图配置',
          subtitle: '地图标注语言切换',
          steps: '切换语言并观察支持多语言的地名标注。',
          slug: 'map-lang',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const ChangeMapLangPage())
          ]),
      Demo(
          title: 'AM-D16: UI 控件',
          category: DemoCategory.basic,
          group: '控件与手势',
          subtitle: '指南针、比例尺与 Logo 位置',
          steps: '切换控件显示；旋转地图验证指南针，缩放地图验证比例尺。',
          slug: 'map-ui',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => MapUIDemoPage())
          ]),
      Demo(
          title: 'AM-D16.1: 手势开关',
          category: DemoCategory.basic,
          group: '控件与手势',
          subtitle: '缩放、拖动、旋转、倾斜手势',
          steps: '分别关闭一种手势并操作地图，确认该手势失效，重新打开后恢复。',
          slug: 'map-gestures',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => GesturesDemoPage())
          ]),
      Demo(
          title: 'AM-D16.2: 缩放范围',
          category: DemoCategory.basic,
          group: '控件与手势',
          subtitle: '最小 / 最大缩放级别',
          steps: '调整缩放限制，再用双指放大缩小，确认无法越过范围。',
          slug: 'min-max-zoom',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MinMaxZoomDemoPage())
          ]),
      Demo(
          title: 'AM-D16.3: 地图显示范围',
          category: DemoCategory.basic,
          group: '控件与手势',
          subtitle: '限制可移动的地理范围',
          steps: '向不同方向拖动地图并缩放，检查地图范围限制。',
          slug: 'limit-map-bounds',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => LimitMapBoundsPage())
          ]),
      Demo(
          title: 'AM-D17: 定位蓝点',
          category: DemoCategory.basic,
          group: '定位功能',
          subtitle: '定位权限、蓝点和定位回调',
          steps: '允许定位权限并打开系统定位，观察蓝点。拒绝权限时不应崩溃，可在系统设置中授权后重进。',
          slug: 'my-location',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const MyLocationPage())
          ]),
      Demo(
          title: 'AM-E50: Marker 属性',
          category: DemoCategory.basic,
          group: '点标记与信息窗口',
          subtitle: '增删、图标、文字、锚点、透明度、旋转',
          steps: '先添加并点击一个 Marker，再修改属性。移除和全部移除后检查修改按钮禁用；重新添加后可继续操作。',
          slug: 'marker-config',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MarkerConfigDemoPage())
          ]),
      Demo(
          title: 'AM-E50.1: 初始点位',
          category: DemoCategory.basic,
          group: '点标记与信息窗口',
          subtitle: '地图创建时加入 10 个 Marker',
          steps: '进入页面检查初始点位，拖动缩放并返回重进，点位数不应重复增长。',
          slug: 'marker-initial',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => MarkerAddWithMapPage())
          ]),
      Demo(
          title: 'AM-E50.2: 动态添加点位',
          category: DemoCategory.basic,
          group: '点标记与信息窗口',
          subtitle: '地图创建后动态添加 Marker',
          steps: '地图就绪后连续添加 Marker，观察新增点位的位置和数量。',
          slug: 'marker-add',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MarkerAddAfterMapPage())
          ]),
      Demo(
          title: 'AM-E50.3: 自定义图标',
          category: DemoCategory.basic,
          group: '点标记与信息窗口',
          subtitle: 'start / end 图片切换',
          steps: '点击更改图标，确认同一个位置的图标在 start / end 之间切换。',
          slug: 'marker-icon',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MarkerCustomIconPage())
          ]),
      Demo(
          title: 'AM-E50.4: 自定义 InfoWindow',
          category: DemoCategory.basic,
          group: '点标记与信息窗口',
          subtitle: 'Flutter 信息窗口与 Marker 选择联动',
          steps: '添加并点击 Marker 显示窗口，更新标题、移动坐标、切换显示。删除后检查窗口消失且修改按钮禁用。',
          slug: 'custom-info-window',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const CustomInfoWindowDemoPage())
          ]),
      Demo(
          title: 'AM-D20: Polygon 多边形',
          category: DemoCategory.basic,
          group: '线与面覆盖物',
          subtitle: '多边形添加、属性修改与删除',
          steps: '添加并选择多边形后修改页面提供的属性，再删除并重新添加。',
          slug: 'polygon',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const PolygonDemoPage())
          ]),
      Demo(
          title: 'AM-D40: Polyline 折线',
          category: DemoCategory.basic,
          group: '线与面覆盖物',
          subtitle: '折线添加、属性修改与删除',
          steps: '添加并选择折线，修改颜色、宽度等属性，检查删除和重新添加。',
          slug: 'polyline',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => const PolylineDemoPage())
          ]),
      Demo(
          title: 'AM-D40.1: 纹理折线',
          category: DemoCategory.basic,
          group: '线与面覆盖物',
          subtitle: '图片纹理绘制折线',
          steps: '查看纹理折线并缩放地图，检查纹理、线宽和接缝。',
          slug: 'polyline-texture',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const PolylineTextureDemoPage())
          ]),
      Demo(
          title: 'AM-D40.2: 大地曲线',
          category: DemoCategory.basic,
          group: '线与面覆盖物',
          subtitle: '跨区域大地曲线显示',
          steps: '查看曲线路径并缩放、移动地图，观察与普通直线的区别。',
          slug: 'polyline-geodesic',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const PolylineGeodesicDemoPage())
          ]),
      Demo(
          title: 'AM-D03: 相机控制',
          category: DemoCategory.basic,
          group: '地图控制',
          subtitle: '移动中心、缩放、旋转与可视范围',
          steps: '依次执行各相机操作，检查目标位置、缩放和动画效果。',
          slug: 'move-camera',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MoveCameraDemoPage())
          ]),
      Demo(
          title: 'AM-D04: POI 点击',
          category: DemoCategory.basic,
          group: '地图控制',
          subtitle: '点击底图 POI 查看名称',
          steps: '放大地图后点击 POI 标注，检查页面显示的名称是否与点击目标一致。',
          slug: 'poi-click',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => PoiClickDemoPage())
          ]),
      Demo(
          title: 'AM-D05: 地图截图',
          category: DemoCategory.basic,
          group: '地图控制',
          subtitle: '截取当前地图并预览',
          steps: '等待地图就绪后截图，检查下方预览。移动地图后再次截图，检查内容更新。',
          slug: 'snapshot',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) => SnapshotPage())
          ]),
      Demo(
          title: 'AM-P01: 点位数量对照',
          category: DemoCategory.basic,
          group: '性能对照',
          subtitle: '固定视野，0 / 100 / 200 个点位',
          steps:
              '使用真机 Release，等待底图加载后分别选择 0、100、200 点，重复相同拖动和缩放。此页不统计 FPS，不刷新连续事件日志；测量请结合原生性能工具。',
          slug: 'marker-benchmark',
          configurations: <DemoConfiguration>[
            DemoConfiguration(
                buildRoute: (BuildContext context) =>
                    const MarkerBenchmarkPage())
          ]),
    ];

Map<String?, Demo> slugToDemo(BuildContext context) => <String?, Demo>{
      for (final Demo demo in allDemos()) demo.slug: demo,
    };
