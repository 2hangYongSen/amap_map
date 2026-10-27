// S17：真机真实点击计时。新路径（原生选中）与旧路径（Dart 重新生成图标）各点 3 次，
// 核对 markers#tapApplied 的 c1→c2（T-TIME-5）；随后关闭诊断，核对无回执、ping 报错（T-TIME-3）。
// 真实触摸由主机执行：
//   Android：example/tool/s17_android_run.sh 读 logcat 中的 `S17CMD 序号 tap x,y`（物理像素）后 root input tap；
//   iOS：example/tool/s17_ios_run.sh 运行 UI 测试 S14UITests/testS17Taps，按固定顺序点原生点位视图
//   （n1×3、l1×3、停顿后 n1、l1），结果写到 App tmp/s17_result.txt 由脚本取回。
import 'dart:io';
import 'dart:ui' as ui;

import 'dart:async';

import 'package:amap_map/amap_map.dart';
// 直接订阅原始通道事件，核对原生是否真的停发（T-TIME-3）
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

const LatLng _center = LatLng(39.909187, 116.397451);
const LatLng _nativePos = LatLng(39.911187, 116.397451);
const LatLng _legacyPos = LatLng(39.907187, 116.397451);

// 旧路径图标：96×96 圆形 PNG（点击目标够大），每次点击在 Dart 重新生成（与业务现状相同）
Future<BitmapDescriptor> _png(Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawCircle(const Offset(48, 48), 44, Paint()..color = color);
  final ui.Image image = await recorder.endRecording().toImage(96, 96);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

// 新路径点位：可选中，选中态换底色
Marker _nativeMarker(void Function() onTap) => Marker(
      markerId: 'n1',
      position: _nativePos,
      selectable: true,
      infoWindowEnable: false,
      onTap: (_) => onTap(),
      nativePresentation: const NativeMarkerPresentation(
        content: NativeMarkerContent(text: '¥3000'),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF), cornerRadius: 6),
          fontSize: 15,
          textColor: Color(0xFFE53935),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          arrow: NativeMarkerArrow(width: 10, height: 6),
        ),
        selectedStyle: NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFE53935), cornerRadius: 6),
          fontSize: 15,
          textColor: Color(0xFFFFFFFF),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          arrow: NativeMarkerArrow(width: 10, height: 6),
        ),
      ),
    );

void main() {
  // 测试绑定默认拦截真实触摸，这里放行，主机点击才能到达地图
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
      .shouldPropagateDevicePointerEvents = true;

  Future<void> settle(WidgetTester tester, int ms) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('真实点击 c1→c2 与诊断关闭', (WidgetTester tester) async {
    final _Host h = _Host();
    final File result = File('${Directory.systemTemp.path}/s17_result.txt');
    if (result.existsSync()) result.deleteSync(); // 清掉上一轮
    await tester.pumpWidget(MaterialApp(home: _Page(h)));
    try {
      await settle(tester, 6000);
      expect(h.controller, isNotNull);
      // 原生发来的诊断消息：回执、点击计时、带 tapId 的 onTap
      int rawDiag = 0;
      final StreamSubscription<MarkerProtocolEvent> sub = (AMapFlutterPlatform
              .instance as dynamic)
          .onMarkerProtocolEvent(mapId: h.controller!.mapId)
          .listen((MarkerProtocolEvent e) {
        final String m = e.value.method;
        if (m == 'markers#applied' ||
            m == 'markers#tapApplied' ||
            e.value.args['tapId'] != null) {
          rawDiag++;
        }
      });
      bool red = false;
      late void Function() onLegacyTap;
      Future<Set<Marker>> build() async => <Marker>{
            _nativeMarker(() => h.dartTaps.add('n1')),
            Marker(
              markerId: 'l1',
              position: _legacyPos,
              infoWindowEnable: false,
              icon: await _png(red ? Colors.red : Colors.blue),
              onTap: (_) => onLegacyTap(),
            ),
          };
      // 旧路径：每次点击在 Dart 重新生成 PNG 并重发，原生在 setIcon 返回时记 c2
      onLegacyTap = () async {
        h.dartTaps.add('l1');
        red = !red;
        h.markers.value = await build();
      };
      h.markers.value = await build();
      await settle(tester, 3000);
      expect(h.updates, isNotEmpty, reason: '诊断开启后应收到 markers#applied');
      // 新路径 3 次（选中→重复点击取消→选中），旧路径 3 次（每次重发 PNG）
      final List<MarkerTapReport> got = <MarkerTapReport>[];
      for (final String id in <String>['n1', 'n1', 'n1', 'l1', 'l1', 'l1']) {
        final MarkerTapReport? r = await _tap(tester, h, id, settle);
        expect(r, isNotNull, reason: '$id 点击后没有收到 markers#tapApplied');
        expect(r!.markerId, id);
        expect(r.path, id == 'n1' ? MarkerTapPath.native : MarkerTapPath.icon);
        expect(r.c2Ms, greaterThanOrEqualTo(r.c1Ms)); // T-TIME-5
        got.add(r);
        await settle(tester, 1500); // 间隔大于双击判定，避免地图放大
      }
      expect(h.dartTaps.length, greaterThanOrEqualTo(6), reason: 'onTap 照常回调');
      h.summary = 'taps ${got.map((MarkerTapReport r) => '${r.markerId}/${r.path.name}='
          '${r.c1ToC2Ms.toStringAsFixed(2)}ms').join(' ')}';
      h.status('S17 ${h.summary}');
      // T-TIME-3：关闭诊断后，点击与更新都不再有回执，ping 报错
      h.diagnostics.value = false;
      await settle(tester, 2000);
      final int updates0 = h.updates.length, taps0 = h.taps.length;
      expect(rawDiag, greaterThan(0), reason: '开启时应收到原始诊断消息');
      final int raw0 = rawDiag;
      final int dart0 = h.dartTaps.length;
      for (final String id in <String>['n1', 'l1']) {
        final MarkerTapReport? r = await _tap(tester, h, id, settle);
        expect(r, isNull, reason: '关闭诊断后 $id 仍有 tapApplied');
        await settle(tester, 1500);
      }
      expect(h.dartTaps.length, dart0 + 2, reason: '关闭诊断不影响 onTap');
      expect(h.updates.length, updates0, reason: '关闭诊断后仍有 markers#applied');
      expect(h.taps.length, taps0);
      expect(rawDiag, raw0, reason: '关闭后原生仍发出诊断消息（含旧路径重发 PNG 的更新）');
      await sub.cancel();
      await expectLater(h.controller!.pingNativeClock(),
          throwsA(isA<PlatformException>()));
      h.status('S17 PASS | ${h.summary}');
    } catch (e) {
      h.status('S17 FAIL: $e | ${h.summary}');
      rethrow;
    } finally {
      h.command('done', '');
      await settle(tester, 1500);
    }
  });
}

// 让主机点 id 对应点位，等回执；最多重试 2 次（主机偶尔漏读命令）
Future<MarkerTapReport?> _tap(WidgetTester tester, _Host h, String id,
    Future<void> Function(WidgetTester, int) settle) async {
  final AMapController c = h.controller!;
  final double dpr = tester.view.devicePixelRatio;
  if (Platform.isIOS) {
    // iOS：UI 测试按固定节奏直接点原生点位视图（Flutter 语义树在测试绑定下不进无障碍树）
    // 按序号计数：点击可能在上一步等待期间提前到达
    final int want = ++h.iosTapCount;
    h.status('S17 wait $id #$want');
    for (int i = 0; i < 200 && h.dartTaps.length < want; i++) {
      await settle(tester, 100);
    }
    if (h.dartTaps.length < want) throw StateError('$id 20s 内没有收到点击');
    if (h.dartTaps[want - 1] != id) throw StateError('第 $want 次点中 ${h.dartTaps[want - 1]}，应为 $id');
    for (int i = 0; i < 10 && h.taps.length <= h.iosReportSeen; i++) {
      await settle(tester, 100);
    }
    if (h.taps.length <= h.iosReportSeen) return null;
    return h.taps[h.iosReportSeen++];
  }
  for (int attempt = 0; attempt < 3; attempt++) {
    // 相机复位后再换算坐标（误判为双击时地图会放大，旧坐标失效）
    await c.moveCamera(
        CameraUpdate.newCameraPosition(
            const CameraPosition(target: _center, zoom: 15)),
        animated: false);
    await settle(tester, 300);
    final ScreenCoordinate p =
        await c.toScreenCoordinate(id == 'n1' ? _nativePos : _legacyPos);
    // 原生返回地图视图内坐标：Android 物理像素，iOS 点
    final Offset local = Platform.isAndroid
        ? Offset(p.x / dpr, p.y / dpr)
        : Offset(p.x.toDouble(), p.y.toDouble());
    final RenderBox box =
        h.mapKey.currentContext!.findRenderObject()! as RenderBox;
    // 气泡 / 图标都在锚点上方，点它们的中心
    final Offset g = box.localToGlobal(local) - Offset(0, id == 'n1' ? 22 : 16);
    final int before = h.taps.length, dartBefore = h.dartTaps.length;
    if (attempt > 0) h.status('S17 retry $id #$attempt');
    h.command('tap', Platform.isAndroid
        ? '${(g.dx * dpr).round()},${(g.dy * dpr).round()}'
        : '${g.dx.round()},${g.dy.round()}');
    // 先等 Dart 的 onTap（证明点中了），再多等 1s 收回执
    for (int i = 0; i < 40 && h.dartTaps.length == dartBefore; i++) {
      await settle(tester, 100);
    }
    if (h.dartTaps.length == dartBefore) continue; // 没点中，重发
    for (int i = 0; i < 10 && h.taps.length == before; i++) {
      await settle(tester, 100);
    }
    return h.taps.length > before ? h.taps.last : null;
  }
  throw StateError('$id 连续 3 次没有点中（onTap 未回调）');
}

// 测试与页面共享的状态：点位、诊断开关、给主机的命令
class _Host {
  final ValueNotifier<Set<Marker>> markers = ValueNotifier<Set<Marker>>(<Marker>{});
  final ValueNotifier<bool> diagnostics = ValueNotifier<bool>(true);
  final ValueNotifier<String> cmd = ValueNotifier<String>('0|wait|');
  final ValueNotifier<String> log = ValueNotifier<String>('');
  final GlobalKey mapKey = GlobalKey();
  final List<MarkerUpdateReport> updates = <MarkerUpdateReport>[];
  final List<MarkerTapReport> taps = <MarkerTapReport>[];
  final List<String> dartTaps = <String>[];
  AMapController? controller;
  String summary = '';
  int iosTapCount = 0, iosReportSeen = 0;
  int _seq = 0;

  // 命令：iOS 由 UI 测试读文字；Android 由主机脚本读 logcat（物理像素）
  void command(String op, String args) {
    _seq++;
    cmd.value = '$_seq|$op|$args';
    // ignore: avoid_print
    print('S17CMD $_seq $op $args');
  }

  void status(String s) {
    log.value = s;
    // ignore: avoid_print
    print(s);
    // iOS 由主机用 devicectl 从 App 的 tmp 目录取回
    File('${Directory.systemTemp.path}/s17_result.txt')
        .writeAsStringSync('$s\n', mode: FileMode.append);
  }
}
class _Page extends StatelessWidget {
  const _Page(this.h);
  final _Host h;

  @override
  Widget build(BuildContext context) {
    AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
    AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);
    return Scaffold(
      body: Column(children: <Widget>[
        Expanded(child: _map()),
        // UI 测试按 identifier 读命令；放在地图下方，不挡点位
        ValueListenableBuilder<String>(
          valueListenable: h.cmd,
          builder: (_, String c, __) => Semantics(
              identifier: 's17cmd',
              label: c,
              excludeSemantics: true, // 标签只含命令本身
              child: Text(c)),
        ),
        ValueListenableBuilder<String>(
          valueListenable: h.log,
          builder: (_, String s, __) =>
              Semantics(
                  identifier: 's17log',
                  label: s,
                  excludeSemantics: true,
                  child: Text(s)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
  // 诊断开关切换时回调变为 null，原生应停止回执与 tapId（T-TIME-3）
  Widget _map() => ValueListenableBuilder<bool>(
        valueListenable: h.diagnostics,
        builder: (_, bool diag, __) => ValueListenableBuilder<Set<Marker>>(
          valueListenable: h.markers,
          builder: (_, Set<Marker> m, __) => AMapWidget(
            key: h.mapKey,
            initialCameraPosition:
                const CameraPosition(target: _center, zoom: 15),
            markers: m,
            markerSelection: const MarkerSelectionOptions(),
            onMapCreated: (AMapController c) => h.controller = c,
            onMarkerUpdateApplied: diag ? h.updates.add : null,
            onMarkerTapApplied: diag ? h.taps.add : null,
          ),
        ),
      );
}
