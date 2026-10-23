import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s4_helpers.dart';

/// 新协议队列，握手完成后清空调用记录
MarkerSyncQueue v2(FakeMarkerTransport t, Set<Marker> markers,
    Set<MarkerImageResource> images,
    {void Function(MarkerSyncException)? onError,
    MarkerSyncCallbacks callbacks = const MarkerSyncCallbacks()}) {
  final MarkerSyncQueue q = MarkerSyncQueue(
      markers: markers,
      images: images,
      onSyncError: onError,
      callbacks: callbacks);
  q.attachTransport(t);
  return q;
}

void main() {
  test('T-RES-4 asset 失败后约 1s 重发，最终 ready', () {
    fakeAsync((FakeAsync async) {
      final MarkerImageResource a = asset('a');
      final FakeMarkerTransport t = FakeMarkerTransport();
      final MarkerSyncQueue q =
          v2(t, <Marker>{nm('p', 'P', iconId: a.id)}, <MarkerImageResource>{a});
      async.flushMicrotasks();
      t.calls.clear();
      q.handleMessage(imagesResult(1, failed: <String>['a']));
      expect(q.imageStatus['a']!.attempts, 1);
      async.elapse(const Duration(milliseconds: 999));
      expect(t.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      final SentCall retry = t.calls.single;
      expect(retry.method, 'markers#update');
      expect(imageIds(retry.map), <String>['a']);
      expect(idsIn(retry.map, 'markersToAdd'), isEmpty);
      expect(q.imageStatus['a']!.state, MarkerImageState.sent);
      q.handleMessage(imagesResult(2, ready: <String>['a']));
      expect(q.imageStatus['a']!.state, MarkerImageState.ready);
      expect(q.hasPendingTimers, isFalse);
    });
  });

  test('asset 最多重试 3 次（1s、4s、16s）', () {
    fakeAsync((FakeAsync async) {
      final MarkerImageResource a = asset('a');
      final FakeMarkerTransport t = FakeMarkerTransport();
      final MarkerSyncQueue q =
          v2(t, <Marker>{nm('p', 'P', iconId: a.id)}, <MarkerImageResource>{a});
      async.flushMicrotasks();
      t.calls.clear();
      for (int i = 1; i <= 4; i++) {
        q.handleMessage(imagesResult(i, failed: <String>['a']));
        async.elapse(const Duration(seconds: 20));
      }
      expect(t.calls, hasLength(3));
      expect(q.imageStatus['a']!.attempts, 4);
      expect(q.hasPendingTimers, isFalse);
    });
  });

  test('T-RES-5 字节资源解码失败不重发，错误回调一次', () {
    fakeAsync((FakeAsync async) {
      final List<NativeMarkerError> errors = <NativeMarkerError>[];
      final FakeMarkerTransport t = FakeMarkerTransport();
      final MarkerSyncQueue q = v2(
          t,
          <Marker>{nm('p', 'P', iconId: bytesImage.id)},
          <MarkerImageResource>{bytesImage},
          callbacks: MarkerSyncCallbacks(onNativeError: errors.add));
      async.flushMicrotasks();
      t.calls.clear();
      q.handleMessage(imagesResult(1, failed: <String>[bytesImage.id]));
      q.handleMessage(decodeError(2, bytesImage.id));
      async.elapse(const Duration(minutes: 1));
      expect(t.calls, isEmpty);
      expect(errors.single.code, NativeMarkerErrorCode.imageDecodeFailed);
      // 点位仍在基准中，由原生按降级绘制
      expect(q.confirmed.containsKey('p'), isTrue);
    });
  });

  test('T-RES-14 修改被拒时 resync 保留旧资源，合法修改后自动释放', () async {
    final MarkerImageResource a = bytesImage;
    final MarkerImageResource b = asset('b');
    final FakeMarkerTransport t = FakeMarkerTransport();
    final MarkerSyncQueue q =
        v2(t, <Marker>{nm('c', 'C', iconId: a.id)}, <MarkerImageResource>{a});
    await flush();
    t.calls.clear();
    t.reject(<String>['c']);
    q.setTarget(<Marker>{nm('c', 'C', iconId: b.id)}, <MarkerImageResource>{b});
    await flush();
    expect(t.calls.single.map['imageIdsToRelease'], isEmpty);
    expect(q.retainedImageIds, contains(a.id));
    // 原生报告资源缺失，触发 resync
    q.handleMessage(msg('marker#nativeError', 1, <String, Object?>{
      'code': 'imageMissing',
      'imageId': a.id,
      'message': 'missing',
    }));
    await flush();
    final Map<String, dynamic> resync = t.byMethod('markers#resync').single.map;
    final List<dynamic> images = resync['images'] as List<dynamic>;
    final Map<String, dynamic> imgA =
        images.cast<Map<String, dynamic>>().firstWhere(
            (Map<String, dynamic> m) => m['id'] == a.id);
    expect(imgA['data'], isNotNull);
    final Map<String, dynamic> c = (resync['markers'] as List<dynamic>).single;
    expect(c['nativePresentation']['content']['iconId'], a.id);
    // 合法修改成功后，无需再次重建也会发送 release A
    t.calls.clear();
    q.setTarget(
        <Marker>{nm('c', 'C2', iconId: b.id)}, <MarkerImageResource>{b});
    await flush();
    expect(methods(t), <String>['markers#update', 'markers#update']);
    expect(t.calls.last.map['imageIdsToRelease'], <String>[a.id]);
    expect(q.retainedImageIds, isNot(contains(a.id)));
    expect(q.imageStatus.containsKey(a.id), isFalse);
    expect(t.byMethod('markers#resync'), isEmpty); // 没有 imageMissing 循环
  });

  test('T-RES-15 释放在途时重新引用：副本不丢，确认后重新登记', () async {
    final MarkerImageResource a = asset('a');
    final FakeMarkerTransport t = FakeMarkerTransport();
    final MarkerSyncQueue q =
        v2(t, <Marker>{nm('c', 'C', iconId: a.id)}, <MarkerImageResource>{a});
    await flush();
    t.calls.clear();
    // 第 1 个请求只改点位（旧值可能被拒，A 仍受保护）；确认后自动发送释放
    t.next((SentCall c) async => FakeMarkerTransport.accepted(c));
    final Completer<Map<Object?, Object?>?> gate = t.hold();
    q.setTarget(<Marker>{nm('c', 'C')}, const <MarkerImageResource>{});
    await flush();
    expect(t.calls.first.map['imageIdsToRelease'], isEmpty);
    expect(t.calls.last.map['imageIdsToRelease'], <String>['a']);
    expect(q.retainedImageIds, contains('a')); // 释放未确认，副本保留
    q.setTarget(<Marker>{nm('c', 'C3', iconId: a.id)}, <MarkerImageResource>{a});
    gate.complete(FakeMarkerTransport.accepted(t.calls.last));
    await flush();
    t.calls.removeAt(0);
    expect(methods(t), <String>['markers#update', 'markers#update']);
    final Map<String, dynamic> p = t.calls.last.map;
    // 同一请求内原生先登记资源再处理点位（§6.2）
    expect(imageIds(p), <String>['a']);
    expect(idsIn(p, 'markersToChange'), <String>['c']);
    expect(q.imageStatus['a']!.state, MarkerImageState.sent);
    expect(q.retainedImageIds.where((String id) => id == 'a'), hasLength(1));
    expect(q.confirmedImageIds, <String>{'a'});
  });

  test('T-RES-16 恢复失败有界：无忙循环，销毁后不再重试', () {
    fakeAsync((FakeAsync async) {
      final List<MarkerSyncException> errors = <MarkerSyncException>[];
      final FakeMarkerTransport t = FakeMarkerTransport();
      final MarkerSyncQueue q =
          v2(t, <Marker>{nm('a', 'A')}, const <MarkerImageResource>{},
              onError: errors.add);
      async.flushMicrotasks();
      t.calls.clear();
      for (int i = 0; i < 10; i++) {
        t.fail();
      }
      q.setTarget(<Marker>{nm('a', 'A1')}, const <MarkerImageResource>{});
      async.elapse(const Duration(minutes: 1));
      expect(t.byMethod('markers#resync'), hasLength(2));
      expect(errors, isNotEmpty);
      expect(q.isBusy, isFalse);
      expect(q.hasPendingTimers, isFalse);
      // 外部新更新重新触发恢复；恢复计时器挂起时销毁，之后不再有调用
      q.setTarget(<Marker>{nm('a', 'A2')}, const <MarkerImageResource>{});
      async.flushMicrotasks();
      expect(q.hasPendingTimers, isTrue);
      final int before = t.calls.length;
      q.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(t.calls, hasLength(before));
    });
  });

  test('imageMissing 反复出现时 resync 次数有上限', () async {
    final List<MarkerSyncException> errors = <MarkerSyncException>[];
    final FakeMarkerTransport t = FakeMarkerTransport();
    final MarkerSyncQueue q = v2(t, <Marker>{nm('a', 'A')},
        const <MarkerImageResource>{},
        onError: errors.add);
    await flush();
    for (int i = 1; i <= 5; i++) {
      q.handleMessage(msg('marker#nativeError', i, <String, Object?>{
        'code': 'imageMissing',
        'imageId': 'x',
        'message': 'missing',
      }));
      await flush();
    }
    expect(t.byMethod('markers#resync'), hasLength(2));
    expect(errors, isNotEmpty);
  });
}
