// T-FIX-3：真机上连续切换 fromBytes 图标，每次截图供人工比对。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/marker_bytes_icon_test.dart -d <设备 id>
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  // 地图区域一行像素的颜色种类数：瓦片加载后约 30～60，未加载（空白底色）只有个位数
  Future<int> mapRowColors() async {
    final List<int> png = await binding.takeScreenshot('map_probe');
    final ui.Codec codec =
        await ui.instantiateImageCodec(Uint8List.fromList(png));
    final ui.Image image = (await codec.getNextFrame()).image;
    final ByteData rgba =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final int y = image.height ~/ 4; // 屏幕上 1/4 处，位于地图内、避开标记
    final Set<int> colors = <int>{};
    for (int x = 0; x < image.width; x++) {
      final int i = (y * image.width + x) * 4;
      colors.add((rgba.getUint8(i) >> 4) << 8 |
          (rgba.getUint8(i + 1) >> 4) << 4 |
          rgba.getUint8(i + 2) >> 4);
    }
    image.dispose();
    return colors.length;
  }

  // 最多等 30s；地图没加载出来就直接失败，避免拿空白截图做比较
  Future<void> waitMapLoaded(WidgetTester tester) async {
    int count = 0;
    for (int i = 0; i < 15; i++) {
      count = await mapRowColors();
      if (count >= 15) return;
      await settle(tester, 2000);
    }
    fail('地图未加载：地图区域只有 $count 种颜色（需 ≥15），本次截图比较无效');
  }

  testWidgets('bytes 图标连续切换', (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    await settle(tester, 500);

    // 首页 build 时完成 key 和隐私初始化，再进入“自定义图标”页
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pushNamed('/marker-icon');
    await settle(tester, 2000);
    await waitMapLoaded(tester);
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
