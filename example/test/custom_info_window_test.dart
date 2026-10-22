import 'package:amap_map_example/pages/map/custom_map_style.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:amap_map_example/pages/map/map_my_location.dart';
import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/core/amap_flutter_platform.dart';
import 'package:amap_map/src/core/method_channel_amap_map.dart';
import 'package:amap_map_example/pages/overlays/custom_info_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Keep the real Dart map/widget lifecycle, replacing only native SDK calls.
class _TestMapPlatform extends MethodChannelAMapFlutterMap
    with MockPlatformInterfaceMixin {
  bool created = false;
  int mapId = 0;
  Completer<void>? ready;
  final List<Map<String, dynamic>> optionUpdates = <Map<String, dynamic>>[];
  final List<CameraUpdate> cameraUpdates = <CameraUpdate>[];

  @override
  Future<void> moveCamera(CameraUpdate update,
      {required int mapId, bool animated = true, int duration = 0}) async {
    cameraUpdates.add(update);
  }

  @override
  Future<void> updateMapOptions(Map<String, dynamic> options,
      {required int mapId}) async {
    optionUpdates.add(options);
  }

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers,
    void Function(int) onPlatformViewCreated,
  ) {
    if (!created) {
      created = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onPlatformViewCreated(mapId++);
      });
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> init(int mapId) async {
    await ready?.future;
  }

  @override
  void dispose({required int id}) {}

  @override
  Future<void> updateMarkers(MarkerUpdates updates,
      {required int mapId}) async {}

  @override
  Future<void> updatePolylines(PolylineUpdates updates,
      {required int mapId}) async {}

  @override
  Future<void> updatePolygons(PolygonUpdates updates,
      {required int mapId}) async {}

  @override
  Future<ScreenCoordinate> toScreenLocation(LatLng position,
      {required int mapId}) async {
    return const ScreenCoordinate(x: 100, y: 100);
  }
}

void main() {
  final _TestMapPlatform platform = _TestMapPlatform();
  AMapFlutterPlatform.instance = platform;

  Future<void> openDemo(WidgetTester tester) async {
    platform.created = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        AMapInitializer.init(context);
        return const Scaffold(body: CustomInfoWindowDemoPage());
      }),
    ));
    await tester.pumpAndSettle();
  }

  AMapWidget map(WidgetTester tester) =>
      tester.widget<AMapWidget>(find.byType(AMapWidget));

  Future<Marker> addAndSelect(WidgetTester tester) async {
    await tester.tap(find.textContaining('添加（当前'));
    await tester.pumpAndSettle();
    final Marker marker = map(tester).markers.last;
    marker.onTap!(marker.id);
    await tester.pumpAndSettle();
    return marker;
  }

  void expectEditingDisabled(WidgetTester tester) {
    for (final String label in <String>[
      '移除',
      '更新InfoWindow',
      '修改锚点',
      '修改透明度',
      '修改坐标',
      '修改旋转角度',
    ]) {
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, label))
            .onPressed,
        isNull,
        reason: '$label must be disabled without an existing selected marker',
      );
    }
    for (final Switch control
        in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(control.onChanged, isNull);
    }
  }

  for (final String action in <String>['移除', '全部移除']) {
    testWidgets('$action clears selection and ignores stale marker callbacks',
        (WidgetTester tester) async {
      await openDemo(tester);
      expectEditingDisabled(tester);
      final Marker removed = await addAndSelect(tester);
      expect(find.text(removed.infoWindow.title!), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(map(tester).markers, isEmpty);
      expectEditingDisabled(tester);
      expect(find.text(removed.infoWindow.title!), findsNothing);

      removed.onTap!(removed.id);
      removed.onDragEnd!(removed.id, const LatLng(30, 120));
      await tester.pumpAndSettle();
      expectEditingDisabled(tester);

      final Marker added = await addAndSelect(tester);
      await tester.tap(find.text('更新InfoWindow'));
      await tester.pumpAndSettle();
      expect(find.text('${added.infoWindow.title}*'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('style switch sends loaded bytes and both enable states',
      (WidgetTester tester) async {
    platform.created = false;
    platform.optionUpdates.clear();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CustomMapStylePage())));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final SwitchListTile control =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.onChanged, isNotNull);
    expect(control.value, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    Map<dynamic, dynamic> style = platform
        .optionUpdates.last['customStyleOptions'] as Map<dynamic, dynamic>;
    expect(style['enabled'], isTrue);
    expect((style['styleData'] as List<int>).length, greaterThan(0));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    style = platform.optionUpdates.last['customStyleOptions']
        as Map<dynamic, dynamic>;
    expect(style['enabled'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'location arriving before map ready is focused once and can recenter',
      (WidgetTester tester) async {
    const MethodChannel permissionChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      permissionChannel,
      (MethodCall call) async => <int, int>{3: 1},
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null));
    platform.created = false;
    platform.cameraUpdates.clear();
    platform.ready = Completer<void>();
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: MyLocationPage())));
    await tester.pumpAndSettle();
    final AMapWidget widget = map(tester);
    const LatLng shanghai = LatLng(31.230378, 121.473658);
    widget.onLocationChanged!(
        const AMapLocation(latLng: shanghai, altitude: 150));
    await tester.pump();
    expect(platform.cameraUpdates, isEmpty);
    platform.ready!.complete();
    await tester.pumpAndSettle();
    expect(platform.cameraUpdates.single.toJson(),
        CameraUpdate.newLatLngZoom(shanghai, 16).toJson());
    widget.onLocationChanged!(const AMapLocation(latLng: shanghai));
    await tester.pumpAndSettle();
    expect(platform.cameraUpdates, hasLength(1));
    await tester.tap(find.text('回到我的位置'));
    await tester.pumpAndSettle();
    expect(platform.cameraUpdates, hasLength(2));
    platform.ready = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection, visibility and dragging keep custom window in sync',
      (WidgetTester tester) async {
    await openDemo(tester);
    final Marker first = await addAndSelect(tester);
    expect(first.infoWindowEnable, isFalse);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(map(tester).markers.single.draggable, isTrue);

    final Marker second = await addAndSelect(tester);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text(first.infoWindow.title!), findsNothing);
    expect(find.text(second.infoWindow.title!), findsOneWidget);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.text(second.infoWindow.title!), findsNothing);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.text(second.infoWindow.title!), findsOneWidget);

    second.onDragEnd!(second.id, const LatLng(30, 120));
    await tester.pumpAndSettle();
    expect(map(tester).markers.last.position, const LatLng(30, 120));
    expect(tester.takeException(), isNull);
  });
}
