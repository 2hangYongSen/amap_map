import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/core/amap_flutter_platform.dart';
import 'package:amap_map/src/core/method_channel_amap_map.dart';
import 'package:amap_map_example/pages/interactive/house_map_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:x_amap_base/x_amap_base.dart';

// 保留真实地图控制器及通道，只替换原生平台视图和 SDK 应答。
class _MapPlatform extends MethodChannelAMapFlutterMap
    with MockPlatformInterfaceMixin {
  bool created = false;
  int nextId = 0;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers,
    void Function(int) onPlatformViewCreated,
  ) {
    if (!created) {
      created = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onPlatformViewCreated(nextId++));
    }
    return const SizedBox.expand();
  }
}

void main() {
  final _MapPlatform mapPlatform = _MapPlatform();
  AMapFlutterPlatform.instance = mapPlatform;
  late MethodChannel channel;
  final List<MethodCall> calls = <MethodCall>[];
  Completer<Object?>? pendingProjection;
  int revision = 0;
  String? selectedId;
  LatLng viewportCenter = const LatLng(31.2304, 121.4537);
  double viewportSpan = 0.01;

  Future<void> open(WidgetTester tester) async {
    mapPlatform.created = false;
    channel = MethodChannel('amap_map_${mapPlatform.nextId}');
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1200, 2400);
    calls.clear();
    pendingProjection = null;
    revision = 0;
    selectedId = null;
    viewportCenter = const LatLng(31.2304, 121.4537);
    viewportSpan = 0.01;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'markers#attach':
          return <String, Object?>{
            'protocolVersion': 2,
            'syncId': 0,
            'lastEventSeq': 0,
            'rejectedMarkerIds': <String>[],
          };
        case 'markers#setSelected':
          return <String, Object?>{'revision': ++revision};
        case 'markers#update':
        case 'markers#resync':
          return <String, Object?>{
            'syncId': call.arguments['syncId'],
            'accepted': true,
            'rejectedMarkerIds': <String>[],
          };
        case 'map#toScreenCoordinate':
          final Completer<Object?>? pending = pendingProjection;
          pendingProjection = null;
          if (pending != null) return pending.future;
          return <String, int>{'x': 360, 'y': 600};
        case 'map#fromScreenCoordinate':
          final int x = call.arguments['x'] as int;
          if (x == 0) {
            return <double>[
              viewportCenter.latitude + viewportSpan,
              viewportCenter.longitude - viewportSpan,
            ];
          }
          if (x == 1200 || x == 400) {
            return <double>[
              viewportCenter.latitude - viewportSpan,
              viewportCenter.longitude + viewportSpan,
            ];
          }
          return <double>[31.22, 121.45];
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: HouseMapPage())));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    calls.clear();
  }

  Future<void> select(WidgetTester tester, String? id,
      {String reason = 'markerTap', bool settle = true}) async {
    final ByteData data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('marker#selectionChanged', <String, Object?>{
        'selectedId': id,
        'previousId': selectedId,
        'reason': reason,
        'revision': ++revision,
        'eventSeq': revision,
      }),
    );
    selectedId = id;
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (_) {});
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  DraggableScrollableController sheet(WidgetTester tester) => tester
      .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
      .controller!;

  List<MethodCall> cameraMoves() =>
      calls.where((MethodCall call) => call.method == 'camera#move').toList();

  AMapWidget map(WidgetTester tester) =>
      tester.widget<AMapWidget>(find.byType(AMapWidget));

  void move(WidgetTester tester, LatLng center, {double zoom = 14.5}) {
    viewportCenter = center;
    final CameraPosition camera = CameraPosition(target: center, zoom: zoom);
    map(tester).onCameraMove!(camera);
    map(tester).onCameraMoveEnd!(camera);
  }

  Future<void> finishRequest(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'zooming into a tiny area returns only existing houses in that area',
      (WidgetTester tester) async {
    await open(tester);
    final Set<Marker> initial = map(tester).markers;
    final Set<String> firstIds = initial.map((Marker m) => m.id).toSet();
    expect(firstIds, hasLength(300));
    expect(initial.every((Marker m) => m.selectable), isTrue);
    expect(find.textContaining('当前视野 300 套'), findsOneWidget);
    final Marker house = initial.first;

    viewportSpan = 0.00001;
    move(tester, house.position, zoom: 20);
    await tester.pump();
    expect(find.textContaining('正在查询附近房源'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 699));
    expect(map(tester).markers.map((Marker m) => m.id).toSet(), firstIds);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    final Marker result = map(tester).markers.single;
    expect(result.id, house.id);
    expect(result.position, house.position);
    expect(result.nativePresentation, house.nativePresentation);
    expect(find.textContaining('当前视野 1 套'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'panning queries stable houses, empty areas stay empty, returning restores them',
      (WidgetTester tester) async {
    await open(tester);
    final Map<String, Marker> catalog = <String, Marker>{
      for (final Marker marker in map(tester).markers) marker.id: marker,
    };
    viewportSpan = 0.004;
    move(tester, const LatLng(31.2304, 121.4517));
    await finishRequest(tester);
    final Set<String> leftIds =
        map(tester).markers.map((Marker m) => m.id).toSet();
    expect(leftIds.length, inExclusiveRange(0, 300));

    move(tester, const LatLng(31.2304, 121.4557));
    await finishRequest(tester);
    final Set<Marker> right = map(tester).markers;
    final Set<String> rightIds = right.map((Marker m) => m.id).toSet();
    expect(rightIds.intersection(leftIds), isNotEmpty);
    expect(rightIds.difference(leftIds), isNotEmpty);
    expect(leftIds.difference(rightIds), isNotEmpty);
    for (final Marker marker in right) {
      expect(marker.position, catalog[marker.id]!.position);
      expect(marker.nativePresentation, catalog[marker.id]!.nativePresentation);
      expect(marker.position.latitude, inInclusiveRange(31.2264, 31.2344));
      expect(marker.position.longitude, inInclusiveRange(121.4517, 121.4597));
    }

    move(tester, const LatLng(30.25, 120.15));
    await finishRequest(tester);
    expect(map(tester).markers, isEmpty);
    expect(find.textContaining('当前视野暂无房源'), findsOneWidget);

    viewportSpan = 0.01;
    move(tester, const LatLng(31.2304, 121.4537));
    await finishRequest(tester);
    expect(map(tester).markers.map((Marker m) => m.id).toSet(),
        catalog.keys.toSet());
    for (final Marker marker in map(tester).markers) {
      expect(marker.position, catalog[marker.id]!.position);
      expect(marker.nativePresentation, catalog[marker.id]!.nativePresentation);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'debounces movement and discards an old query when dragging resumes',
      (WidgetTester tester) async {
    await open(tester);
    final Set<String> initialIds =
        map(tester).markers.map((Marker m) => m.id).toSet();
    move(tester, const LatLng(30, 120));
    await tester.pump(const Duration(milliseconds: 150));
    move(tester, const LatLng(32, 118));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        calls.where((MethodCall c) => c.method == 'map#fromScreenCoordinate'),
        hasLength(2));
    // 旧查询会返回空列表。再次开始拖动后，即使尚未停拖发新请求，也不能应用旧结果。
    await tester.pump(const Duration(milliseconds: 300));
    const CameraPosition camera =
        CameraPosition(target: LatLng(31.2304, 121.4537), zoom: 17);
    map(tester).onCameraMove!(camera);
    await tester.pump(const Duration(milliseconds: 400));
    expect(map(tester).markers.map((Marker m) => m.id).toSet(), initialIds);
    viewportCenter = camera.target;
    viewportSpan = 0.002;
    map(tester).onCameraMoveEnd!(camera);
    await finishRequest(tester);
    expect(map(tester).markers.length, inExclusiveRange(0, 300));
    expect(initialIds.containsAll(map(tester).markers.map((Marker m) => m.id)),
        isTrue);
    expect(find.textContaining('第 3 次查询'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'automatic focus queries its viewport and retains selection without refocusing',
      (WidgetTester tester) async {
    await open(tester);
    final Set<Marker> initial = map(tester).markers;
    await select(tester, 'house-2');
    expect(cameraMoves(), hasLength(1));
    calls.clear();
    move(tester, const LatLng(31.22, 121.45));
    await finishRequest(tester);
    expect(
        calls.where((MethodCall c) => c.method == 'map#fromScreenCoordinate'),
        hasLength(2));
    final Set<Marker> focusedHouses = initial
        .where((Marker marker) =>
            marker.position.latitude >= 31.21 &&
            marker.position.latitude <= 31.23 &&
            marker.position.longitude >= 121.44 &&
            marker.position.longitude <= 121.46)
        .toSet();
    expect(focusedHouses.length, inExclusiveRange(0, 300));
    expect(map(tester).markers, focusedHouses);
    expect(map(tester).markers.any((Marker m) => m.id == 'house-2'), isTrue);
    expect(find.text('示例公寓 2'), findsOneWidget);
    expect(sheet(tester).size, closeTo(0.5, 0.001));
    expect(cameraMoves(), isEmpty);
    expect(calls.where((MethodCall c) => c.method == 'markers#setSelected'),
        isEmpty);

    // 刷新覆盖物后 SDK 重复回调相同视角，不重复请求或移动相机。
    move(tester, const LatLng(31.22, 121.45));
    await finishRequest(tester);
    expect(
        calls.where((MethodCall c) => c.method == 'map#fromScreenCoordinate'),
        hasLength(2));
    expect(cameraMoves(), isEmpty);

    move(tester, const LatLng(31.2304, 121.4537));
    await finishRequest(tester);
    expect(map(tester).markers, initial);
    expect(find.text('示例公寓 2'), findsOneWidget);
    expect(sheet(tester).size, closeTo(0.5, 0.001));
    expect(cameraMoves(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a selected house outside the queried area is removed and its sheet closes',
      (WidgetTester tester) async {
    await open(tester);
    await select(tester, 'house-2');
    calls.clear();
    move(tester, const LatLng(30.25, 120.15));
    await finishRequest(tester);
    expect(map(tester).markers, isEmpty);
    expect(sheet(tester).size, 0);
    expect(find.text('示例公寓 2'), findsNothing);
    expect(find.textContaining('当前视野暂无房源'), findsOneWidget);
    final MethodCall clear =
        calls.singleWhere((MethodCall c) => c.method == 'markers#setSelected');
    expect(clear.arguments['markerId'], isNull);
    expect(cameraMoves(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving while a request is in flight ignores its result',
      (WidgetTester tester) async {
    await open(tester);
    move(tester, const LatLng(30, 120));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate camera callbacks do not restart or repeat queries',
      (WidgetTester tester) async {
    await open(tester);
    for (int i = 0; i < 3; i++) {
      move(tester, const LatLng(31.2304, 121.4537));
      await finishRequest(tester);
    }
    expect(
        calls.where((MethodCall c) => c.method == 'map#fromScreenCoordinate'),
        isEmpty);
    viewportSpan = 0.002;
    move(tester, const LatLng(31.232, 121.454), zoom: 17);
    await tester.pump(const Duration(milliseconds: 250));
    move(tester, const LatLng(31.232, 121.454), zoom: 17);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(map(tester).markers.length, inExclusiveRange(0, 300));
    move(tester, const LatLng(31.232, 121.454), zoom: 17);
    await finishRequest(tester);
    expect(
        calls.where((MethodCall c) => c.method == 'map#fromScreenCoordinate'),
        hasLength(2));
    expect(find.textContaining('第 2 次查询'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS
  ]) {
    testWidgets('$platform selection focuses above the half sheet without zoom',
        (WidgetTester tester) async {
      await open(tester);
      expect(sheet(tester).size, 0);
      await select(tester, 'house-1');
      expect(find.text('示例公寓 1'), findsOneWidget);
      expect(sheet(tester).size, closeTo(0.5, 0.001));
      final MethodCall projection = calls.singleWhere(
          (MethodCall call) => call.method == 'map#fromScreenCoordinate');
      expect(projection.arguments, <String, int>{
        'x': 360,
        'y': platform == TargetPlatform.android ? 1230 : 810,
      });
      expect(cameraMoves().single.arguments['cameraUpdate'], <Object>[
        'newLatLng',
        <Matcher>[closeTo(31.22, 0.000001), closeTo(121.45, 0.000001)]
      ]);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets(
      'switching selection discards a delayed focus and resets the list',
      (WidgetTester tester) async {
    await open(tester);
    final Completer<Object?> delayed = Completer<Object?>();
    pendingProjection = delayed;
    await select(tester, 'house-1');
    expect(cameraMoves(), isEmpty);
    await tester.tap(find.text('展开 / 半屏'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await select(tester, 'house-2');
    delayed.complete(<String, int>{'x': 10, 'y': 10});
    await tester.pumpAndSettle();
    expect(find.text('示例公寓 2').hitTestable(), findsOneWidget);
    expect(find.text('示例公寓 1'), findsNothing);
    expect(sheet(tester).size, closeTo(0.5, 0.001));
    expect(cameraMoves(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retap, map tap and close hide the sheet without moving camera',
      (WidgetTester tester) async {
    await open(tester);
    for (final String reason in <String>['retap', 'mapTap', 'close']) {
      await select(tester, 'house-1');
      calls.clear();
      if (reason == 'close') {
        await tester.tap(find.byTooltip('关闭房源'));
        await tester.pumpAndSettle();
        expect(calls.where((MethodCall c) => c.method == 'markers#setSelected'),
            hasLength(1));
      } else {
        await select(tester, null, reason: reason);
      }
      expect(sheet(tester).size, 0);
      expect(find.text('示例公寓 1'), findsNothing);
      expect(cameraMoves(), isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sheet drags to full, half and hidden and clears native selection',
      (WidgetTester tester) async {
    await open(tester);
    await select(tester, 'house-1');
    calls.clear();
    final Finder handle =
        find.byKey(const ValueKey<String>('house-sheet-handle'));
    await tester.timedDrag(
        handle, const Offset(0, -340), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sheet(tester).size, closeTo(0.94, 0.001));
    await tester.timedDrag(
        handle, const Offset(0, 350), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sheet(tester).size, closeTo(0.5, 0.001));
    await tester.timedDrag(
        handle, const Offset(0, 390), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sheet(tester).size, 0);
    expect(find.text('示例公寓 1'), findsNothing);
    final MethodCall clear = calls
        .singleWhere((MethodCall call) => call.method == 'markers#setSelected');
    expect(clear.arguments['markerId'], isNull);
    expect(cameraMoves(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing before projection returns cancels pending focus',
      (WidgetTester tester) async {
    await open(tester);
    final Completer<Object?> delayed = Completer<Object?>();
    pendingProjection = delayed;
    await select(tester, 'house-1');
    await tester.tap(find.byTooltip('关闭房源'));
    await tester.pumpAndSettle();
    delayed.complete(<String, int>{'x': 360, 'y': 600});
    await tester.pumpAndSettle();
    expect(cameraMoves(), isEmpty);
    expect(sheet(tester).size, 0);
    expect(tester.takeException(), isNull);
  });
}
