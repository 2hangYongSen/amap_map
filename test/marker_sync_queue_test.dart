import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

import 'support/fake_marker_transport.dart';

const NativeMarkerStyle _style = NativeMarkerStyle(
  background: NativeMarkerShapeBackground.roundedRect(
      fillColor: Color(0xFFFFFFFF), cornerRadius: 4),
);

/// 原生点位；[text] 不同即为不同的值
Marker nativeMarker(String id, String text, {double lat = 30}) => Marker(
      markerId: id,
      position: LatLng(lat, 120),
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        style: _style,
      ),
    );

Marker iconMarker(String id, {double lat = 30}) =>
    Marker(markerId: id, position: LatLng(lat, 120));

/// 创建一个新协议队列并完成握手
Future<(MarkerSyncQueue, FakeMarkerTransport)> v2Queue(
    Set<Marker> initial) async {
  final MarkerSyncQueue q = MarkerSyncQueue(markers: initial);
  final FakeMarkerTransport t = FakeMarkerTransport();
  q.attachTransport(t);
  await flush();
  expect(q.isProtocolV2, isTrue);
  t.calls.clear();
  return (q, t);
}

const Set<MarkerImageResource> _noImages = <MarkerImageResource>{};

void main() {
  test('T-SYNC-1 在途期间 5 次重建只合并为 1 个待发请求', () async {
    final (MarkerSyncQueue q, FakeMarkerTransport t) =
        await v2Queue(<Marker>{nativeMarker('a', '0')});
    final Completer<Map<Object?, Object?>?> gate = t.hold();
    final Set<Marker> first = <Marker>{nativeMarker('a', '1')};
    q.setTarget(first, _noImages);
    await flush();
    for (int i = 2; i <= 6; i++) {
      q.setTarget(<Marker>{
        nativeMarker('a', '$i'),
        nativeMarker('b', '$i'),
      }, _noImages);
    }
    await flush();
    expect(t.calls, hasLength(1));
    gate.complete(FakeMarkerTransport.accepted(t.calls.first));
    await flush();
    expect(t.calls, hasLength(2));
    // 第 2 次 = 第 1 次快照 → 最终快照
    final Map<String, dynamic> second = t.calls[1].map;
    expect(idsIn(second, 'markersToAdd'), <String>['b']);
    expect(idsIn(second, 'markersToChange'), <String>['a']);
    expect(q.confirmed['a'], nativeMarker('a', '6'));
  });

  test('T-SYNC-3 第 2 个请求失败后发送完整快照的 markers#resync', () async {
    final (MarkerSyncQueue q, FakeMarkerTransport t) =
        await v2Queue(<Marker>{nativeMarker('a', '0')});
    q.setTarget(<Marker>{nativeMarker('a', '1')}, _noImages);
    await flush();
    t.fail();
    q.setTarget(<Marker>{nativeMarker('a', '1'), nativeMarker('b', '1')},
        _noImages);
    await flush();
    expect(t.calls.map((SentCall c) => c.method), <String>[
      'markers#update',
      'markers#update',
      'markers#resync',
    ]);
    final Map<String, dynamic> resync = t.calls.last.map;
    expect(idsIn(resync, 'markers'), unorderedEquals(<String>['a', 'b']));
    expect(resync['protocolVersion'], 2);
    expect(q.confirmed.keys, unorderedEquals(<String>['a', 'b']));
  });

  test('resync 连续失败时有界停止并报告错误', () async {
    final List<MarkerSyncException> errors = <MarkerSyncException>[];
    final MarkerSyncQueue q = MarkerSyncQueue(
        markers: <Marker>{nativeMarker('a', '0')},
        onSyncError: errors.add,
        retryDelay: Duration.zero);
    final FakeMarkerTransport t = FakeMarkerTransport();
    q.attachTransport(t);
    await flush();
    for (int i = 0; i < 5; i++) {
      t.fail();
    }
    q.setTarget(<Marker>{nativeMarker('a', '1')}, _noImages);
    await flush();
    // update 失败 1 次 + resync 最多 2 次
    expect(t.byMethod('markers#resync'), hasLength(2));
    expect(errors, isNotEmpty);
    expect(q.isBusy, isFalse);
  });

  group('T-SYNC-5 部分拒绝', () {
    late MarkerSyncQueue q;
    late FakeMarkerTransport t;
    final Marker c0 = nativeMarker('c', 'C0');
    final Marker c1 = nativeMarker('c', 'C1');
    final Marker a = nativeMarker('a', 'A');
    final Marker b = nativeMarker('b', 'B');

    setUp(() async {
      (q, t) = await v2Queue(<Marker>{c0});
      t.reject(<String>['b', 'c']);
      q.setTarget(<Marker>{a, b, c1}, _noImages);
      await flush();
      t.calls.clear();
    });

    test('基准逐点推进，无关重建不重发被拒值', () async {
      expect(q.confirmed.keys, unorderedEquals(<String>['a', 'c']));
      expect(q.confirmed['c'], c0);
      expect(q.rejected, <String, Marker>{'b': b, 'c': c1});
      // 无关重建：只新增 d
      q.setTarget(<Marker>{a, b, c1, iconMarker('d')}, _noImages);
      await flush();
      final Map<String, dynamic> p = t.calls.single.map;
      expect(idsIn(p, 'markersToAdd'), <String>['d']);
      expect(idsIn(p, 'markersToChange'), isEmpty);
    });

    test('① 移除仍被拒绝的 B 不发送 remove(B)', () async {
      q.setTarget(<Marker>{a, c1}, _noImages);
      await flush();
      expect(t.calls, isEmpty);
      expect(q.rejected.containsKey('b'), isFalse);
    });

    test('② B 修正为 B\' 成功 add 后再移除，必须 remove(B)', () async {
      final Marker b2 = nativeMarker('b', "B'");
      q.setTarget(<Marker>{a, b2, c1}, _noImages);
      await flush();
      expect(idsIn(t.calls.single.map, 'markersToAdd'), <String>['b']);
      q.setTarget(<Marker>{a, c1}, _noImages);
      await flush();
      expect(t.calls.last.map['markerIdsToRemove'], <String>['b']);
    });

    test('③ 移除 C 必须发送 remove(C)', () async {
      q.setTarget(<Marker>{a, b}, _noImages);
      await flush();
      expect(t.calls.single.map['markerIdsToRemove'], <String>['c']);
    });

    test('T-SYNC-6 resync 不带非法值，之后也不重发', () async {
      // 下一次普通请求失败，触发 resync
      t.fail();
      q.setTarget(<Marker>{a, b, c1, iconMarker('d')}, _noImages);
      await flush();
      final Map<String, dynamic> resync =
          t.byMethod('markers#resync').single.map;
      final List<Map<String, dynamic>> markers =
          (resync['markers'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(markers.map((Map<String, dynamic> m) => m['id']),
          unorderedEquals(<String>['a', 'c', 'd']));
      final Map<String, dynamic> c = markers.firstWhere(
          (Map<String, dynamic> m) => m['id'] == 'c');
      expect(c['nativePresentation']['content']['text'], 'C0');
      expect(q.rejected, <String, Marker>{'b': b, 'c': c1});
      t.calls.clear();
      // 无关重建不重发 B、C1
      q.setTarget(
          <Marker>{a, b, c1, iconMarker('d'), iconMarker('e')}, _noImages);
      await flush();
      final Map<String, dynamic> p = t.calls.single.map;
      expect(idsIn(p, 'markersToAdd'), <String>['e']);
      expect(idsIn(p, 'markersToChange'), isEmpty);
    });
  });

  group('协议锁存', () {
    test('T-COMPAT-2 启用后把唯一原生点改回 icon，仍按新协议发送', () async {
      final (MarkerSyncQueue q, FakeMarkerTransport t) =
          await v2Queue(<Marker>{nativeMarker('a', 'x')});
      q.setTarget(<Marker>{iconMarker('a')}, _noImages);
      await flush();
      final Map<String, dynamic> p = t.calls.single.map;
      expect(t.calls.single.method, 'markers#update');
      expect(p['protocolVersion'], 2);
      final Map<String, dynamic> m =
          (p['markersToChange'] as List<dynamic>).single;
      expect(m['renderMode'], 'icon');
      expect(m.containsKey('nativePresentation'), isTrue);
      expect(m['nativePresentation'], isNull);
      expect(m['icon'], isNotNull);
    });

    test('T-COMPAT-3 创建后才启用：先旧请求，再握手，不重发未变点', () async {
      final MarkerSyncQueue q = MarkerSyncQueue(
          markers: <Marker>{iconMarker('a'), iconMarker('b')});
      expect(q.createdAsV2, isFalse);
      expect(q.creationParams.keys, <String>['markersToAdd']);
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      expect(t.calls, isEmpty);
      // 旧请求在途时加入原生点
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.setTarget(<Marker>{iconMarker('a'), iconMarker('b', lat: 31)},
          _noImages);
      await flush();
      q.setTarget(<Marker>{
        iconMarker('a'),
        iconMarker('b', lat: 31),
        nativeMarker('n', 'N'),
      }, _noImages);
      await flush();
      expect(t.calls.single.method, 'legacy');
      expect(t.calls.single.map.containsKey('protocolVersion'), isFalse);
      gate.complete(null);
      await flush();
      expect(t.calls.map((SentCall c) => c.method),
          <String>['legacy', 'markers#attach', 'markers#update']);
      final Map<String, dynamic> p = t.calls.last.map;
      expect(idsIn(p, 'markersToAdd'), <String>['n']);
      expect(idsIn(p, 'markersToChange'), isEmpty);
      // 之后修改旧点，以新格式完整发送
      q.setTarget(<Marker>{
        iconMarker('a', lat: 32),
        iconMarker('b', lat: 31),
        nativeMarker('n', 'N'),
      }, _noImages);
      await flush();
      final Map<String, dynamic> changed =
          (t.calls.last.map['markersToChange'] as List<dynamic>).single;
      expect(changed['id'], 'a');
      expect(changed['renderMode'], 'icon');
      expect(changed.containsKey('selectedZIndex'), isTrue);
    });

    test('纯旧协议地图全程不握手、不带新键', () async {
      final MarkerSyncQueue q =
          MarkerSyncQueue(markers: <Marker>{iconMarker('a')});
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      q.setTarget(<Marker>{iconMarker('a', lat: 31)}, _noImages);
      await flush();
      expect(t.calls.single.method, 'legacy');
      expect(t.calls.single.map.keys.toSet(), <String>{
        'markersToAdd',
        'markersToChange',
        'markerIdsToRemove',
      });
    });

    test('新协议创建：握手的拒绝列表按“新增被拒”处理', () async {
      final Marker bad = nativeMarker('bad', 'x');
      final MarkerSyncQueue q =
          MarkerSyncQueue(markers: <Marker>{nativeMarker('a', 'A'), bad});
      expect(q.creationParams['protocolVersion'], 2);
      final FakeMarkerTransport t = FakeMarkerTransport();
      t.next((SentCall c) async => <Object?, Object?>{
            'protocolVersion': 2,
            'syncId': 0,
            'rejectedMarkerIds': <String>['bad'],
          });
      // 握手前的重建只合并，不发送
      q.setTarget(<Marker>{nativeMarker('a', 'A2'), bad}, _noImages);
      q.attachTransport(t);
      await flush();
      expect(t.calls.map((SentCall c) => c.method),
          <String>['markers#attach', 'markers#update']);
      expect(idsIn(t.calls.last.map, 'markersToChange'), <String>['a']);
      expect(q.rejected['bad'], bad);
    });
  });

  test('销毁后迟到结果不推进 confirmed', () async {
    final (MarkerSyncQueue q, FakeMarkerTransport t) =
        await v2Queue(<Marker>{nativeMarker('a', '0')});
    final Completer<Map<Object?, Object?>?> gate = t.hold();
    q.setTarget(<Marker>{nativeMarker('a', '1')}, _noImages);
    await flush();
    q.dispose();
    gate.complete(FakeMarkerTransport.accepted(t.calls.single));
    await flush();
    expect(q.confirmed, isEmpty);
    expect(t.calls, hasLength(1));
  });
}
