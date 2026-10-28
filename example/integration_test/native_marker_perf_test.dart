// S18 性能场景（§13.4）：新路径与旧路径（Dart 生成 PNG + Marker.icon）同口径，每场景 30 次。
//   cold100 / cold200：全新且各不相同的价格（新路径前先 diag#clearCaches）
//   dup100：100 个点、20 种重复价格
//   viewport：缓存命中后的视野更新（100 点换 60 个已见过的价格）
//   toggle：价格层 100 点 ↔ 片区层 10 点反复切换（50 次，内存回到基线 ±10%）
// 每次记录：t0→t1（Dart）、t2→t4（原生）、校准后的 t0→t4 估算、drawCount、bytesReceived；
// 旧路径另记 PNG 生成耗时（Dart）。Android 每个场景前后由主机采 gfxinfo 与 meminfo。
// 运行：example/tool/s18_android_run.sh native_marker_perf_test.dart <设备>
//       example/tool/s18_ios_run.sh native_marker_perf_test.dart <udid>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:amap_map_example/const_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 's18_support.dart';

const int _runs = 30;

class _Host {
  _Host(this.out);
  final S18Out out;
  final ValueNotifier<Set<Marker>> markers =
      ValueNotifier<Set<Marker>>(<Marker>{});
  final List<MarkerUpdateReport> updates = <MarkerUpdateReport>[];
  AMapController? controller;
}

class _Page extends StatelessWidget {
  const _Page(this.h);
  final _Host h;

  @override
  Widget build(BuildContext context) {
    AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
    AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: h.markers,
      builder: (_, Set<Marker> m, __) => AMapWidget(
        initialCameraPosition:
            const CameraPosition(target: s18Center, zoom: 13),
        markers: m,
        onMapCreated: (AMapController c) => h.controller = c,
        onMarkerUpdateApplied: h.updates.add,
      ),
    );
  }
}

/// 一次更新的测量：t0 = 业务数据到达（开始构造点位）；旧路径的 PNG 生成算在 t0→t1 内，
/// 与业务现状一致。等到 dartT1 晚于 t0 的回执（即本次更新）后返回一条记录。
Future<Map<String, Object?>> _measure(WidgetTester tester, _Host h,
    MarkerClockCalibration cal, Future<Set<Marker>> Function() build) async {
  final int u0 = h.updates.length;
  final double t0 = MarkerDiagnosticsClock.nowMs();
  final Set<Marker> m = await build();
  final double built = MarkerDiagnosticsClock.nowMs();
  h.markers.value = m;
  // 立即刷一帧：AMapWidget 在这一帧里发出 markers#update；
  // 否则 t0→t1 会混入测试轮询等帧的间隔（最多 100ms），与插件无关
  await tester.pump();
  MarkerUpdateReport? r;
  final bool ok = await waitFor(tester, () {
    for (final MarkerUpdateReport x in h.updates.skip(u0)) {
      if ((x.dartT1Ms ?? -1) >= t0) {
        r = x; // 取本次更新最后一条（同一批可能拆成多次请求时取最后）
      }
    }
    return r != null && r!.t2ToT4Ms >= 0;
  }, timeoutMs: 15000);
  if (!ok) throw StateError('15s 内没有收到本次更新的 markers#applied');
  await settle(tester, 300); // 拆分请求时等后续回执
  for (final MarkerUpdateReport x in h.updates.skip(u0)) {
    if ((x.dartT1Ms ?? -1) >= t0) r = x;
  }
  final MarkerUpdateReport rr = r!;
  return <String, Object?>{
    'syncId': rr.syncId,
    'buildMs': built - t0,
    't0t1': rr.dartT1Ms! - t0,
    't2t3': rr.t2ToT3Ms,
    't2t4': rr.t2ToT4Ms,
    't0t4': cal.arrivalToAppliedMs(dartT0Ms: t0, nativeT4Ms: rr.nativeT4Ms),
    'rtt': rr.dartRoundTripMs,
    'applied': rr.appliedCount,
    'draws': rr.drawCount,
    'hits': rr.cacheHits,
    'misses': rr.cacheMisses,
    'pending': rr.pendingTasks,
    'bytes': rr.bytesReceived,
    'composite': rr.memory.compositeBytes,
    'decoded': rr.memory.decodedBytes,
  };
}

/// [n] 个价格点；texts[i] 为第 i 个点的文字。旧路径在 Dart 生成 PNG（同一文字只生成一次）
Future<Set<Marker>> _prices(List<String> texts, bool legacy, double dpr,
    {String prefix = 'p'}) async {
  if (!legacy) {
    return <Marker>{
      for (int i = 0; i < texts.length; i++)
        nativePrice('$prefix$i', gridPos(i), texts[i]),
    };
  }
  final Map<String, BitmapDescriptor> icons = <String, BitmapDescriptor>{};
  for (final String t in texts.toSet()) {
    icons[t] = await legacyPricePng(t, dpr);
  }
  return <Marker>{
    for (int i = 0; i < texts.length; i++)
      Marker(
          markerId: '$prefix$i',
          position: gridPos(i),
          icon: icons[texts[i]]!,
          infoWindowEnable: false),
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final S18Out out = S18Out('native_marker_perf_test.txt');

  testWidgets('S18 性能场景', (WidgetTester tester) async {
    final _Host h = _Host(out);
    await tester.pumpWidget(MaterialApp(home: _Page(h)));
    try {
      await settle(tester, 8000); // SDK 初始化与瓦片加载完成后再测
      expect(h.controller, isNotNull);
      final double dpr = tester.view.devicePixelRatio;
      out.record(<String, Object?>{
        'device': Platform.operatingSystemVersion,
        'dpr': dpr,
        'mode': const bool.fromEnvironment('dart.vm.product')
            ? 'release'
            : 'profile/debug',
      });
      for (final String sc in <String>[
        'cold100',
        'cold200',
        'dup100',
        'viewport'
      ]) {
        for (final bool legacy in <bool>[false, true]) {
          await _scenario(tester, h, sc, legacy, dpr);
        }
      }
      for (final bool legacy in <bool>[false, true]) {
        await _toggle(tester, h, legacy, dpr);
      }
      out.line('S18 PASS');
    } catch (e) {
      out.line('S18 FAIL: $e');
      rethrow;
    } finally {
      out.command('done');
      await settle(tester, 1500);
    }
  });
}

/// 场景 [sc] 跑 30 次；每次先清空点位（计入下一次的基线，不测）
Future<void> _scenario(
    WidgetTester tester, _Host h, String sc, bool legacy, double dpr) async {
  final String tag = '${sc}_${legacy ? 'legacy' : 'native'}';
  final MarkerClockCalibration pre = await h.controller!.calibrateNativeClock();
  out(h).command('gfxreset');
  int seed = 0;
  List<String> texts(int n, int kinds) => <String>[
        for (int i = 0; i < n; i++)
          '¥${1000 + (seed * 997 + i % kinds * 7) % 90000}',
      ];
  // viewport：先显示一次 100 个价格，之后每次换成其中 60 个（缓存命中）
  final List<String> seen = texts(100, 100);
  if (sc == 'viewport') {
    h.markers.value = await _prices(seen, legacy, dpr);
    await settle(tester, 2000);
  }
  for (int run = 0; run < _runs; run++) {
    seed = run + 1 + (sc.hashCode & 0xFF) * 31;
    if (sc != 'viewport') {
      h.markers.value = <Marker>{};
      await settle(tester, 600);
      if (!legacy && sc.startsWith('cold'))
        await h.controller!.clearNativeMarkerCaches();
    }
    final List<String> t = switch (sc) {
      'cold100' => texts(100, 100),
      'cold200' => texts(200, 200),
      'dup100' => texts(100, 20),
      _ => <String>[for (int i = 0; i < 60; i++) seen[(run * 7 + i) % 100]],
    };
    final Map<String, Object?> r = await _measure(
        tester,
        h,
        pre,
        () => _prices(t, legacy, dpr,
            prefix: sc == 'viewport' ? 'v${run % 2}_' : 'p'));
    out(h).record(<String, Object?>{'sc': tag, 'run': run, ...r});
    await settle(tester, 400);
  }
  final MarkerClockCalibration post =
      await h.controller!.calibrateNativeClock();
  out(h).record(<String, Object?>{
    'sc': tag,
    'calib': true,
    'preOffset': pre.offsetMs,
    'preHalf': pre.halfWidthMs,
    'postOffset': post.offsetMs,
    'postHalf': post.halfWidthMs,
  });
  out(h).command('gfxdump', tag);
  out(h).command('meminfo', tag);
  await settle(tester, 2500);
  h.markers.value = <Marker>{};
  await settle(tester, 1000);
}

S18Out out(_Host h) => h.out;

/// 价格 100 点 ↔ 片区 10 点切换 50 次（第一次之后都命中缓存）；记录每次切换耗时与切换前后内存
Future<void> _toggle(
    WidgetTester tester, _Host h, bool legacy, double dpr) async {
  final String tag = 'toggle_${legacy ? 'legacy' : 'native'}';
  final MarkerClockCalibration cal = await h.controller!.calibrateNativeClock();
  final List<String> priceTexts = <String>[
    for (int i = 0; i < 100; i++) '¥${5000 + i * 11}'
  ];
  final List<BitmapDescriptor?> areaIcons = <BitmapDescriptor?>[
    for (int i = 0; i < 10; i++)
      legacy ? await _areaPng('片区$i ${40 + i}套', dpr) : null,
  ];
  // 旧路径与业务一致：每次切回价格层都重新生成 PNG（片区图标也按业务每次生成）
  Future<Set<Marker>> prices() => _prices(priceTexts, legacy, dpr);
  Future<Set<Marker>> areas() async => <Marker>{
        for (int i = 0; i < 10; i++)
          _area('a$i', i, legacy,
              legacy ? await _areaPng('片区$i ${40 + i}套', dpr) : areaIcons[i]),
      };
  h.markers.value = await prices();
  await settle(tester, 3000);
  final int rss0 = ProcessInfo.currentRss;
  out(h).command('meminfo', '${tag}_before');
  out(h).command('gfxreset');
  await settle(tester, 3000);
  for (int i = 0; i < 50; i++) {
    final bool toArea = i.isEven;
    final Map<String, Object?> r =
        await _measure(tester, h, cal, toArea ? areas : prices);
    out(h).record(<String, Object?>{
      'sc': tag,
      'run': i,
      'to': toArea ? 'area' : 'price',
      ...r
    });
    await settle(tester, 300);
  }
  out(h).command('gfxdump', tag);
  await settle(tester, 3000);
  final int rss1 = ProcessInfo.currentRss;
  out(h).command('meminfo', '${tag}_after');
  await settle(tester, 3000);
  out(h).record(<String, Object?>{
    'sc': tag,
    'mem': true,
    'rssBefore': rss0,
    'rssAfter': rss1,
    'growth': (rss1 - rss0) / rss0,
  });
  h.markers.value = <Marker>{};
  await settle(tester, 1500);
}

/// 片区圆旧路径 PNG：蓝色圆 + 白字，56pt
Future<BitmapDescriptor> _areaPng(String text, double dpr) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  final double d = 56 * dpr;
  c.drawCircle(
      Offset(d / 2, d / 2), d / 2, Paint()..color = const Color(0xFF1E88E5));
  final TextPainter tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 11 * dpr, color: Colors.white)),
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: d);
  tp.paint(c, Offset((d - tp.width) / 2, (d - tp.height) / 2));
  final ui.Image img = await rec.endRecording().toImage(d.ceil(), d.ceil());
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

/// 片区圆（toggle 场景）
Marker _area(String id, int i, bool legacy, BitmapDescriptor? icon) => legacy
    ? Marker(
        markerId: id,
        position: gridPos(i * 20 + 5, step: 0.004),
        icon: icon!,
        infoWindowEnable: false,
        anchor: const Offset(0.5, 0.5))
    : Marker(
        markerId: id,
        position: gridPos(i * 20 + 5, step: 0.004),
        infoWindowEnable: false,
        nativePresentation: NativeMarkerPresentation(
          content: NativeMarkerContent(text: '片区$i ${40 + i}套'),
          style: const NativeMarkerStyle(
            background: NativeMarkerShapeBackground.circle(
                diameter: 56, fillColor: Color(0xFF1E88E5)),
            fontSize: 11,
            textColor: Color(0xFFFFFFFF),
          ),
        ),
      );
