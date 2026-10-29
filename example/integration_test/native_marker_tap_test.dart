// S18 真实点击集成测试：T-SEL-7（选中态未预热时点击）、T-DEL-5（Android：替换延迟期间点待删除点）、
// 连续点击 c1→c2（新路径 / 旧路径各 30 次）。
// 真实触摸由主机执行：
//   Android：example/tool/s18_android_run.sh native_marker_tap_test.dart（读 logcat 中 S18CMD tap x,y，物理像素）
//   iOS：example/tool/s18_ios_run.sh native_marker_tap_test.dart <udid> S14UITests/S14UITests/testS18Commands
//        测试绑定下 Flutter 语义不进无障碍树，命令写在一个不可点击的原生点位文字里（原生点位文字进无障碍树）。
import 'dart:async';
import 'dart:io';

import 'package:amap_map/amap_map.dart';
// 订阅原始通道事件，判断 markers#removed 与点击的先后（T-DEL-5）
// ignore: implementation_imports
import 'package:amap_map/src/core/amap_flutter_platform.dart';
// ignore: implementation_imports
import 'package:amap_map/src/core/map_event.dart';
import 'package:amap_map_example/const_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

import 's18_support.dart';

const int _red = 0xFFE53935; // 选中态底色
const LatLng _cmdPos = LatLng(39.9182, 116.3934); // iOS 命令点位：屏幕上方偏左

/// 测试与页面共享的状态
class _Host {
  _Host(this.out);
  final S18Out out;
  final ValueNotifier<Set<Marker>> markers =
      ValueNotifier<Set<Marker>>(<Marker>{});
  final ValueNotifier<String> iosCmd = ValueNotifier<String>('S18|0|wait|');
  final ValueNotifier<MarkerTransition> transition =
      ValueNotifier<MarkerTransition>(const MarkerTransition.immediate());
  final GlobalKey mapKey = GlobalKey();
  final List<MarkerUpdateReport> updates = <MarkerUpdateReport>[];
  final List<MarkerTapReport> taps = <MarkerTapReport>[];
  final List<MarkerSelectionChange> selections = <MarkerSelectionChange>[];
  final List<String> dartTaps = <String>[];
  AMapController? controller;
  int _iosSeq = 0;

  /// 主机命令：Android 打印 S18CMD（物理像素）；iOS 写进命令点位文字（点）
  void command(String op, [String args = '']) {
    if (Platform.isAndroid) {
      out.command(op, args);
    } else {
      iosCmd.value = 'S18|${++_iosSeq}|$op|$args';
    }
  }

  /// 在全局逻辑坐标处真实点击
  void tapAt(Offset g, double dpr) => command(
      'tap',
      Platform.isAndroid
          ? '${(g.dx * dpr).round()},${(g.dy * dpr).round()}'
          : '${g.dx.round()},${g.dy.round()}');

  /// 经纬度 → 全局逻辑坐标（Android 原生返回物理像素，iOS 返回点）
  Future<Offset> globalOf(LatLng at, double dpr) async {
    final ScreenCoordinate p = await controller!.toScreenCoordinate(at);
    final Offset local = Platform.isAndroid
        ? Offset(p.x / dpr, p.y / dpr)
        : Offset(p.x.toDouble(), p.y.toDouble());
    final RenderBox box =
        mapKey.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(local);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
      .shouldPropagateDevicePointerEvents = true; // 放行真实触摸
  final S18Out out = S18Out('native_marker_tap_test.txt');

  testWidgets('S18 点击：T-SEL-7、T-DEL-5、连续点击', (WidgetTester tester) async {
    final _Host h = _Host(out);
    await tester.pumpWidget(MaterialApp(home: _Page(h)));
    try {
      await settle(tester, 6000);
      expect(h.controller, isNotNull);
      await _tSel7(tester, h);
      await _continuous(tester, h);
      if (Platform.isAndroid) await _tDel5(tester, h);
      out.line('S18 PASS');
    } catch (e) {
      out.line('S18 FAIL: $e');
      rethrow;
    } finally {
      h.command('done');
      await settle(tester, 1500);
    }
  });
}

/// 点 [id] 一次并等待：onTap 到达 Dart 后再等最多 2s 收 tapApplied；返回该次回报
Future<MarkerTapReport?> _tap(
    WidgetTester tester, _Host h, String id, LatLng at,
    {double lift = 14}) async {
  final double dpr = tester.view.devicePixelRatio;
  for (int attempt = 0; attempt < 3; attempt++) {
    final int dart0 = h.dartTaps.length, taps0 = h.taps.length;
    final Offset g = await h.globalOf(at, dpr) - Offset(0, lift);
    h.tapAt(g, dpr);
    if (!await waitFor(tester, () => h.dartTaps.length > dart0,
        timeoutMs: 6000)) {
      continue; // 主机漏读或没点中，重发
    }
    await waitFor(tester, () => h.taps.length > taps0, timeoutMs: 2000);
    final MarkerTapReport? r = h.taps.length > taps0 ? h.taps.last : null;
    expect(h.dartTaps.last, id, reason: '点中了 ${h.dartTaps.last}，应为 $id');
    return r;
  }
  throw StateError('$id 连续 3 次没有点中');
}

/// T-SEL-7：普通态刚出现、选中态尚未预热时立即点击，最终显示选中态，点击期间没有空白。
/// 每轮一次放 200 个文字各不相同的可选点（预热队列排满），收到该次 markers#applied
/// （t4，普通态已在 SDK）后立刻点第 110 个。Android 回报 drawCount ≥ 1 说明点击时
/// 选中态还没预热；截图确认点位处为选中红色。
Future<void> _tSel7(WidgetTester tester, _Host h) async {
  final List<double> c1c2 = <double>[];
  int coldTaps = 0;
  final LatLng at = gridPos(110, step: 0.004); // 屏幕中心右上方，邻点 ≥ 78pt
  for (int i = 0; i < 30; i++) {
    final String id = 'sel7_${i}_110';
    final int u0 = h.updates.length;
    h.markers.value = <Marker>{
      for (int k = 0; k < 200; k++)
        nativePrice(
            'sel7_${i}_$k', gridPos(k, step: 0.004), '¥${20000 + i * 211 + k}',
            selectable: true, onTap: h.dartTaps.add),
    };
    expect(await waitFor(tester, () => h.updates.length > u0), isTrue,
        reason: '没有收到 $id 的 markers#applied');
    final MarkerTapReport? r = await _tap(tester, h, id, at);
    expect(r, isNotNull, reason: '$id 没有 tapApplied');
    expect(r!.path, MarkerTapPath.native);
    expect(h.selections.last.selectedId, id, reason: '没有选中 $id');
    c1c2.add(r.c1ToC2Ms);
    if (r.drawCount > 0) coldTaps++;
    if (i % 10 == 0) await _shotSelected(tester, h, '${id}_selected', at);
    await settle(tester, 1200); // 大于双击判定
  }
  h.out.record(<String, Object?>{
    'test': 'T-SEL-7',
    'n': c1c2.length,
    'coldTaps': coldTaps,
    'p50': pct(c1c2, .5),
    'p95': pct(c1c2, .95),
    'c1c2': c1c2,
  });
  await h.controller!.setSelectedMarker(null);
  h.markers.value = <Marker>{};
  await settle(tester, 1000);
  if (Platform.isAndroid) {
    expect(coldTaps, greaterThanOrEqualTo(1),
        reason: '30 次点击时选中态都已预热，没有覆盖 T-SEL-7 场景');
  }
}

/// 连续点击（§13.4）：新路径 n1 反复点 30 次（选中↔取消，缓存命中后 drawCount 应为 0）；
/// 旧路径 l1 反复点 30 次（每次 Dart 重新生成价格 PNG 重发，与业务现状相同）。
Future<void> _continuous(WidgetTester tester, _Host h) async {
  final double dpr = tester.view.devicePixelRatio;
  const LatLng nPos = LatLng(39.911187, 116.397451);
  const LatLng lPos = LatLng(39.907187, 116.397451);
  bool lSel = false;
  late Set<Marker> Function(BitmapDescriptor) build;
  Future<void> onLegacy(String id) async {
    h.dartTaps.add(id);
    lSel = !lSel;
    h.markers.value = build(await legacyPricePng('¥4100', dpr, selected: lSel));
  }

  build = (BitmapDescriptor icon) => <Marker>{
        nativePrice('n1', nPos, '¥3000',
            selectable: true, onTap: h.dartTaps.add),
        Marker(
            markerId: 'l1',
            position: lPos,
            icon: icon,
            infoWindowEnable: false,
            zIndex: lSel ? 99 : 1,
            onTap: onLegacy),
      };
  h.markers.value = build(await legacyPricePng('¥4100', dpr));
  await settle(tester, 2500);
  final Map<String, List<MarkerTapReport>> got =
      <String, List<MarkerTapReport>>{
    'native': <MarkerTapReport>[],
    'legacy': <MarkerTapReport>[],
  };
  for (final String id in <String>['n1', 'l1']) {
    for (int i = 0; i < 30; i++) {
      final MarkerTapReport? r =
          await _tap(tester, h, id, id == 'n1' ? nPos : lPos);
      expect(r, isNotNull, reason: '$id 第 $i 次没有 tapApplied');
      expect(r!.c2Ms, greaterThanOrEqualTo(r.c1Ms));
      got[id == 'n1' ? 'native' : 'legacy']!.add(r);
      await settle(tester, 1200);
    }
  }
  for (final MapEntry<String, List<MarkerTapReport>> e in got.entries) {
    final List<double> xs =
        e.value.map((MarkerTapReport r) => r.c1ToC2Ms).toList();
    h.out.record(<String, Object?>{
      'test': 'tap', 'path': e.key, 'n': xs.length,
      'p50': pct(xs, .5), 'p95': pct(xs, .95),
      // 前两次可能还在预热，之后应全部命中缓存
      'drawsAfterWarm': e.value
          .skip(2)
          .fold<int>(0, (int s, MarkerTapReport r) => s + r.drawCount),
      'c1c2': xs,
    });
  }
  h.markers.value = <Marker>{};
  await settle(tester, 1000);
}

/// 截图（map#takeSnapshot）确认锚点上方 6～24pt 处是选中态红色，不是空白
Future<void> _shotSelected(
    WidgetTester tester, _Host h, String name, LatLng at) async {
  final double dpr = tester.view.devicePixelRatio;
  final Uint8List? png = await h.controller!.takeSnapshot();
  h.out.image(name, png!);
  final ScreenCoordinate p = await h.controller!.toScreenCoordinate(at);
  final double k = Platform.isAndroid ? 1 : dpr; // 截图为物理像素
  final Offset a = Offset(p.x * k, p.y * k);
  final int red = (await Rgba.decode(png)).count(
      Rect.fromLTRB(
          a.dx - 16 * dpr, a.dy - 24 * dpr, a.dx + 16 * dpr, a.dy - 8 * dpr),
      _red);
  expect(red, greaterThan(40 * dpr * dpr), reason: '$name 点位处没有选中态（红色像素 $red）');
}

/// T-DEL-5（Android）：replaceWhenReady 1000ms 下用 200 个新点替换，旧点 r1 进入待删除；
/// 在 markers#removed 之前点 r1：onTap 照常（R-DEL-3），selectable 点同时产生选择事件。
/// iOS 替换同步完成、没有延迟期（R-DEL-6），不适用。
Future<void> _tDel5(WidgetTester tester, _Host h) async {
  const LatLng rPos = LatLng(39.909187, 116.397451);
  final List<String> removedIds = <String>[];
  final List<String> order = <String>[];
  final StreamSubscription<MarkerProtocolEvent> sub =
      (AMapFlutterPlatform.instance as dynamic)
          .onMarkerProtocolEvent(mapId: h.controller!.mapId)
          .listen((MarkerProtocolEvent e) {
    if (e.value.method == 'markers#removed') {
      final List<Object?> ids =
          e.value.args['markerIds'] as List<Object?>? ?? <Object?>[];
      removedIds.addAll(ids.whereType<String>());
      order.add('removed');
    } else if (e.value.method == 'marker#onTap') {
      order.add('tap:${e.value.args['markerId']}');
    }
  });
  int ok = 0;
  for (int round = 0; round < 5; round++) {
    // 每轮从“未选中”开始：上一轮的 r1 被删除后选中会被作废，这里再显式清一次
    await h.controller!.setSelectedMarker(null);
    h.transition.value = const MarkerTransition.immediate();
    h.markers.value = <Marker>{
      nativePrice('r1', rPos, '旧 $round',
          selectable: true, onTap: h.dartTaps.add),
    };
    await settle(tester, 2000);
    h.transition.value = const MarkerTransition.replaceWhenReady(
        timeout: Duration(milliseconds: 1000));
    await settle(tester, 300);
    order.clear();
    removedIds.clear();
    final int sel0 = h.selections.length, dart0 = h.dartTaps.length;
    // 新层：200 个各不相同的价格点（远离 r1），绘制需要数百毫秒
    h.markers.value = <Marker>{
      for (int i = 0; i < 200; i++)
        nativePrice('x${round}_$i', gridPos(i, step: 0.0011),
            '¥${10000 + round * 300 + i}'),
    };
    await settle(tester, 30);
    await _tap(tester, h, 'r1', rPos);
    await waitFor(tester, () => removedIds.contains('r1'), timeoutMs: 3000);
    final bool beforeRemoved = order.indexOf('tap:r1') >= 0 &&
        (order.indexOf('removed') < 0 ||
            order.indexOf('tap:r1') < order.indexOf('removed'));
    h.out.record(<String, Object?>{
      'test': 'T-DEL-5',
      'round': round,
      'order': order,
      'onTap': h.dartTaps.length - dart0,
      'selection': h.selections.length - sel0,
      'changes': h.selections
          .skip(sel0)
          .map((MarkerSelectionChange c) =>
              '${c.previousId}->${c.selectedId}/${c.reason.name}')
          .toList(),
      'beforeRemoved': beforeRemoved,
    });
    if (beforeRemoved) {
      ok++;
      expect(h.dartTaps.length - dart0, 1, reason: '待删除点 onTap 没有回调');
      // 选中或重复点击取消都算产生选择事件
      expect(
          h.selections.skip(sel0).any((MarkerSelectionChange c) =>
              c.selectedId == 'r1' || c.previousId == 'r1'),
          isTrue,
          reason: '待删除点没有选择事件：${h.selections.skip(sel0).toList()}');
    }
  }
  await sub.cancel();
  h.transition.value = const MarkerTransition.immediate();
  h.markers.value = <Marker>{};
  expect(ok, greaterThanOrEqualTo(1),
      reason: '5 轮都没能在 markers#removed 之前点中待删除点');
}

/// iOS 命令点位：不可点击、文字即命令，UI 测试按 label 前缀 "S18|" 读取
Marker _cmdMarker(String text) => Marker(
      markerId: 's18cmd',
      position: _cmdPos,
      clickable: false,
      infoWindowEnable: false,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        style: const NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF), cornerRadius: 2),
          fontSize: 9,
          textColor: Color(0xFF000000),
        ),
      ),
    );

class _Page extends StatelessWidget {
  const _Page(this.h);
  final _Host h;

  @override
  Widget build(BuildContext context) {
    AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
    AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);
    return Scaffold(
      body: Column(children: <Widget>[
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge(
                <Listenable>[h.markers, h.iosCmd, h.transition]),
            builder: (_, __) => AMapWidget(
              key: h.mapKey,
              initialCameraPosition:
                  const CameraPosition(target: s18Center, zoom: 15),
              markers: <Marker>{
                ...h.markers.value,
                if (Platform.isIOS) _cmdMarker(h.iosCmd.value),
              },
              markerSelection: const MarkerSelectionOptions(),
              markerTransition: h.transition.value,
              onMapCreated: (AMapController c) => h.controller = c,
              onMarkerUpdateApplied: h.updates.add,
              onMarkerTapApplied: h.taps.add,
              onMarkerSelectionChanged: h.selections.add,
            ),
          ),
        ),
        const SizedBox(height: 48),
      ]),
    );
  }
}
