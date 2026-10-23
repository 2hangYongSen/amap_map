// Copyright 2023 kuloud
// Copyright 2020 lbs.amap.com

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

//     http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,

part of '../amap_map.dart';

typedef MapCreatedCallback = void Function(AMapController controller);

///用于展示高德地图的Widget
class AMapWidget extends StatefulWidget {
  /// 初始化时的地图中心点
  final CameraPosition initialCameraPosition;

  /// 地图类型
  final MapType mapType;

  /// 自定义地图样式
  final CustomStyleOptions? customStyleOptions;

  /// 定位小蓝点
  final MyLocationStyleOptions? myLocationStyleOptions;

  /// 缩放级别范围
  final MinMaxZoomPreference? minMaxZoomPreference;

  /// 地图显示范围
  final LatLngBounds? limitBounds;

  /// 显示路况开关
  final bool trafficEnabled;

  /// 地图poi是否允许点击
  final bool touchPoiEnabled;

  /// 是否显示3D建筑物，默认显示
  final bool buildingsEnabled;

  /// 是否显示底图文字标注
  final bool labelsEnabled;

  /// 是否显示指南针
  final bool compassEnabled;

  /// 是否显示比例尺
  final bool scaleEnabled;

  /// 是否支持缩放手势
  final bool zoomGesturesEnabled;

  /// 是否支持滑动手势
  final bool scrollGesturesEnabled;

  ///是否支持旋转手势
  final bool rotateGesturesEnabled;

  ///是否支持倾斜手势
  final bool tiltGesturesEnabled;

  /// logo 位置，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final LogoPosition? logoPosition;

  /// logo 底部间距(px)，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final int? logoBottomMargin;

  /// logo 靠左间距(px)，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final int? logoLeftMargin;

  /// 地图上显示的Marker
  final Set<Marker> markers;

  /// 地图上显示的polyline
  final Set<Polyline> polylines;

  /// 地图上显示的polygon
  final Set<Polygon> polygons;

  /// 地图创建成功的回调, 收到此回调之后才可以操作地图
  final MapCreatedCallback? onMapCreated;

  /// 相机视角持续移动的回调
  final ArgumentCallback<CameraPosition>? onCameraMove;

  /// 相机视角移动结束的回调
  final ArgumentCallback<CameraPosition>? onCameraMoveEnd;

  /// 地图单击事件的回调
  final ArgumentCallback<LatLng>? onTap;

  /// 地图长按事件的回调
  final ArgumentCallback<LatLng>? onLongPress;

  /// 地图POI的点击回调，需要`touchPoiEnabled`true，才能回调
  final ArgumentCallback<AMapPoi>? onPoiTouched;

  ///位置回调
  final ArgumentCallback<AMapLocation>? onLocationChanged;

  ///需要应用到地图上的手势集合
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// 设置地图语言
  final MapLanguage? mapLanguage;

  /// Marker InfoWindow 适配器
  final InfoWindowAdapter? infoWindowAdapter;

  /// 原生点位使用的图片资源；非空时地图启用新协议且不再回退
  final Set<MarkerImageResource> markerImages;

  /// 原生点位错误回调（解码失败、异步校验失败等）
  final ValueChanged<NativeMarkerError>? onNativeMarkerError;

  /// 原生单选配置；为空表示关闭自动选择。非空时地图启用新协议
  final MarkerSelectionOptions? markerSelection;

  /// 选择变化回调。只需把结果写回业务状态，不要在其中调用
  /// `setSelectedMarker`（传入相同 id 不会产生任何效果）
  final ValueChanged<MarkerSelectionChange>? onMarkerSelectionChanged;

  /// 集合替换的过渡策略，默认立即删除（与 1.0.15 一致）
  final MarkerTransition markerTransition;

  /// 创建一个展示高德地图的widget
  ///
  /// 在app首次启动时必须传入高德合规声明配置[privacyStatement],后续如果没有变化不需要重复设置
  /// <li>[privacyStatement.hasContains] 隐私权政策是否包含高德开平隐私权政策</li>
  /// <li>[privacyStatement.hasShow] 是否已经弹窗展示给用户</li>
  /// <li>[privacyStatement.hasAgree] 隐私权政策是否已经取得用户同意</li>
  /// 以上三个值，任何一个为false都会造成地图插件不工作（白屏情况）
  ///
  /// 高德SDK合规使用方案请参考：https://lbs.amap.com/news/sdkhgsy
  ///
  /// [AssertionError] will be thrown if [initialCameraPosition] is null;
  const AMapWidget(
      {super.key,
      this.initialCameraPosition =
          const CameraPosition(target: LatLng(39.909187, 116.397451), zoom: 10),
      this.mapType = MapType.normal,
      this.buildingsEnabled = true,
      this.compassEnabled = false,
      this.labelsEnabled = true,
      this.limitBounds,
      this.minMaxZoomPreference,
      this.rotateGesturesEnabled = true,
      this.scaleEnabled = true,
      this.scrollGesturesEnabled = true,
      this.tiltGesturesEnabled = true,
      this.touchPoiEnabled = true,
      this.trafficEnabled = false,
      this.zoomGesturesEnabled = true,
      this.onMapCreated,
      this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
      this.customStyleOptions,
      this.myLocationStyleOptions,
      this.onCameraMove,
      this.onCameraMoveEnd,
      this.onLocationChanged,
      this.onTap,
      this.onLongPress,
      this.onPoiTouched,
      this.markers = const <Marker>{},
      this.polylines = const <Polyline>{},
      this.polygons = const <Polygon>{},
      this.mapLanguage,
      this.infoWindowAdapter,
      this.logoPosition,
      this.logoBottomMargin,
      this.logoLeftMargin,
      this.markerImages = const <MarkerImageResource>{},
      this.onNativeMarkerError,
      this.markerSelection,
      this.onMarkerSelectionChanged,
      this.markerTransition = const MarkerTransition.immediate()});

  ///
  @override
  State<StatefulWidget> createState() => _MapState();
}

class _MapState extends State<AMapWidget> {
  Map<String, Marker> _markers = <String, Marker>{};
  Map<String, Polyline> _polylines = <String, Polyline>{};
  Map<String, Polygon> _polygons = <String, Polygon>{};
  final Map<String, Widget?> _infoWindows = <String, Widget?>{};

  final Completer<AMapController> _controller = Completer<AMapController>();
  late _AMapOptions _mapOptions;
  late final MarkerSyncQueue _markerQueue;

  // 会话代次：dispose 时递增，异步续体据此判断是否已失效
  int _session = 0;
  AMapController? _readyController;

  // 创建参数只在首次 build 计算，平台视图只在首次创建时使用（R-SYNC-4）
  Map<String, dynamic>? _creationParams;

  Map<String, dynamic> _buildCreationParams() => <String, dynamic>{
        'privacyStatement': AMapInitializer._privacyStatement?.toMap(),
        'apiKey': AMapInitializer._apiKey?.toMap(),
        'initialCameraPosition': widget.initialCameraPosition.toMap(),
        'options': _mapOptions.toMap(),
        // 旧协议只含 markersToAdd；新协议另含 protocolVersion、imagesToAdd
        ..._markerQueue.creationParams,
        'polylinesToAdd': serializeOverlaySet(widget.polylines),
        'polygonsToAdd': serializeOverlaySet(widget.polygons),
      };

  @override
  Widget build(BuildContext context) {
    Widget mapView = _methodChannel.buildView(
      _creationParams ??= _buildCreationParams(),
      widget.gestureRecognizers,
      onPlatformViewCreated,
    );

    return Stack(
      children: <Widget>[mapView, ..._infoWindows.values.nonNulls],
    );
  }

  @override
  void initState() {
    super.initState();
    _mapOptions = _AMapOptions.fromWidget(widget);
    _markerQueue = _createMarkerQueue();
    // 与队列目标一致：初始校验失败时为空
    _markers = keyByMarkerId(_markerQueue.targetMarkers);
    _polygons = keyByPolygonId(widget.polygons);
    _polylines = keyByPolylineId(widget.polylines);

    print('initState AMapWidget');
  }

  @override
  void dispose() {
    // 同步标记会话失效，不等待尚未完成的控制器初始化（R-DART-DISP）
    _session++;
    _markerQueue.dispose();
    // 控制器已就绪就立即取消订阅；未就绪的由 _initForSession 在返回时清理
    _readyController?.disponse();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    print('reassemble AMapWidget');
  }

  @override
  void deactivate() async {
    super.deactivate();
    print('deactivate AMapWidget');
  }

  @override
  void didUpdateWidget(covariant AMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateOptions();
    updateMarkers();
    _updatePolylines();
    _updatePolygons();
  }

  Future<void> onPlatformViewCreated(int id) async {
    // 捕获会话代次：销毁或重建后，迟到的初始化只清理不握手（R-DART-DISP）
    final int session = _session;
    final AMapController? controller = await AMapController._initForSession(
        id, this, () => !mounted || session != _session);
    if (controller == null) {
      return;
    }
    _readyController = controller;
    _controller.complete(controller);
    // 订阅已在控制器构造时建立，之后才确认初始快照或握手（R-INIT-1）
    _markerQueue.attachTransport(controller._markerTransport);

    final MapCreatedCallback? onMapCreated = widget.onMapCreated;
    if (onMapCreated != null) {
      onMapCreated(controller);
    }
  }

  /// 点击分发：先查当前点位，再查过渡中的待删除点（R-DEL-3）
  void onMarkerTap(String markerId) {
    final Marker? marker =
        _markers[markerId] ?? _markerQueue.retiringMarker(markerId);
    if (marker != null) {
      final ArgumentCallback<String>? onTap = marker.onTap;
      if (onTap != null) {
        onTap(markerId);
      }
    }
  }

  void onMarkerDragEnd(String markerId, LatLng position) {
    final Marker? marker = _markers[markerId];
    if (marker != null) {
      final MarkerDragEndCallback? onDragEnd = marker.onDragEnd;
      if (onDragEnd != null) {
        onDragEnd(markerId, position);
      }
    }
  }

  void onPolylineTap(String polylineId) {
    final Polyline? polyline = _polylines[polylineId];
    if (polyline != null) {
      final ArgumentCallback<String>? onTap = polyline.onTap;
      if (onTap != null) {
        onTap(polylineId);
      }
    }
  }

  void _updateOptions() async {
    final _AMapOptions newOptions = _AMapOptions.fromWidget(widget);
    final Map<String, dynamic> updates = _mapOptions._updatesMap(newOptions);
    if (updates.isEmpty) {
      return;
    }
    final AMapController controller = await _controller.future;
    // ignore: unawaited_futures
    controller._updateMapOptions(updates);
    _mapOptions = newOptions;
  }

  /// 把最新点位交给发送队列：合并、无变化不发送（R-SYNC-1/2/5）。
  ///
  /// 校验失败时上报 [ArgumentError]，本次点位更新整体不发送（R-VAL）；
  /// 不向上抛出，避免地图子树被替换成错误组件。
  void updateMarkers() {
    try {
      // 选项先于点位写入，握手后按“选项 → 点位”的顺序发送（R-INIT-7）
      _markerQueue.setOptions(_markerOptions());
      _markerQueue.setTarget(widget.markers, widget.markerImages);
    } on ArgumentError catch (e, s) {
      _reportMarkerError(e, s);
      return;
    }
    _syncLocalMarkers();
  }

  void _reportMarkerError(ArgumentError error, StackTrace stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'amap_map',
      context: ErrorDescription('校验 AMapWidget.markers / markerImages 时'),
    ));
  }

  MarkerSyncOptions _markerOptions() => MarkerSyncOptions(
        selection: widget.markerSelection,
        transition: widget.markerTransition,
      );

  /// 回调总是读取最新的 widget；队列销毁后不会再调用（R-DART-DISP）
  MarkerSyncCallbacks get _markerCallbacks => MarkerSyncCallbacks(
        // 异步校验失败等原生错误只上报，不回退、不重发（R-SYNC-8）
        onNativeError: (NativeMarkerError e) =>
            widget.onNativeMarkerError?.call(e),
        onSelectionChanged: (MarkerSelectionChange c) =>
            widget.onMarkerSelectionChanged?.call(c),
      );

  /// 初始点位校验失败时上报，并先按空集合创建，后续合法更新照常发送
  MarkerSyncQueue _createMarkerQueue() {
    try {
      return MarkerSyncQueue(
        markers: widget.markers,
        images: widget.markerImages,
        options: _markerOptions(),
        onSyncError: _onMarkerSyncError,
        callbacks: _markerCallbacks,
      );
    } on ArgumentError catch (e, s) {
      _reportMarkerError(e, s);
      return MarkerSyncQueue(
          markers: const <Marker>{},
          onSyncError: _onMarkerSyncError,
          callbacks: _markerCallbacks);
    }
  }

  void _onMarkerSyncError(MarkerSyncException error) {
    if (kDebugMode) {
      debugPrint('AMapWidget marker sync: $error');
    }
  }

  /// 本地回调索引与 InfoWindow，沿用原先在控制器就绪后处理的时序
  void _syncLocalMarkers() async {
    final int session = _session;
    await _controller.future;
    if (!mounted || session != _session) {
      return;
    }
    final Set<String> currentIds =
        widget.markers.map((Marker m) => m.id).toSet();
    for (final String markerId in _markers.keys.toList()) {
      if (!currentIds.contains(markerId)) {
        _removeInfoWindow(markerId);
      }
    }
    _markers = keyByMarkerId(widget.markers);

    if (widget.infoWindowAdapter != null) {
      for (final Marker marker in _markers.values) {
        _onInfoWindowUpdate(marker);
      }
    }
  }

  void _updatePolylines() async {
    final AMapController controller = await _controller.future;
    controller._updatePolylines(
        PolylineUpdates.from(_polylines.values.toSet(), widget.polylines));
    _polylines = keyByPolylineId(widget.polylines);
  }

  void _updatePolygons() async {
    final AMapController controller = await _controller.future;
    controller._updatePolygons(
        PolygonUpdates.from(_polygons.values.toSet(), widget.polygons));
    _polygons = keyByPolygonId(widget.polygons);
  }

  void _onInfoWindowUpdate(Marker marker) {
    if (widget.infoWindowAdapter != null) {
      setState(() {
        _infoWindows[marker.id] =
            widget.infoWindowAdapter!.getInfoWindow(context, marker);
      });
    }
  }

  void _removeInfoWindow(String markerId) {
    setState(() {
      _infoWindows.remove(markerId);
    });
  }
}

//高德地图参数设置
class _AMapOptions {
  ///地图类型
  final MapType mapType;

  ///自定义地图样式
  final CustomStyleOptions? customStyleOptions;

  ///定位小蓝点
  final MyLocationStyleOptions? myLocationStyleOptions;

  //缩放级别范围
  final MinMaxZoomPreference? minMaxZoomPreference;

  ///地图显示范围
  final LatLngBounds? limitBounds;

  ///显示路况开关
  final bool? trafficEnabled;

  /// 地图poi是否允许点击
  final bool? touchPoiEnabled;

  ///是否显示3D建筑物
  final bool? buildingsEnabled;

  /// 是否显示底图文字标注，默认显示
  final bool? labelsEnabled;

  ///是否显示指南针
  final bool? compassEnabled;

  ///是否显示比例尺
  final bool? scaleEnabled;

  ///是否支持缩放手势
  final bool? zoomGesturesEnabled;

  ///是否支持滑动手势
  final bool? scrollGesturesEnabled;

  ///是否支持旋转手势
  final bool? rotateGesturesEnabled;

  ///是否支持仰角手势
  final bool? tiltGesturesEnabled;

  /// logo的位置
  final int? logoPosition;

  final int? logoBottomMargin;
  final int? logoLeftMargin;

  final MapLanguage? mapLanguage;

  _AMapOptions(
      {this.mapType = MapType.normal,
      this.buildingsEnabled,
      this.customStyleOptions,
      this.myLocationStyleOptions,
      this.compassEnabled,
      this.labelsEnabled,
      this.limitBounds,
      this.minMaxZoomPreference,
      this.scaleEnabled,
      this.touchPoiEnabled,
      this.trafficEnabled,
      this.rotateGesturesEnabled,
      this.scrollGesturesEnabled,
      this.tiltGesturesEnabled,
      this.zoomGesturesEnabled,
      this.logoPosition,
      this.logoBottomMargin,
      this.logoLeftMargin,
      this.mapLanguage});

  static _AMapOptions fromWidget(AMapWidget map) {
    return _AMapOptions(
      mapType: map.mapType,
      buildingsEnabled: map.buildingsEnabled,
      compassEnabled: map.compassEnabled,
      labelsEnabled: map.labelsEnabled,
      limitBounds: map.limitBounds,
      minMaxZoomPreference: map.minMaxZoomPreference,
      scaleEnabled: map.scaleEnabled,
      touchPoiEnabled: map.touchPoiEnabled,
      trafficEnabled: map.trafficEnabled,
      rotateGesturesEnabled: map.rotateGesturesEnabled,
      scrollGesturesEnabled: map.scrollGesturesEnabled,
      tiltGesturesEnabled: map.tiltGesturesEnabled,
      zoomGesturesEnabled: map.zoomGesturesEnabled,
      customStyleOptions: map.customStyleOptions?.clone(),
      myLocationStyleOptions: map.myLocationStyleOptions?.clone(),
      logoPosition: map.logoPosition?.index,
      logoBottomMargin: map.logoBottomMargin,
      logoLeftMargin: map.logoLeftMargin,
      mapLanguage: map.mapLanguage,
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> optionsMap = <String, dynamic>{};
    void addIfNonNull(String fieldName, dynamic value) {
      if (value != null) {
        optionsMap[fieldName] = value;
      }
    }

    addIfNonNull('mapType', mapType.index);
    addIfNonNull('buildingsEnabled', buildingsEnabled);
    addIfNonNull('customStyleOptions', customStyleOptions?.clone().toMap());
    addIfNonNull('compassEnabled', compassEnabled);
    addIfNonNull('labelsEnabled', labelsEnabled);
    addIfNonNull('limitBounds', limitBounds?.toJson());
    addIfNonNull('minMaxZoomPreference', minMaxZoomPreference?.toJson());
    addIfNonNull('scaleEnabled', scaleEnabled);
    addIfNonNull('touchPoiEnabled', touchPoiEnabled);
    addIfNonNull('trafficEnabled', trafficEnabled);
    addIfNonNull('rotateGesturesEnabled', rotateGesturesEnabled);
    addIfNonNull('scrollGesturesEnabled', scrollGesturesEnabled);
    addIfNonNull('tiltGesturesEnabled', tiltGesturesEnabled);
    addIfNonNull('zoomGesturesEnabled', zoomGesturesEnabled);
    addIfNonNull('myLocationStyle', myLocationStyleOptions?.clone().toMap());
    addIfNonNull('logoPosition', logoPosition);
    addIfNonNull('logoBottomMargin', logoBottomMargin);
    addIfNonNull('logoLeftMargin', logoLeftMargin);
    addIfNonNull('mapLanguage', mapLanguage?.value);
    return optionsMap;
  }

  Map<String, dynamic> _updatesMap(_AMapOptions newOptions) {
    final Map<String, dynamic> prevOptionsMap = toMap();

    return newOptions.toMap()
      ..removeWhere((String key, dynamic value) =>
          (_checkChange(key, prevOptionsMap[key], value)));
  }

  bool _checkChange(String key, dynamic preValue, dynamic newValue) {
    if (key == 'myLocationStyle' || key == 'customStyleOptions') {
      return preValue?.toString() == newValue?.toString();
    } else {
      return preValue == newValue;
    }
  }
}
