import 'dart:async';

import 'package:amap_map/src/core/amap_flutter_platform.dart';
import 'package:amap_map/src/core/method_channel_amap_map.dart';
import 'package:amap_map_example/pages/interactive/house_map_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

  Future<void> open(WidgetTester tester) async {
    mapPlatform.created = false;
    channel = MethodChannel('amap_map_${mapPlatform.nextId}');
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1200, 2400);
    calls.clear();
    pendingProjection = null;
    revision = 0;
    selectedId = null;
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
        case 'map#toScreenCoordinate':
          final Completer<Object?>? pending = pendingProjection;
          pendingProjection = null;
          if (pending != null) return pending.future;
          return <String, int>{'x': 360, 'y': 600};
        case 'map#fromScreenCoordinate':
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

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS
  ]) {
    testWidgets('$platform selection focuses above the half sheet without zoom',
        (WidgetTester tester) async {
      await open(tester);
      expect(sheet(tester).size, 0);
      await select(tester, 'house-1');
      expect(find.text('静安紫庭公寓'), findsOneWidget);
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
    expect(find.text('南京西路青年公寓').hitTestable(), findsOneWidget);
    expect(find.text('静安紫庭公寓'), findsNothing);
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
      expect(find.text('静安紫庭公寓'), findsNothing);
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
    expect(find.text('静安紫庭公寓'), findsNothing);
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
