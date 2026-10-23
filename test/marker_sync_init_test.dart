import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s4_helpers.dart';

void main() {
  group('握手（§6.8）', () {
    test('T-INIT-1 attach 快照安装资源状态，错误回调一次', () async {
      final List<NativeMarkerError> errors = <NativeMarkerError>[];
      final MarkerImageResource a = asset('a');
      final MarkerSyncQueue q = MarkerSyncQueue(
        markers: <Marker>{nm('p', 'P', iconId: a.id)},
        images: <MarkerImageResource>{a, bytesImage},
        callbacks: MarkerSyncCallbacks(onNativeError: errors.add),
      );
      final FakeMarkerTransport t = FakeMarkerTransport();
      t.next((_) async => snapshot(
            ready: <String>['a'],
            failed: <String>[bytesImage.id],
            lastEventSeq: 2,
            errors: <Map<String, Object?>>[
              decodeError(1, bytesImage.id).args.cast<String, Object?>(),
            ],
          ));
      q.attachTransport(t);
      await flush();
      expect(q.imageStatus['a']!.state, MarkerImageState.ready);
      final MarkerImageStatus b = q.imageStatus[bytesImage.id]!;
      expect(b.state, MarkerImageState.failed);
      expect(b.attempts, 1);
      expect(errors, hasLength(1));
      // 握手后同一序号的实时错误重复到达，不重复回调（R-INIT-5）
      q.handleMessage(decodeError(1, bytesImage.id));
      expect(errors, hasLength(1));
    });

    test('T-INIT-2 attach 之后的事件生效；与快照重复时不变', () async {
      final MarkerImageResource c = asset('c');
      final MarkerSyncQueue q = MarkerSyncQueue(
          markers: <Marker>{nm('p', 'P', iconId: c.id)},
          images: <MarkerImageResource>{c, asset('d')});
      final FakeMarkerTransport t = FakeMarkerTransport();
      t.next((_) async => snapshot(ready: <String>['d'], lastEventSeq: 5));
      q.attachTransport(t);
      await flush();
      expect(q.imageStatus['c']!.state, MarkerImageState.sent);
      // 快照已包含的旧事件（seq ≤ 5）被忽略
      q.handleMessage(imagesResult(4, failed: <String>['d']));
      expect(q.imageStatus['d']!.state, MarkerImageState.ready);
      q.handleMessage(imagesResult(6, ready: <String>['c']));
      expect(q.imageStatus['c']!.state, MarkerImageState.ready);
      q.handleMessage(imagesResult(6, ready: <String>['c']));
      expect(q.imageStatus['c']!.state, MarkerImageState.ready);
    });

    test('T-INIT-4 attach 返回前重建 3 次，返回后只发 1 次合并请求', () async {
      final MarkerSyncQueue q = MarkerSyncQueue(markers: <Marker>{nm('a', '0')});
      final FakeMarkerTransport t = FakeMarkerTransport();
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.attachTransport(t);
      for (int i = 1; i <= 3; i++) {
        q.setTarget(<Marker>{nm('a', '$i'), nm('b', '$i')},
            const <MarkerImageResource>{});
        await flush();
      }
      expect(methods(t), <String>['markers#attach']);
      gate.complete(snapshot());
      await flush();
      expect(methods(t), <String>['markers#attach', 'markers#update']);
      final Map<String, dynamic> p = t.calls.last.map;
      expect(idsIn(p, 'markersToAdd'), <String>['b']);
      expect(idsIn(p, 'markersToChange'), <String>['a']);
    });

    test('T-INIT-5 纯旧路径：无 attach、无新键', () async {
      final MarkerSyncQueue q = MarkerSyncQueue(markers: <Marker>{im('a')});
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      for (int i = 1; i <= 3; i++) {
        q.setTarget(<Marker>{im('a', lat: 30.0 + i)},
            const <MarkerImageResource>{});
        await flush();
      }
      expect(methods(t), <String>['legacy', 'legacy', 'legacy']);
      for (final SentCall c in t.calls) {
        expect(c.map.containsKey('protocolVersion'), isFalse);
      }
      expect(q.confirmed['a'], im('a', lat: 33));
      expect(q.isProtocolV2, isFalse);
    });

    test('T-INIT-6 仅开启选择：握手一次后发送选项，无空 markers#update', () async {
      final List<MarkerSelectionChange> changes = <MarkerSelectionChange>[];
      final MarkerSyncQueue q = MarkerSyncQueue(
        markers: <Marker>{im('a')},
        callbacks: MarkerSyncCallbacks(onSelectionChanged: changes.add),
      );
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      q.setOptions(const MarkerSyncOptions(selection: MarkerSelectionOptions()));
      await flush();
      expect(methods(t), <String>['markers#attach', 'map#update']);
      expect(t.calls.last.map['markerSelection'], isNotNull);
      // 随后加入可选点，再点击可产生选择事件
      q.setTarget(<Marker>{im('a'), nm('s', 'S', selectable: true)},
          const <MarkerImageResource>{});
      await flush();
      expect(idsIn(t.calls.last.map, 'markersToAdd'), <String>['s']);
      q.handleMessage(msg('marker#selectionChanged', 1, <String, Object?>{
        'selectedId': 's',
        'previousId': null,
        'reason': 'markerTap',
        'revision': 1,
      }));
      expect(changes.single.selectedId, 's');
      expect(changes.single.reason, MarkerSelectionReason.markerTap);
    });

    test('T-INIT-7 旧请求在途时加入原生点与资源：先确认旧请求再握手', () async {
      final MarkerImageResource a = asset('a');
      final MarkerSyncQueue q = MarkerSyncQueue(markers: <Marker>{im('o')});
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.setTarget(<Marker>{im('o', lat: 31)}, const <MarkerImageResource>{});
      await flush();
      q.setTarget(<Marker>{im('o', lat: 31), nm('n', 'N', iconId: a.id)},
          <MarkerImageResource>{a, bytesImage});
      await flush();
      expect(methods(t), <String>['legacy']);
      gate.complete(null);
      await flush();
      expect(methods(t),
          <String>['legacy', 'markers#attach', 'markers#update']);
      final Map<String, dynamic> p = t.calls.last.map;
      expect(imageIds(p), unorderedEquals(<String>['a', bytesImage.id]));
      expect(idsIn(p, 'markersToAdd'), <String>['n']);
      expect(idsIn(p, 'markersToChange'), isEmpty); // 旧未变点不重发
      q.handleMessage(imagesResult(1, ready: <String>['a']));
      q.handleMessage(imagesResult(2, failed: <String>[bytesImage.id]));
      expect(q.imageStatus['a']!.state, MarkerImageState.ready);
      expect(q.imageStatus[bytesImage.id]!.state, MarkerImageState.failed);
    });

    test('T-INIT-8 首次选择与选项升级同时触发，只握手一次且命令最后发送', () async {
      final MarkerSyncQueue q = MarkerSyncQueue(markers: <Marker>{im('a')});
      final FakeMarkerTransport t = FakeMarkerTransport()..revision = 6;
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.attachTransport(t);
      q.setTarget(<Marker>{im('a', lat: 31)}, const <MarkerImageResource>{});
      await flush();
      // 旧请求在途时同时触发两种升级
      final Future<int> revision = q.setSelected('a');
      q.setOptions(const MarkerSyncOptions(selection: MarkerSelectionOptions()));
      gate.complete(null);
      await flush();
      expect(methods(t), <String>[
        'legacy',
        'markers#attach',
        'map#update',
        'markers#setSelected',
      ]);
      expect(await revision, 7);
    });

    test('T-INIT-9 快照后的事件先于 Future 到达：先装快照再应用，不回退', () async {
      final MarkerImageResource a = asset('a');
      final MarkerSyncQueue q = MarkerSyncQueue(
          markers: <Marker>{nm('p', 'P', iconId: a.id)},
          images: <MarkerImageResource>{a});
      final FakeMarkerTransport t = FakeMarkerTransport();
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.attachTransport(t);
      await flush();
      // 序号 3 的 ready 在握手返回前到达；快照（序号 2）中 a 仍为 pending
      q.handleMessage(imagesResult(3, ready: <String>['a']));
      q.handleMessage(imagesResult(1, failed: <String>['a']));
      gate.complete(snapshot(pending: <String>['a'], lastEventSeq: 2));
      await flush();
      expect(q.imageStatus['a']!.state, MarkerImageState.ready);
      expect(q.imageStatus['a']!.attempts, 0);
    });

    test('T-INIT-9 首次握手失败后幂等重试，期间不发依赖命令', () {
      fakeAsync((FakeAsync async) {
        final List<MarkerSyncException> errors = <MarkerSyncException>[];
        final MarkerSyncQueue q = MarkerSyncQueue(
            markers: <Marker>{nm('a', 'A')}, onSyncError: errors.add);
        final FakeMarkerTransport t = FakeMarkerTransport()..fail();
        q.attachTransport(t);
        Object? selectError;
        q.setSelected('a').catchError((Object e) {
          selectError = e;
          return -1;
        });
        q.setTarget(<Marker>{nm('a', 'A'), nm('b', 'B')},
            const <MarkerImageResource>{});
        async.flushMicrotasks();
        expect(methods(t), <String>['markers#attach']);
        expect(selectError, isA<MarkerSyncException>());
        async.elapse(q.retryDelay);
        expect(methods(t), <String>[
          'markers#attach',
          'markers#attach',
          'markers#update',
        ]);
        // 初始点 a 由握手确认，不重复创建；只新增 b
        expect(idsIn(t.calls.last.map, 'markersToAdd'), <String>['b']);
        expect(q.confirmed.keys, unorderedEquals(<String>['a', 'b']));
      });
    });

    test('握手连续失败两次后停止自动重试并报告', () {
      fakeAsync((FakeAsync async) {
        final List<MarkerSyncException> errors = <MarkerSyncException>[];
        final MarkerSyncQueue q = MarkerSyncQueue(
            markers: <Marker>{nm('a', 'A')}, onSyncError: errors.add);
        final FakeMarkerTransport t = FakeMarkerTransport()
          ..fail()
          ..fail();
        q.attachTransport(t);
        async.elapse(const Duration(minutes: 1));
        expect(methods(t), <String>['markers#attach', 'markers#attach']);
        expect(errors, hasLength(1));
        expect(q.hasPendingTimers, isFalse);
      });
    });
  });
}
