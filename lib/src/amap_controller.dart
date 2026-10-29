// Copyright 2023-2024 kuloud
// Copyright 2020 lbs.amap.com
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,

part of '../amap_map.dart';

final MethodChannelAMapFlutterMap _methodChannel =
    AMapFlutterPlatform.instance as MethodChannelAMapFlutterMap;

/// 地图通信中心
class AMapController {
  final int mapId;
  final _MapState _mapState;

  AMapController._(CameraPosition initCameraPosition, this._mapState,
      {required this.mapId}) {
    _connectStreams(mapId);
  }

  // 已建立的事件订阅，销毁时统一取消（R-DART-DISP）
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  bool _disposed = false;

  ///根据传入的id初始化[AMapController]
  /// 主要用于在[AMapWidget]初始化时在[AMapWidget.onMapCreated]中初始化controller
  static Future<AMapController> init(
    int id,
    CameraPosition initialCameration,
    dynamic mapState,
  ) async {
    await _methodChannel.init(id);
    return AMapController._(
      initialCameration,
      mapState,
      mapId: id,
    );
  }

  /// 供 [AMapWidget] 使用：`map#waitForMap` 返回后若会话已失效，
  /// 只清理通道、不建立订阅，返回 null（R-DART-DISP）。
  static Future<AMapController?> _initForSession(
      int id, _MapState state, bool Function() isStale) async {
    await _methodChannel.init(id);
    if (isStale()) {
      _methodChannel.dispose(id: id);
      return null;
    }
    return AMapController._(state.widget.initialCameraPosition, state,
        mapId: id);
  }

  ///只用于测试
  ///用于与native的通信
  @visibleForTesting
  MethodChannel get channel {
    return _methodChannel.channel(mapId);
  }

  void _connectStreams(int mapId) {
    // 记录订阅，销毁时统一取消
    void keep(StreamSubscription<dynamic> s) => _subscriptions.add(s);

    keep(_methodChannel.onLocationChanged(mapId: mapId).listen(
        (LocationChangedEvent e) =>
            _mapState.widget.onLocationChanged?.call(e.value)));

    keep(_methodChannel.onCameraMove(mapId: mapId).listen((CameraMoveEvent e) {
      _mapState.widget.onCameraMove?.call(e.value);
      if (_mapState.widget.infoWindowAdapter != null) {
        _mapState.updateMarkers();
      }
    }));

    keep(_methodChannel
        .onCameraMoveEnd(mapId: mapId)
        .listen((CameraMoveEndEvent e) {
      _mapState.widget.onCameraMoveEnd?.call(e.value);
    }));
    keep(_methodChannel
        .onMapTap(mapId: mapId)
        .listen(((MapTapEvent e) => _mapState.widget.onTap?.call(e.value))));
    keep(_methodChannel
        .onMapLongPress(mapId: mapId)
        .listen(((MapLongPressEvent e) {
      _mapState.widget.onLongPress?.call(e.value);
    })));

    keep(_methodChannel.onPoiTouched(mapId: mapId).listen(((MapPoiTouchEvent e) {
      _mapState.widget.onPoiTouched?.call(e.value);
    })));

    keep(_methodChannel.onMarkerTap(mapId: mapId).listen((MarkerTapEvent e) {
      _mapState.onMarkerTap(e.value);
    }));

    keep(_methodChannel
        .onMarkerDragEnd(mapId: mapId)
        .listen((MarkerDragEndEvent e) {
      _mapState.onMarkerDragEnd(e.value, e.position);
    }));

    keep(_methodChannel.onPolylineTap(mapId: mapId).listen((PolylineTapEvent e) {
      _mapState.onPolylineTap(e.value);
    }));

    // 新协议事件交给队列：握手前暂存，按 eventSeq 去重（R-INIT-4/5）
    keep(_methodChannel
        .onMarkerProtocolEvent(mapId: mapId)
        .listen((MarkerProtocolEvent e) {
      _mapState._markerQueue.handleMessage(e.value);
    }));
  }

  /// 发送队列使用的通道出口
  MarkerSyncTransport get _markerTransport => _ControllerMarkerTransport(this);

  /// 取消订阅并释放通道；幂等（R-DART-DISP）
  void disponse() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final StreamSubscription<dynamic> s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _methodChannel.dispose(id: mapId);
  }

  /// 设置原生选中点，返回原生提交后的 selectionRevision。
  ///
  /// 此 API 跳过地图 SDK 点击路径的双击判定等待，共用原生选择更新逻辑；
  /// 不保证即时呈现。证据与耗时验证边界见 README「点位选择延迟」。
  ///
  /// 首次调用（包括传入 null）会启用新协议；地图已销毁或握手失败时抛出
  /// [MarkerSyncException]。传入与当前相同的 id 不会产生选择事件。
  Future<int> setSelectedMarker(String? markerId) =>
      _mapState._markerQueue.setSelected(markerId);

  /// 诊断：一次 `diag#ping` 时钟样本（R-TIME-3）。d0/d1 用 [MarkerDiagnosticsClock]。
  /// 诊断未开启时原生返回错误，抛出 [PlatformException]。
  Future<MarkerClockSample> pingNativeClock() async {
    final double d0 = MarkerDiagnosticsClock.nowMs();
    final Map<Object?, Object?>? r = await _methodChannel.diagPing(mapId: mapId);
    final double d1 = MarkerDiagnosticsClock.nowMs();
    final Object? n = r?['nativeMs'];
    if (n is! num) {
      throw StateError('diag#ping 返回缺少 nativeMs');
    }
    return MarkerClockSample(d0Ms: d0, nativeMs: n.toDouble(), d1Ms: d1);
  }

  /// 诊断：连续 ping [samples] 次（规格要求每轮采样前后各 20 次），取往返最短的样本估算时钟偏移
  Future<MarkerClockCalibration> calibrateNativeClock({int samples = 20}) async {
    final List<MarkerClockSample> out = <MarkerClockSample>[];
    for (int i = 0; i < samples; i++) {
      out.add(await pingNativeClock());
    }
    return MarkerClockCalibration.fromSamples(out);
  }

  /// 诊断：冷测试前清空原生合成位图缓存（§13.4）；诊断未开启时抛出 [PlatformException]
  Future<void> clearNativeMarkerCaches() =>
      _methodChannel.diagClearCaches(mapId: mapId);

  Future<void> _updateMapOptions(Map<String, dynamic> optionsUpdate) {
    return _methodChannel.updateMapOptions(optionsUpdate, mapId: mapId);
  }

  Future<void> _updateMarkers(MarkerUpdates markerUpdates) {
    return _methodChannel.updateMarkers(markerUpdates, mapId: mapId);
  }

  Future<void> _updatePolylines(PolylineUpdates polylineUpdates) {
    return _methodChannel.updatePolylines(polylineUpdates, mapId: mapId);
  }

  Future<void> _updatePolygons(PolygonUpdates polygonUpdates) {
    return _methodChannel.updatePolygons(polygonUpdates, mapId: mapId);
  }

  ///改变地图视角
  ///
  ///通过[CameraUpdate]对象设置新的中心点、缩放比例、放大缩小、显示区域等内容
  ///
  ///（注意：iOS端设置显示区域时，不支持duration参数，动画时长使用iOS地图默认值350毫秒）
  ///
  ///可选属性[animated]用于控制是否执行动画移动
  ///
  ///可选属性[duration]用于控制执行动画的时长,默认250毫秒,单位:毫秒
  Future<void> moveCamera(CameraUpdate cameraUpdate,
      {bool animated = true, int duration = 250}) {
    return _methodChannel.moveCamera(cameraUpdate,
        mapId: mapId, animated: animated, duration: duration);
  }

  ///地图截屏
  Future<Uint8List?> takeSnapshot() {
    return _methodChannel.takeSnapshot(mapId: mapId);
  }

  /// 清空缓存
  Future<void> clearDisk() {
    return _methodChannel.clearDisk(mapId: mapId);
  }

  /// 经纬度转屏幕坐标 since v1.0.3
  Future<ScreenCoordinate> toScreenCoordinate(LatLng latLng) {
    return _methodChannel.toScreenLocation(latLng, mapId: mapId);
  }

  /// 屏幕坐标转经纬度 From v1.0.3
  Future<LatLng> fromScreenCoordinate(ScreenCoordinate screenCoordinate) {
    return _methodChannel.fromScreenLocation(screenCoordinate, mapId: mapId);
  }

  Future<String> getMapContentApprovalNumber() {
    return _methodChannel.getMapContentApprovalNumber(mapId: mapId);
  }

  Future<String> getSatelliteImageApprovalNumber() {
    return _methodChannel.getSatelliteImageApprovalNumber(mapId: mapId);
  }
}

/// 把发送队列的请求转发到当前地图的 MethodChannel
class _ControllerMarkerTransport implements MarkerSyncTransport {
  _ControllerMarkerTransport(this._c);

  final AMapController _c;

  @override
  Future<void> updateLegacy(MarkerUpdates updates) => _c._updateMarkers(updates);

  @override
  Future<Map<Object?, Object?>?> attach() =>
      _methodChannel.attachMarkers(mapId: _c.mapId);

  @override
  Future<Map<Object?, Object?>?> update(Map<String, dynamic> payload) =>
      _methodChannel.updateMarkersV2(payload, mapId: _c.mapId);

  @override
  Future<Map<Object?, Object?>?> resync(Map<String, dynamic> payload) =>
      _methodChannel.resyncMarkers(payload, mapId: _c.mapId);

  @override
  Future<void> updateOptions(Map<String, dynamic> options) =>
      _c._updateMapOptions(options);

  @override
  Future<Map<Object?, Object?>?> setSelected(String? markerId) =>
      _methodChannel.setSelectedMarker(markerId, mapId: _c.mapId);
}
