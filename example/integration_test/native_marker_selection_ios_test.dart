// S16：iOS 真机打开选择示例页，用 API 选中 p2 再取消，截图供驱动判定画面变化与恢复。
// 点位点击路径由原生实验 T4（T-TOP-4）覆盖；这里核对整条 Dart → 原生 → 高层 Annotation 链路。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/native_marker_selection_ios_test.dart -d <设备 id>
import 'package:amap_map_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 原生绑定是异步的：按真实时间等待，期间持续刷帧
  Future<void> settle(WidgetTester tester, int ms) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  // 真实点击（经 AMapViewController）由 XCUITest S14UITests/testSelectionPage 覆盖
  testWidgets('原生点位选择页：API 选中与取消', (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    await settle(tester, 500);
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pushNamed('/native-marker-selection');
    await settle(tester, 6000);
    await binding.takeScreenshot('s16_sel_0_normal');

    await tester.tap(find.text('选中 p2'));
    await settle(tester, 2000);
    // 事件与 revision 回写到页面日志（R-SEL-1）
    expect(find.textContaining('setSelectedMarker(p2) → revision 1'), findsOneWidget);
    await binding.takeScreenshot('s16_sel_1_p2');

    // 再选同一个：revision 不变（R-SEL-4）
    await tester.tap(find.text('选中 p2'));
    await settle(tester, 1000);
    expect(find.textContaining('setSelectedMarker(p2) → revision 1'), findsOneWidget);

    await tester.tap(find.text('取消选择'));
    await settle(tester, 2000);
    expect(find.textContaining('setSelectedMarker(null) → revision 2'), findsOneWidget);
    await binding.takeScreenshot('s16_sel_2_cleared');
  });
}
