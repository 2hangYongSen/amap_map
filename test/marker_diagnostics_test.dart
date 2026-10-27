import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s4_helpers.dart';

/// 模拟一次 ping：Dart 在 d0 发出，经去程延迟到达原生（处理中读取原生时钟），
/// 再经回程延迟回到 Dart。原生时钟 = Dart 时钟 + offset。
MarkerClockSample _ping(double d0,
        {required double offset,
        required double up,
        required double proc,
        required double down}) =>
    MarkerClockSample(
      d0Ms: d0,
      nativeMs: d0 + up + proc / 2 + offset,
      d1Ms: d0 + up + proc + down,
    );

Map<String, Object?> _receipt(int syncId, {double t2 = 1000, double t4 = 1010}) =>
    <String, Object?>{
      'syncId': syncId,
      'nativeT2Ms': t2,
      'nativeT2vMs': t2 + 0.1,
      'markerColor': 0xFF00C853,
      'nativeT4Ms': t4,
      't2ToT3Ms': 2.0,
      't2ToT4Ms': t4 - t2,
      'appliedCount': 3,
      'drawCount': 2,
      'cacheHits': 1,
      'cacheMisses': 2,
      'bytesReceived': 128,
      'pendingTasks': 1,
      'memory': <String, Object?>{
        'compositeBytes': 4096,
        'decodedBytes': 1024,
        'compositeOverBudget': false,
        'decodedOverBudget': true,
      },
    };

void main() {
  group('T-TIME-2 时钟校准（R-TIME-3）', () {
    test('不对称延迟与偏移漂移：区间包含真实偏移，t0→t4 按统一单位计算', () {
      // 前 20 次偏移 5000ms，后 20 次漂移到 5000.4ms；去程比回程慢很多
      final List<MarkerClockSample> before = <MarkerClockSample>[
        for (int i = 0; i < 20; i++)
          _ping(100.0 + i * 10,
              offset: 5000, up: 3 + (i % 5) * 0.7, proc: 0.2, down: 0.4),
      ];
      final List<MarkerClockSample> after = <MarkerClockSample>[
        for (int i = 0; i < 20; i++)
          _ping(900.0 + i * 10,
              offset: 5000.4, up: 2.5 + (i % 3), proc: 0.3, down: 0.6),
      ];
      final MarkerClockCalibration pre = MarkerClockCalibration.fromSamples(before);
      final MarkerClockCalibration post = MarkerClockCalibration.fromSamples(after);
      // 选最短往返；真实偏移落在 [n−d1, n−d0]
      expect(pre.best.rttMs, closeTo(3.6, 1e-9));
      expect(pre.lowerMs, lessThanOrEqualTo(5000));
      expect(pre.upperMs, greaterThanOrEqualTo(5000));
      expect(post.lowerMs, lessThanOrEqualTo(5000.4));
      expect(post.upperMs, greaterThanOrEqualTo(5000.4));
      expect(pre.halfWidthMs, closeTo(pre.best.rttMs / 2, 1e-9));
      // 不对称时中点估计有偏差，但不超过半宽
      expect((pre.offsetMs - 5000).abs(), lessThanOrEqualTo(pre.halfWidthMs));
      // 漂移在报告中可见
      expect(post.offsetMs - pre.offsetMs, closeTo(0.4, 0.5));

      // 数据在 Dart t0=500 到达，原生 t4 = 真实 Dart 时刻 523 + 偏移
      const double t0 = 500;
      const double trueDartT4 = 523;
      const double nativeT4 = trueDartT4 + 5000;
      final double est = pre.arrivalToAppliedMs(dartT0Ms: t0, nativeT4Ms: nativeT4);
      expect(est, closeTo(nativeT4 - pre.offsetMs - t0, 1e-9));
      expect((est - (trueDartT4 - t0)).abs(), lessThanOrEqualTo(pre.halfWidthMs));
      expect(pre.toDartMs(nativeT4), closeTo(nativeT4 - pre.offsetMs, 1e-9));
    });

    test('不用更新请求往返/2 当单向传输：回执往返只作“通道往返”报告', () {
      const MarkerUpdateReport r = MarkerUpdateReport(
        syncId: 1,
        nativeT2Ms: 0,
        nativeT4Ms: 0,
        t2ToT3Ms: 30,
        t2ToT4Ms: 30,
        appliedCount: 1,
        drawCount: 0,
        cacheHits: 0,
        cacheMisses: 0,
        bytesReceived: 0,
        dartT1Ms: 10,
        dartReturnMs: 45,
      );
      // 往返 35ms 中原生处理就占了 30ms，往返/2=17.5 不能代表单向传输
      expect(r.dartRoundTripMs, 35);
      expect(r.dartRoundTripMs! - r.t2ToT3Ms, 5);
    });

    test('没有样本时报错', () {
      expect(() => MarkerClockCalibration.fromSamples(<MarkerClockSample>[]),
          throwsArgumentError);
    });

    test('会话时钟单调', () {
      final double a = MarkerDiagnosticsClock.nowMs();
      final double b = MarkerDiagnosticsClock.nowMs();
      expect(b, greaterThanOrEqualTo(a));
    });
  });

  group('队列中的诊断（T-TIME-3/5 Dart 部分）', () {
    const MarkerSyncOptions on = MarkerSyncOptions(diagnostics: true);

    MarkerSyncQueue queue({
      MarkerSyncOptions options = on,
      List<MarkerUpdateReport>? reports,
      List<MarkerTapReport>? taps,
      Set<Marker>? markers,
    }) =>
        MarkerSyncQueue(
          markers: markers ?? <Marker>{nm('a', '1')},
          options: options,
          callbacks: MarkerSyncCallbacks(
            onUpdateApplied: reports?.add,
            onTapApplied: taps?.add,
          ),
        );

    test('诊断开启即启用新协议，创建参数带 markerDiagnostics', () {
      final MarkerSyncQueue q =
          queue(markers: <Marker>{im('i')}, options: on);
      expect(q.createdAsV2, isTrue);
      expect(q.creationParams['markerDiagnostics'], isTrue);
      expect(queue(markers: <Marker>{im('i')}, options: const MarkerSyncOptions())
          .createdAsV2, isFalse);
    });

    test('回执先于返回到达：返回后交付，补上 t1 与返回时刻', () async {
      final List<MarkerUpdateReport> reports = <MarkerUpdateReport>[];
      final MarkerSyncQueue q = queue(reports: reports);
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      final Completer<Map<Object?, Object?>?> gate = t.hold();
      q.setTarget(<Marker>{nm('a', '2')}, const <MarkerImageResource>{});
      await flush();
      final int syncId = t.calls.last.map['syncId'] as int;
      // Android 同步应用时，原生在返回前就发出回执
      q.handleMessage(msg('markers#applied', 10, _receipt(syncId)));
      expect(reports, isEmpty);
      gate.complete(FakeMarkerTransport.accepted(t.calls.last));
      await flush();
      expect(reports, hasLength(1));
      final MarkerUpdateReport r = reports.single;
      expect(r.syncId, syncId);
      expect(r.t2ToT4Ms, 10);
      expect(r.nativeT2vMs, closeTo(1000.1, 1e-9));
      expect(r.markerColor, 0xFF00C853);
      expect(r.pendingTasks, 1);
      expect(r.memory.decodedOverBudget, isTrue);
      expect(r.dartT1Ms, isNotNull);
      expect(r.dartRoundTripMs, greaterThanOrEqualTo(0));
    });

    test('回执晚于返回到达：到达时立即交付', () async {
      final List<MarkerUpdateReport> reports = <MarkerUpdateReport>[];
      final MarkerSyncQueue q = queue(reports: reports);
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      q.setTarget(<Marker>{nm('a', '2')}, const <MarkerImageResource>{});
      await flush();
      expect(reports, isEmpty);
      final int syncId = t.calls.last.map['syncId'] as int;
      q.handleMessage(msg('markers#applied', 10, _receipt(syncId)));
      expect(reports.single.dartReturnMs, isNotNull);
    });

    test('T-TIME-5 旧路径：onTap 的 tapId 写进紧接着的那次 markers#update', () async {
      final List<MarkerTapReport> taps = <MarkerTapReport>[];
      final MarkerSyncQueue q =
          queue(markers: <Marker>{im('i'), im('j')}, taps: taps);
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      q.handleMessage(msg('marker#onTap', 3,
          <String, Object?>{'markerId': 'i', 'tapId': 7}));
      // 业务在 onTap 中重新生成图标：只改 j 的那次不带 tapId
      q.setTarget(<Marker>{im('i'), im('j', lat: 31)},
          const <MarkerImageResource>{});
      await flush();
      expect(t.calls.last.map.containsKey('diagTapId'), isFalse);
      q.setTarget(<Marker>{im('i', lat: 32), im('j', lat: 31)},
          const <MarkerImageResource>{});
      await flush();
      expect(t.calls.last.map['diagTapId'],
          <String, Object?>{'tapId': 7, 'markerId': 'i'});
      // 只带一次
      q.setTarget(<Marker>{im('i', lat: 33), im('j', lat: 31)},
          const <MarkerImageResource>{});
      await flush();
      expect(t.calls.last.map.containsKey('diagTapId'), isFalse);
      // 原生 c1、c2 回到 Dart
      q.handleMessage(msg('markers#tapApplied', 4, <String, Object?>{
        'tapId': 7,
        'markerId': 'i',
        'c1Ms': 100.0,
        'c2Ms': 161.5,
        'path': 'icon',
      }));
      expect(taps.single.c1ToC2Ms, closeTo(61.5, 1e-9));
      expect(taps.single.path, MarkerTapPath.icon);
    });

    test('T-TIME-3 关闭时：不带 diagTapId、不交付回执、无诊断通道调用', () async {
      final List<MarkerUpdateReport> reports = <MarkerUpdateReport>[];
      final List<MarkerTapReport> taps = <MarkerTapReport>[];
      final MarkerSyncQueue q = queue(
          options: const MarkerSyncOptions(),
          reports: reports,
          taps: taps);
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      q.handleMessage(msg('marker#onTap', 1,
          <String, Object?>{'markerId': 'a', 'tapId': 1}));
      q.setTarget(<Marker>{nm('a', '2')}, const <MarkerImageResource>{});
      await flush();
      q.handleMessage(msg('markers#applied', 2, _receipt(1)));
      q.handleMessage(msg('markers#tapApplied', 3, <String, Object?>{
        'tapId': 1,
        'markerId': 'a',
        'c1Ms': 1.0,
        'c2Ms': 2.0,
      }));
      expect(t.calls.any((SentCall c) => c.map.containsKey('diagTapId')),
          isFalse);
      expect(t.calls.any((SentCall c) => c.method.startsWith('diag#')),
          isFalse);
      expect(t.calls.map((SentCall c) => c.method),
          <String>['markers#attach', 'markers#update']);
      expect(reports, isEmpty);
      expect(taps, isEmpty);
    });

    test('运行中开启：先 attach，再发 markerDiagnostics: true；关闭时发 false', () async {
      final MarkerSyncQueue q = queue(
          markers: <Marker>{im('i')}, options: const MarkerSyncOptions());
      final FakeMarkerTransport t = FakeMarkerTransport();
      q.attachTransport(t);
      await flush();
      q.setOptions(on);
      await flush();
      expect(t.calls.map((SentCall c) => c.method),
          <String>['markers#attach', 'map#update']);
      expect(t.calls.last.map['markerDiagnostics'], isTrue);
      q.setOptions(const MarkerSyncOptions());
      await flush();
      expect(t.calls.last.map['markerDiagnostics'], isFalse);
    });
  });
}
