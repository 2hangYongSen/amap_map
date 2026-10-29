// S17：真机冒烟。开启诊断后发 100 个原生点，检查 markers#applied 回执、diag#ping 校准与标记方块。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/native_marker_diagnostics_test.dart -d <设备 id>
import 'dart:io';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map_example/const_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

const LatLng _center = LatLng(39.909187, 116.397451);

Marker _price(int i, String text) => Marker(
      markerId: 'p$i',
      position: LatLng(_center.latitude + (i ~/ 10 - 4.5) * 0.002,
          _center.longitude + (i % 10 - 4.5) * 0.002),
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: const NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF), cornerRadius: 6),
          fontSize: 13,
          textColor: Color(0xFFE53935),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          arrow: NativeMarkerArrow(width: 10, height: 6),
        ),
      ),
    );

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, int ms) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('诊断回执、时钟校准与标记方块', (WidgetTester tester) async {
    final List<MarkerUpdateReport> reports = <MarkerUpdateReport>[];
    AMapController? controller;
    final ValueNotifier<Set<Marker>> markers =
        ValueNotifier<Set<Marker>>(<Marker>{});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<Set<Marker>>(
          valueListenable: markers,
          builder: (BuildContext context, Set<Marker> m, __) {
            AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
            AMapInitializer.updatePrivacyAgree(
                ConstConfig.amapPrivacyStatement);
            return AMapWidget(
              initialCameraPosition:
                  const CameraPosition(target: _center, zoom: 14),
              markers: m,
              onMapCreated: (AMapController c) => controller = c,
              onMarkerUpdateApplied: reports.add,
            );
          },
        ),
      ),
    ));
    await settle(tester, 5000);
    expect(controller, isNotNull);

    final MarkerClockCalibration pre = await controller!.calibrateNativeClock();
    await controller!.clearNativeMarkerCaches(); // 冷测试
    final double t0 = MarkerDiagnosticsClock.nowMs();
    markers.value = <Marker>{
      for (int i = 0; i < 100; i++) _price(i, '¥${3000 + i * 7}'),
    };
    await settle(tester, 3000);
    final MarkerClockCalibration post =
        await controller!.calibrateNativeClock();

    final MarkerUpdateReport r =
        reports.lastWhere((MarkerUpdateReport x) => x.appliedCount == 100);
    // T-TIME-1：同一原生时钟内的顺序
    expect(r.t2ToT3Ms, greaterThanOrEqualTo(0));
    expect(r.t2ToT4Ms, greaterThanOrEqualTo(0));
    expect(r.nativeT4Ms, greaterThanOrEqualTo(r.nativeT2Ms));
    expect(r.nativeT2vMs, isNotNull, reason: '标记方块已提交');
    expect(r.nativeT2vMs!, greaterThanOrEqualTo(r.nativeT2Ms));
    expect(r.dartT1Ms, isNotNull);
    expect(r.dartT1Ms!, greaterThanOrEqualTo(t0));
    expect(r.dartRoundTripMs, isNotNull);
    expect(pre.halfWidthMs, lessThan(50));
    final double est =
        pre.arrivalToAppliedMs(dartT0Ms: t0, nativeT4Ms: r.nativeT4Ms);
    expect(est, greaterThanOrEqualTo(-pre.halfWidthMs));
    // ignore: avoid_print
    print(
        'S17 diag: syncId=${r.syncId} t2→t3=${r.t2ToT3Ms.toStringAsFixed(2)}ms '
        't2→t4=${r.t2ToT4Ms.toStringAsFixed(2)}ms draw=${r.drawCount} '
        'hits=${r.cacheHits} pending=${r.pendingTasks} '
        'rtt=${r.dartRoundTripMs!.toStringAsFixed(2)}ms '
        'bytes=${r.bytesReceived} color=0x${r.markerColor?.toRadixString(16)} '
        'offset=${pre.offsetMs.toStringAsFixed(3)}±${pre.halfWidthMs.toStringAsFixed(3)} '
        '→${post.offsetMs.toStringAsFixed(3)}±${post.halfWidthMs.toStringAsFixed(3)} '
        't0→t4(估算)=${est.toStringAsFixed(1)}ms');
    if (Platform.isAndroid) {
      // 安卓：Flutter 截图拍不到原生地图与标记方块，停留几秒由主机 adb screencap 截屏
      await settle(tester, 6000);
    } else {
      await binding.takeScreenshot('s17_diag_square');
    }
  });
}
