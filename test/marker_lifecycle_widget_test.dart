import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart'
    show MarkerSyncException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_harness.dart';
import 'support/s4_helpers.dart' show nm, asset;

const MarkerTransition _replace =
    MarkerTransition.replaceWhenReady(timeout: Duration(seconds: 1));

void main() {
  final ChannelPlatform platform = installChannelPlatform();
  late FakeNative native;

  Future<void> open(WidgetTester tester, Widget Function() map,
      {bool settle = true}) async {
    native = FakeNative(tester, platform.nextId)..install();
    await tester.pumpWidget(MaterialApp(home: Host(builder: map)));
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> rebuild(WidgetTester tester, Widget Function() map) async {
    tester.state<HostState>(find.byType(Host)).rebuildWith(map);
    await tester.pumpAndSettle();
  }

  Future<void> tap(String id) =>
      native.emit('marker#onTap', <String, Object?>{'markerId': id});

  /// 最近一次携带删除的 markers#update 的 syncId
  int lastRemoveSyncId() => native.calls
      .lastWhere((MethodCall c) =>
          c.method == 'markers#update' &&
          ((c.arguments as Map<Object?, Object?>)['markerIdsToRemove']
                  as List<Object?>)
              .isNotEmpty)
      .arguments['syncId'] as int;

  testWidgets('T-DEL-7 待删除点在 removed 之前点击，旧回调执行一次',
      (WidgetTester tester) async {
    final List<String> taps = <String>[];
    final List<MarkerSelectionChange> changes = <MarkerSelectionChange>[];
    final Marker d1 = nm('d:1', '片区', onTap: taps.add);
    Widget map(Set<Marker> m) => AMapWidget(
          markers: m,
          markerTransition: _replace,
          onMarkerSelectionChanged: changes.add,
        );
    await open(tester, () => map(<Marker>{d1, nm('p', 'P')}));
    await rebuild(tester, () => map(<Marker>{nm('p', 'P')}));
    final int removeSyncId = lastRemoveSyncId();
    await tap('d:1');
    expect(taps, <String>['d:1']);
    expect(changes, isEmpty);
    await native.emit('markers#removed', <String, Object?>{
      'markerIds': <String>['d:1'],
      'removeSyncIds': <int>[removeSyncId],
      'eventSeq': 1,
    });
    await tap('d:1');
    expect(taps, hasLength(1));
  });

  testWidgets('T-DEL-8 removed 之前以新回调重新加入，旧 removed 不影响新点',
      (WidgetTester tester) async {
    final List<String> oldTaps = <String>[];
    final List<String> newTaps = <String>[];
    Widget map(Set<Marker> m) =>
        AMapWidget(markers: m, markerTransition: _replace);
    await open(tester,
        () => map(<Marker>{nm('d:1', '片区', onTap: oldTaps.add)}));
    await rebuild(tester, () => map(<Marker>{nm('p', 'P')}));
    final int removeSyncId = lastRemoveSyncId();
    await rebuild(tester,
        () => map(<Marker>{nm('d:1', '片区', onTap: newTaps.add)}));
    await tap('d:1');
    await native.emit('markers#removed', <String, Object?>{
      'markerIds': <String>['d:1'],
      'removeSyncIds': <int>[removeSyncId],
      'eventSeq': 1,
    });
    await tap('d:1');
    expect(oldTaps, isEmpty);
    expect(newTaps, <String>['d:1', 'd:1']);
  });

  testWidgets('T-DEL-9 immediate 下删除请求在途时点击走旧回调，返回后清除',
      (WidgetTester tester) async {
    final List<String> taps = <String>[];
    Widget map(Set<Marker> m) => AMapWidget(markers: m);
    await open(tester, () => map(<Marker>{nm('d:1', 'D', onTap: taps.add)}));
    final Completer<Object?> gate = native.hold('markers#update');
    await rebuild(tester, () => map(<Marker>{nm('p', 'P')}));
    await tap('d:1');
    expect(taps, <String>['d:1']);
    gate.complete(FakeNative.defaultReply(native.calls.last));
    await tester.pumpAndSettle();
    await tap('d:1');
    expect(taps, hasLength(1));
  });

  testWidgets('T-SEL-6 同一次点击 selectionChanged 先于 onTap 交付',
      (WidgetTester tester) async {
    final List<String> order = <String>[];
    await open(
        tester,
        () => AMapWidget(
              markers: <Marker>{
                nm('a', 'A', selectable: true, onTap: (_) => order.add('tap')),
              },
              markerSelection: const MarkerSelectionOptions(),
              onMarkerSelectionChanged: (MarkerSelectionChange c) =>
                  order.add('selection:${c.selectedId}'),
            ));
    // 原生在同一次 SDK 回调内按 R-SEL-3 顺序发送
    await native.emit('marker#selectionChanged', <String, Object?>{
      'selectedId': 'a',
      'previousId': null,
      'reason': 'markerTap',
      'revision': 1,
      'eventSeq': 1,
    });
    await tap('a');
    expect(order, <String>['selection:a', 'tap']);
  });

  testWidgets('控制器 setSelectedMarker 返回 revision',
      (WidgetTester tester) async {
    late AMapController controller;
    await open(
        tester,
        () => AMapWidget(
            markers: <Marker>{nm('a', 'A', selectable: true)},
            onMapCreated: (AMapController c) => controller = c));
    final Future<int> revision = controller.setSelectedMarker('a');
    await tester.pumpAndSettle();
    expect(await revision, 1);
    expect(native.lastArgs('markers#setSelected')['markerId'], 'a');
  });

  testWidgets('T-DART-DISP-1 asset 重试计时器挂起时销毁，之后无调用',
      (WidgetTester tester) async {
    final MarkerImageResource a = asset('a');
    await open(
        tester,
        () => AMapWidget(
            markers: <Marker>{nm('p', 'P', iconId: a.id)},
            markerImages: <MarkerImageResource>{a}));
    await native.emit('marker#imagesResult', <String, Object?>{
      'ready': <String>[],
      'failed': <Map<String, Object?>>[
        <String, Object?>{'id': 'a'},
      ],
      'eventSeq': 1,
    });
    native.calls.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(native.markerMethods(), isEmpty);
  });

  testWidgets('T-DART-DISP-2 attach 在途时销毁：迟到成功不推进、不回调',
      (WidgetTester tester) async {
    final List<NativeMarkerError> errors = <NativeMarkerError>[];
    Future<int>? select;
    native = FakeNative(tester, platform.nextId)..install();
    final Completer<Object?> attach = native.hold('markers#attach');
    await tester.pumpWidget(MaterialApp(
        home: AMapWidget(
      markers: <Marker>{nm('a', 'A')},
      onNativeMarkerError: errors.add,
      // 选择命令排在握手之后
      onMapCreated: (AMapController c) => select = c.setSelectedMarker('a'),
    )));
    await tester.pumpAndSettle();
    expect(native.markerMethods(), <String>['map#waitForMap', 'markers#attach']);
    // 先挂上断言再销毁：等待中的选择命令以错误结束，不悬挂
    final Future<void> selectFails =
        expectLater(select, throwsA(isA<MarkerSyncException>()));
    await tester.pumpWidget(const SizedBox());
    await selectFails;
    attach.complete(FakeNative.attachReply());
    await native.emit('marker#nativeError', <String, Object?>{
      'code': 'renderFailed',
      'message': 'late',
      'eventSeq': 1,
    });
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
    expect(native.markerMethods(), <String>['map#waitForMap', 'markers#attach']);
  });

  testWidgets('T-DART-DISP-2 markers#update 在途时销毁：迟到失败不重试',
      (WidgetTester tester) async {
    Widget map(Set<Marker> m) => AMapWidget(markers: m);
    await open(tester, () => map(<Marker>{nm('a', 'A')}));
    final Completer<Object?> update = native.hold('markers#update');
    await rebuild(tester, () => map(<Marker>{nm('a', 'A2')}));
    await tester.pumpWidget(const SizedBox());
    native.calls.clear();
    update.completeError(PlatformException(code: 'late'));
    await tester.pump(const Duration(seconds: 5));
    expect(native.markerMethods(), isEmpty); // 没有 resync
  });

  testWidgets('T-DART-DISP-3 初始化迟到：只清理不握手；旧会话事件不影响新会话',
      (WidgetTester tester) async {
    final List<NativeMarkerError> errors = <NativeMarkerError>[];
    int created = 0;
    final FakeNative old = FakeNative(tester, platform.nextId)..install();
    final Completer<Object?> wait = old.hold('map#waitForMap');
    Widget map() => AMapWidget(
        markers: <Marker>{nm('a', 'A')},
        onNativeMarkerError: errors.add,
        onMapCreated: (_) => created++);
    await tester.pumpWidget(MaterialApp(home: map()));
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // 控制器未就绪即销毁
    wait.complete(null);
    await tester.pumpAndSettle();
    expect(old.markerMethods(), <String>['map#waitForMap']);
    expect(created, 0);
    // 新会话（新平台视图）
    native = FakeNative(tester, platform.nextId)..install();
    await tester.pumpWidget(MaterialApp(home: map()));
    await tester.pumpAndSettle();
    expect(created, 1);
    await old.emit('marker#nativeError', <String, Object?>{
      'code': 'renderFailed',
      'message': 'old session',
      'eventSeq': 1,
    });
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
  });
}
