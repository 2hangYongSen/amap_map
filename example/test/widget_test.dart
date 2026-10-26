import 'package:amap_map_example/data/demos.dart';
import 'package:amap_map/amap_map.dart';
import 'package:amap_map_example/pages/interactive/map_events_page.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:amap_map_example/main.dart';
import 'package:amap_map_example/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every demo has a unique route and test steps', () {
    final List<Demo> demos = allDemos();
    expect(demos.length, 27);
    expect(demos.map((Demo demo) => demo.slug).toSet().length, demos.length);
    expect(demos.map((Demo demo) => demo.title.split(':').first).toSet().length,
        demos.length);
    for (final Demo demo in demos) {
      expect(demo.steps, isNotEmpty);
      expect(demo.configurations, hasLength(1));
      expect(RouteConfig.onGenerateRoute(RouteSettings(name: '/${demo.slug}')),
          isNotNull);
    }
    expect(RouteConfig.onGenerateRoute(const RouteSettings()), isNull);
  });

  testWidgets('grouped catalog opens a demo and shows its test instructions',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    expect(find.text('高德地图测试示例'), findsOneWidget);
    expect(find.text('基础功能'), findsOneWidget);
    expect(find.text('AM-D01: 基本地图显示'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);

    await tester.tap(find.text('AM-D01: 基本地图显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('测试步骤'));
    await tester.pumpAndSettle();
    expect(find.text(allDemos().first.steps), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('高德地图测试示例'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('event logging updates its panel without rebuilding the map',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MapEventsPage()),
    ));
    final AMapWidget before = tester.widget<AMapWidget>(find.byType(AMapWidget));
    before.onTap!(const LatLng(30, 120));
    await tester.pump();
    expect(find.textContaining('点击：'), findsOneWidget);
    expect(identical(before, tester.widget<AMapWidget>(find.byType(AMapWidget))), isTrue);
    await tester.tap(find.byTooltip('清空日志'));
    await tester.pump();
    expect(find.text('操作地图查看事件'), findsOneWidget);
    expect(identical(before, tester.widget<AMapWidget>(find.byType(AMapWidget))), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown demo route shows a recoverable page',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AMapDemoApp());
    Navigator.of(tester.element(find.byType(ListView)))
        .pushNamed('/missing-demo');
    await tester.pumpAndSettle();
    expect(find.text('未找到测试'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('高德地图测试示例'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
