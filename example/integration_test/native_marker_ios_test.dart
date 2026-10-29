// S15：iOS 上打开形状、图片示例页并截图，供人工与 Android 截图比对；
// 图片页再点“修复资源”，确认降级背景恢复为九宫格气泡（T-RES-12 的界面侧）。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/native_marker_ios_test.dart -d <设备 id>
import 'package:amap_map_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 原生绑定与解码都是异步的：按真实时间等待，期间持续刷帧
  Future<void> settle(WidgetTester tester, int ms) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('原生点位示例页截图', (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    await settle(tester, 500);
    final NavigatorState nav = tester.state(find.byType(Navigator));

    nav.pushNamed('/native-marker-shape');
    await settle(tester, 6000);
    await binding.takeScreenshot('s15_shape');
    nav.pop();
    await settle(tester, 1000);

    nav.pushNamed('/native-marker-image');
    await settle(tester, 6000);
    await binding.takeScreenshot('s15_image_broken');
    await tester.tap(find.text('修复资源'));
    await settle(tester, 3000);
    await binding.takeScreenshot('s15_image_repaired');
  });
}
