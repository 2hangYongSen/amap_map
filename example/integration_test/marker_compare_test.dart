// AM-P02 对照页自动测试：原生点位 vs 缓存 PNG，同一页面、同一批数据，两种方案交替跑。
// 场景（每个点数各跑一遍）：
//   push_off   无负载推送一批全新价格
//   push_heavy 重负载（界面线程每帧空转 10ms + 300 个模糊粒子）下推送
//   pan_heavy  重负载 + 镜头连续平移中推送
//   tap        （仅 Android，200 点）连续点击 30 次，记录 c1→c2
//   mem        只跑 COMPARE_SCHEME 指定的一种方案：连续推送 20 批新价格，记录 RSS 与 meminfo
//              （不在默认场景里；两种方案各启动一次 App 跑）
// 每轮交替先后顺序（偶数轮原生先，奇数轮 PNG 先），切换方案时清空点位和两边缓存。
// 可选参数（--dart-define，经 S18_DEFINES 传给脚本）：
//   COMPARE_RUNS=30  COMPARE_COUNTS=200,500,1000  COMPARE_SCENARIOS=push_off,push_heavy,pan_heavy,tap
// 运行：S18_TIMEOUT=7200 example/tool/s18_android_run.sh marker_compare_test.dart <设备>
//       S18_DEFINES="--dart-define=COMPARE_COUNTS=200" example/tool/s18_ios_run.sh marker_compare_test.dart <udid>
// 内存不在这里比较：同一进程内先后跑两种方案，残留缓存会互相影响，需每种方案单独重启 App 测。
import 'dart:io';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map_example/const_config.dart';
import 'package:amap_map_example/pages/interactive/compare/compare_controller.dart';
import 'package:amap_map_example/pages/interactive/compare/compare_markers.dart';
import 'package:amap_map_example/pages/interactive/compare/flutter_load.dart';
import 'package:amap_map_example/pages/interactive/marker_compare_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

import 's18_support.dart';

const int _runs = int.fromEnvironment('COMPARE_RUNS', defaultValue: 30);
const String _counts =
    String.fromEnvironment('COMPARE_COUNTS', defaultValue: '200,500,1000');
const String _scenarios = String.fromEnvironment('COMPARE_SCENARIOS',
    defaultValue: 'push_off,push_heavy,pan_heavy,tap');

/// mem 场景只跑的方案（native / png）与推送批数
const String _memScheme = String.fromEnvironment('COMPARE_SCHEME');
const int _memRounds = int.fromEnvironment('COMPARE_MEM_ROUNDS', defaultValue: 20);

/// 真实时间等待；帧由引擎按 vsync 驱动（fullyLive），不用 tester.pump
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 像真实 App 一样按 vsync 出帧，掉帧统计和负载动画才真实；放行真实触摸（主机点击）
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.shouldPropagateDevicePointerEvents = true;
  final S18Out out = S18Out('marker_compare_test.txt');

  testWidgets('AM-P02 原生点位 vs 缓存 PNG', (WidgetTester tester) async {
    final CompareController c = CompareController();
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
      AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
      AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);
      return Scaffold(body: MarkerComparePage(controller: c));
    })));
    try {
      await settle(tester, 8000); // SDK 初始化与瓦片加载
      expect(c.map, isNotNull, reason: '8s 内地图没有创建');
      await _cmd(c, out, 'wait'); // iOS：先放出命令点位，UI 测试 60s 内要能找到它
      out.record(<String, Object?>{
        'device': Platform.operatingSystemVersion,
        'dpr': tester.view.devicePixelRatio,
        'refreshRate': tester.view.display.refreshRate,
        'runs': _runs,
      });
      final List<String> sc = _scenarios.split(',');
      for (final int n in _counts.split(',').map(int.parse)) {
        c.setCount(n);
        for (final String s in sc.where((String s) => s.startsWith('push') || s.startsWith('pan'))) {
          await _pushScenario(c, out, s, n);
        }
      }
      if (sc.contains('tap')) {
        await _tapScenario(tester, c, out);
      }
      if (sc.contains('mem')) {
        if (_memScheme.isEmpty) throw StateError('mem 场景需要 COMPARE_SCHEME=native 或 png');
        for (final int n in _counts.split(',').map(int.parse)) {
          await _memScenario(c, out, n);
        }
      }
      out.line('S18 PASS');
    } catch (e) {
      out.line('S18 FAIL: $e');
      rethrow;
    } finally {
      c.setLoad(FlutterLoad.off);
      if (c.map != null) await _cmd(c, out, 'done');
      await _wait(1500);
    }
  });
}

/// 点击场景（200 点、无负载）：分 10 块，每块两种方案各推一批，放大后点其中不重叠的点，先后顺序交替。
/// 每个点都是第一次被点；PNG 方案首次点击某价格要现生成选中态图标，这是它的真实成本。
Future<void> _tapScenario(
    WidgetTester tester, CompareController c, S18Out out) async {
  c
    ..setLoad(FlutterLoad.off)
    ..setCount(200);
  final Map<MarkerTapPath, List<double>> got = <MarkerTapPath, List<double>>{
    MarkerTapPath.native: <double>[],
    MarkerTapPath.icon: <double>[],
  };
  // 每块换一批数据（随机位置不同），zoom 15 下每批约能挑出 3 个不重叠的点；10 块约 30 次点击
  for (int block = 0; block < 10; block++) {
    final List<CompareScheme> order = block.isEven
        ? <CompareScheme>[CompareScheme.native, CompareScheme.png]
        : <CompareScheme>[CompareScheme.png, CompareScheme.native];
    for (final CompareScheme s in order) {
      await c.setScheme(s);
      await c.reset();
      await c.map!.moveCamera(
          CameraUpdate.newCameraPosition(
              const CameraPosition(target: compareCenter, zoom: 13)),
          animated: false);
      await _wait(800);
      await c.push();
      // 200 点铺满一屏时气泡互相重叠，点不准：放大两级，让可见的点之间拉开距离
      await c.map!.moveCamera(
          CameraUpdate.newCameraPosition(
              const CameraPosition(target: compareCenter, zoom: 15)),
          animated: false);
      await _wait(1500); // 原生方案的选中态在后台预热，给它与业务相近的时间
      final List<Offset> targets = await _targets(tester, c, 10);
      out.record(<String, Object?>{'sc': 'tap', 'scheme': s.name, 'targets': targets.length});
      for (final Offset p in targets) {
        final MarkerTapReport? r = await _tapAt(c, out, tester, p);
        if (r == null) continue; // 没点中或没回执：不计入，记一行便于排查
        got[r.path]!.add(r.c1ToC2Ms);
        out.record(<String, Object?>{
          'sc': 'tap', 'block': block, 'scheme': s.name, 'id': r.markerId,
          'c1c2': r.c1ToC2Ms, 'draws': r.drawCount,
        });
        await _wait(1500); // 大于双击判定间隔，避免地图放大
      }
    }
  }
  for (final MapEntry<MarkerTapPath, List<double>> e in got.entries) {
    if (e.value.isEmpty) throw StateError('点击场景 ${e.key.name} 没有有效样本');
    out.record(<String, Object?>{
      'summary': true, 'sc': 'tap', 'path': e.key.name, 'n': e.value.length,
      'c1c2P50': pct(e.value, 0.5), 'c1c2P95': pct(e.value, 0.95),
    });
  }
  await c.reset();
}

/// 选 [k] 个可点的点位：在地图可见范围内、离边缘 40pt 以上、与其他点相距 48pt 以上（避免点到重叠的点）。
/// 返回点击位置（全局逻辑坐标，气泡中心）
Future<List<Offset>> _targets(
    WidgetTester tester, CompareController c, int k) async {
  final double dpr = tester.view.devicePixelRatio;
  final Rect box = tester.getRect(find.byType(AMapWidget));
  final List<Offset> all = <Offset>[];
  for (final Marker m in c.markers) {
    final ScreenCoordinate s = await c.map!.toScreenCoordinate(m.position);
    // 原生返回地图视图内坐标：Android 物理像素，iOS 点
    final Offset local = Platform.isAndroid
        ? Offset(s.x / dpr, s.y / dpr)
        : Offset(s.x.toDouble(), s.y.toDouble());
    all.add(box.topLeft + local - const Offset(0, 18)); // 气泡中心在锚点上方约 18pt
  }
  final Rect safe = box.deflate(40);
  // iOS 命令点位所在位置：不点它附近（气泡在锚点上方，宽约 120pt）
  final Rect? cmdArea = Platform.isIOS
      ? Rect.fromLTWH(box.left, box.top, _cmdScreen.dx + 120, _cmdScreen.dy + 20)
      : null;
  final List<Offset> picked = <Offset>[];
  for (final Offset p in all) {
    if (!safe.contains(p) || (cmdArea?.contains(p) ?? false)) continue;
    // 气泡约 70×28pt：与其他点在水平或垂直方向拉开一个气泡以上，点击才不会落到别的点上
    final bool alone = all.every((Offset q) =>
        identical(p, q) || (p.dx - q.dx).abs() > 80 || (p.dy - q.dy).abs() > 36);
    if (alone) picked.add(p);
    if (picked.length == k) break;
  }
  return picked;
}

/// iOS 命令点位放在地图视图内的这个位置（逻辑点）；点击目标在 [_targets] 里避开它
const Offset _cmdScreen = Offset(90, 40);
int _iosSeq = 0;

/// 给主机的命令。iOS 写进一个不可点击的原生点位文字（UI 测试 testS18Commands 按 "S18|" 前缀读取）。
/// 镜头会变，每次按当前镜头把屏幕位置换算成坐标，保证命令点位一直在可见区域内。
Future<void> _cmd(CompareController c, S18Out out, String op, [String args = '']) async {
  if (Platform.isAndroid) {
    out.command(op, args);
    return;
  }
  final LatLng at = await c.map!.fromScreenCoordinate(
      ScreenCoordinate(x: _cmdScreen.dx.round(), y: _cmdScreen.dy.round()));
  c.setExtra(<Marker>{
    Marker(
      markerId: 's18cmd',
      position: at,
      clickable: false,
      infoWindowEnable: false,
      zIndex: 200,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: 'S18|${++_iosSeq}|$op|$args'),
        style: const NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF), cornerRadius: 2),
          fontSize: 9,
          textColor: Color(0xFF000000),
        ),
      ),
    ),
  });
}

/// 让主机点 [p]，等 Dart 的 onTap 和点击回执；任一超时返回 null
Future<MarkerTapReport?> _tapAt(
    CompareController c, S18Out out, WidgetTester tester, Offset p) async {
  final double dpr = tester.view.devicePixelRatio;
  final int taps0 = c.taps.length, dart0 = c.dartTaps.length;
  // Android：主机读 logcat，物理像素；iOS：UI 测试读命令点位，逻辑点
  await _cmd(c, out, 'tap', Platform.isAndroid
      ? '${(p.dx * dpr).round()},${(p.dy * dpr).round()}'
      : '${p.dx.round()},${p.dy.round()}');
  for (int i = 0; i < 40 && c.dartTaps.length == dart0; i++) {
    await _wait(100);
  }
  if (c.dartTaps.length == dart0) {
    out.record(<String, Object?>{'sc': 'tap', 'miss': true, 'x': p.dx, 'y': p.dy});
    return null;
  }
  for (int i = 0; i < 30 && c.taps.length == taps0; i++) {
    await _wait(100);
  }
  return c.taps.length > taps0 ? c.taps.last : null;
}

/// 内存场景：只跑 [_memScheme] 一种方案（每种方案单独启动一次 App，避免残留缓存互相影响）。
/// 基线 → 连续推送 [_memRounds] 批全新价格（每批后采样 RSS，取峰值）→ 清空并等待 → 结束值。
/// 同时让主机在三个时刻各抓一次 dumpsys meminfo（Native Heap / Graphics）。
Future<void> _memScenario(CompareController c, S18Out out, int n) async {
  final CompareScheme s = CompareScheme.values.byName(_memScheme);
  await c.setScheme(s);
  c
    ..setLoad(FlutterLoad.off)
    ..setCount(n);
  await c.reset();
  await _wait(3000);
  final String tag = 'mem_${s.name}_$n';
  final int rss0 = ProcessInfo.currentRss;
  out.command('meminfo', '${tag}_base');
  await _wait(2000);
  int peak = rss0;
  for (int i = 0; i < _memRounds; i++) {
    await c.push();
    peak = ProcessInfo.currentRss > peak ? ProcessInfo.currentRss : peak;
  }
  out.command('meminfo', '${tag}_peak');
  await _wait(2000);
  await c.reset();
  await _wait(5000); // 给原生缓存淘汰与 GC 一点时间
  final int rss1 = ProcessInfo.currentRss;
  out.command('meminfo', '${tag}_end');
  await _wait(2000);
  // 再做 4 次“推送 2 批 → 清空”，记每次清空后的 RSS：稳定说明是缓存，一直上涨才是泄漏
  final List<double> cycles = <double>[rss1 / 1048576];
  for (int k = 0; k < 4; k++) {
    await c.push();
    await c.push();
    await c.reset();
    await _wait(5000);
    cycles.add(ProcessInfo.currentRss / 1048576);
  }
  out.command('meminfo', '${tag}_cycle');
  await _wait(2000);
  out.record(<String, Object?>{
    'summary': true, 'sc': 'mem', 'n': n, 'scheme': s.name, 'rounds': _memRounds,
    'rssBaseMB': rss0 / 1048576, 'rssPeakMB': peak / 1048576, 'rssEndMB': rss1 / 1048576,
    'rssCyclesMB': cycles,
  });
}

/// 一个推送场景：每轮两种方案各推一次，先后顺序交替
Future<void> _pushScenario(
    CompareController c, S18Out out, String sc, int n) async {
  c.setLoad(sc.endsWith('heavy') ? FlutterLoad.heavy : FlutterLoad.off);
  final Map<CompareScheme, List<PushResult>> got =
      <CompareScheme, List<PushResult>>{
    for (final CompareScheme s in CompareScheme.values) s: <PushResult>[]
  };
  for (int run = 0; run < _runs; run++) {
    final List<CompareScheme> order = run.isEven
        ? <CompareScheme>[CompareScheme.native, CompareScheme.png]
        : <CompareScheme>[CompareScheme.png, CompareScheme.native];
    for (final CompareScheme s in order) {
      await c.setScheme(s);
      await c.reset(); // 同一方案连续两次时也要清空
      await _wait(800);
      final PushResult? r =
          sc.startsWith('pan') ? await c.panAndPush() : await c.push();
      if (r == null || !r.done) {
        throw StateError('$sc/${s.name}/$n 第 $run 轮没有收到 markers#applied');
      }
      got[s]!.add(r);
      out.record(<String, Object?>{'sc': sc, 'n': n, 'run': run, ..._row(r)});
    }
  }
  for (final CompareScheme s in CompareScheme.values) {
    out.record(<String, Object?>{
      'summary': true, 'sc': sc, 'n': n, 'scheme': s.name,
      ..._summary(got[s]!),
    });
  }
  c.setLoad(FlutterLoad.off);
  await c.reset();
}

Map<String, Object?> _row(PushResult r) => <String, Object?>{
      'scheme': r.scheme.name,
      'buildMs': r.buildMs,
      'pngCount': r.pngGenerated,
      't0t1': r.t0t1,
      't2t4': r.t2t4,
      't0t4': r.t0t4,
      'draws': r.draws,
      'bytes': r.bytes,
      'frames': r.frames,
      'jankBuild': r.jankBuild,
      'jankRaster': r.jankRaster,
      'dropped': r.dropped,
      'worstMs': r.worstFrameMs,
      'windowMs': r.windowMs,
      'thermal': r.thermal,
    };

/// P50 / P95；卡顿帧取每轮的分位数
Map<String, Object?> _summary(List<PushResult> rs) {
  Map<String, double> p(String k, double? Function(PushResult) f) {
    final List<double> xs = <double>[
      for (final PushResult r in rs)
        if (f(r) != null) f(r)!
    ];
    return <String, double>{'${k}P50': pct(xs, 0.5), '${k}P95': pct(xs, 0.95)};
  }

  return <String, Object?>{
    ...p('build', (PushResult r) => r.buildMs),
    ...p('t0t4', (PushResult r) => r.t0t4),
    ...p('t2t4', (PushResult r) => r.t2t4),
    ...p('jank', (PushResult r) =>
        ((r.jankBuild ?? 0) + (r.jankRaster ?? 0)).toDouble()),
    ...p('dropped', (PushResult r) => r.dropped?.toDouble()),
    ...p('worst', (PushResult r) => r.worstFrameMs),
    ...p('kb', (PushResult r) => r.bytes / 1024),
  };
}
