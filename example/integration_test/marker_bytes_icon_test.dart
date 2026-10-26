// T-FIX-3：真机上连续切换 fromBytes 图标，每次截图供人工比对。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/marker_bytes_icon_test.dart -d <设备 id>
import 'package:amap_map_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 地图瓦片和原生换图都是异步的：按真实时间等待，期间持续刷帧（页面切换动画需要多帧）
  Future<void> settle(WidgetTester tester, int ms) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('bytes 图标连续切换', (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    await settle(tester, 500);

    // 首页 build 时完成 key 和隐私初始化，再进入“自定义图标”页
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pushNamed('/marker-icon');
    await settle(tester, 4000);
    await binding.takeScreenshot('t_fix3_0_initial_asset');

    final Finder toggle = find.text('切换 bytes 图标');
    expect(toggle, findsOneWidget);

    // 第 1 次：路径 start → 字节 start（画面不变，修复前也会更新）；
    // 第 2、3 次：字节 → 字节（F-1 场景，画面应在 end / start 间变化）
    const List<String> names = <String>[
      't_fix3_1_bytes_start',
      't_fix3_2_bytes_end',
      't_fix3_3_bytes_start',
    ];
    for (int i = 0; i < names.length; i++) {
      // 打印步骤，方便对着手机观察；每步停 4s，肉眼能看清
      debugPrint('T-FIX-3 第 ${i + 1} 次点击“切换 bytes 图标”，预期：${names[i]}');
      await tester.tap(toggle);
      await settle(tester, 4000);
      await binding.takeScreenshot(names[i]);
    }
  });
}
