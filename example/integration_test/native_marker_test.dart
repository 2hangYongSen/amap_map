// S18 集成测试（无需主机点击）：T-RES-13、T-DISP-2、旧路径回归。
// 运行：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/native_marker_test.dart -d <设备 id>
// Android 内存由 example/tool/s18_android_run.sh 读 S18CMD meminfo 采集；iOS 只记录 RSS。
import 'dart:io';
import 'dart:typed_data';

import 'package:amap_map_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 's18_support.dart';

const String _pinAsset = 'assets/native_marker/pin.png';
const String _missing = 'assets/native_marker/__s18_missing.png';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final S18Out out = S18Out('native_marker_test.txt');

  testWidgets('S18 集成：T-RES-13、旧路径回归、T-DISP-2', (WidgetTester tester) async {
    S18Channel.install();
    try {
      await tester.pumpWidget(const AMapDemoApp());
      await settle(tester, 1000);
      await _tRes13(tester, out);
      await _legacyRegression(tester, out);
      await _tDisp2(tester, out);
      out.line('S18 PASS');
    } catch (e) {
      out.line('S18 FAIL: $e');
      rethrow;
    } finally {
      S18Channel.uninstall();
      out.command('done');
    }
  });
}

NavigatorState _nav(WidgetTester tester) =>
    tester.state(find.byType(Navigator));

/// 地图截图用 map#takeSnapshot（双端均可截到原生点位，E-X1）。
/// 地图已加载：在 1/10～9/10 高度取 9 行，颜色种类最多的一行 ≥ 20（空白底色只有个位数；
/// 单取一行可能落在平整街区上，只有十几种）
bool _loaded(Rgba img) {
  int best = 0;
  for (int k = 1; k <= 9; k++) {
    final Set<int> colors = <int>{};
    final int y = img.height * k ~/ 10;
    for (int x = 0; x < img.width; x++) {
      colors.add(img.at(x, y) >> 4 & 0x0F0F0F);
    }
    if (colors.length > best) best = colors.length;
  }
  return best >= 20;
}

Future<Rgba> _snapLoaded(WidgetTester tester, S18Out out) async {
  Uint8List? png;
  for (int i = 0; i < 15; i++) {
    png = await S18Channel.invoke<Uint8List>('map#takeSnapshot');
    if (png != null) {
      final Rgba img = await Rgba.decode(png);
      if (_loaded(img)) return img;
    }
    await settle(tester, 2000);
  }
  if (png != null) out.image('not_loaded_${S18Channel.lastMapId}', png);
  throw StateError('地图未加载（mapId ${S18Channel.lastMapId}，'
      '截图 ${png?.length ?? 0} 字节），截图比较无效');
}

/// 把载荷中图钉资源的 asset 名换成不存在的文件；返回新载荷，未命中返回 null
Object? _breakPin(Object? v, void Function() hit) {
  if (v is Map) {
    if (v['id'] == 'nm.pin' && v['asset'] == _pinAsset) {
      hit();
      return Map<Object?, Object?>.of(v)..['asset'] = _missing;
    }
    bool changed = false;
    final Map<Object?, Object?> m = <Object?, Object?>{};
    v.forEach((Object? k, Object? x) {
      final Object? y = _breakPin(x, hit);
      changed |= y != null;
      m[k] = y ?? x;
    });
    return changed ? m : null;
  }
  if (v is List) {
    bool changed = false;
    final List<Object?> l = <Object?>[
      for (final Object? x in v) _breakPin(x, hit) ?? x
    ];
    for (int i = 0; i < v.length; i++) {
      changed |= !identical(l[i], v[i]);
    }
    return changed ? l : null;
  }
  return null;
}

/// 图钉（逻辑 40×50，锚点在底边中点）在截图中的区域；图钉主体颜色约 0xFF1888E0
const int _pinBlue = 0xFF1888E0;

Future<Rect> _pinRect(WidgetTester tester) async {
  final Map<Object?, Object?>? p =
      await S18Channel.invoke<Map<Object?, Object?>>('map#toScreenCoordinate',
          <double>[s18Center.latitude - 0.004, s18Center.longitude]);
  final double dpr = tester.view.devicePixelRatio;
  // Android 返回物理像素；iOS 返回点，截图为 @scale 像素
  final double k = Platform.isAndroid ? 1 : dpr;
  final Offset a = Offset((p!['x']! as num) * k, (p['y']! as num) * k);
  return Rect.fromLTRB(a.dx - 20 * dpr, a.dy - 50 * dpr, a.dx + 20 * dpr, a.dy);
}

Future<int> _pinBluePixels(WidgetTester tester, S18Out out, String name) async {
  final Uint8List png =
      (await S18Channel.invoke<Uint8List>('map#takeSnapshot'))!;
  out.image(name, png);
  return (await Rgba.decode(png)).count(await _pinRect(tester), _pinBlue);
}

/// T-RES-13：图片示例页中图钉 asset 先不可读（通道改写为不存在的文件），
/// 截图先是默认降级背景；放开后由 Dart 按 1s/4s/16s 自动重试恢复，与无故障参考图一致。
Future<void> _tRes13(WidgetTester tester, S18Out out) async {
  // 参考图：无故障
  _nav(tester).pushNamed('/native-marker-image');
  await settle(tester, 2000);
  await _snapLoaded(tester, out);
  await settle(tester, 2000);
  final int ref = await _pinBluePixels(tester, out, 't_res13_ref');
  _nav(tester).pop();
  await settle(tester, 1500);

  // 故障：放开前每次登记图钉都改成不存在的文件
  bool broken = true;
  int hits = 0;
  S18Channel.rewrite = (String method, Object? args) =>
      broken ? _breakPin(args, () => hits++) : null;
  _nav(tester).pushNamed('/native-marker-image');
  await settle(tester, 2000);
  await _snapLoaded(tester, out);
  await settle(tester, 1000);
  final int fallback = await _pinBluePixels(tester, out, 't_res13_fallback');
  final bool errorShown =
      find.textContaining('imageDecodeFailed nm.pin').evaluate().isNotEmpty;
  broken = false; // asset 恢复可读，等下一次自动重试
  int recovered = 0;
  for (int i = 0; i < 25 && recovered < ref * 0.8; i++) {
    await settle(tester, 1000);
    recovered = await _pinBluePixels(tester, out, 't_res13_recovered');
  }
  out.record(<String, Object?>{
    'test': 'T-RES-13',
    'refBlue': ref,
    'fallbackBlue': fallback,
    'recoveredBlue': recovered,
    'brokenSends': hits,
    'errorShown': errorShown,
  });
  S18Channel.rewrite = null;
  expect(hits, greaterThanOrEqualTo(1), reason: '图钉登记未被拦截');
  expect(ref, greaterThan(500), reason: '参考图中没有找到图钉');
  expect(fallback, lessThan(ref * 0.3), reason: '故障期间仍显示了图钉图片');
  expect(errorShown, isTrue, reason: '页面没有收到 imageDecodeFailed');
  expect(recovered, greaterThanOrEqualTo(ref * 0.8), reason: '重试后没有恢复');
  expect(recovered, lessThanOrEqualTo(ref * 1.2));
  _nav(tester).pop();
  await settle(tester, 1500);
}

/// 旧路径回归（§15 回归清单）：旧 Marker（asset / bytes 图标）、折线、多边形、InfoWindow、
/// benchmark 页依次打开，地图加载、无异常，旧载荷不带 protocolVersion。
Future<void> _legacyRegression(WidgetTester tester, S18Out out) async {
  const List<String> pages = <String>[
    'marker-config',
    'marker-icon',
    'polyline',
    'polygon',
    'custom-info-window',
    'marker-benchmark',
  ];
  for (final String slug in pages) {
    S18Channel.calls.clear();
    bool v2 = false;
    S18Channel.rewrite = (String method, Object? args) {
      if (method == 'markers#update' &&
          args is Map &&
          args['protocolVersion'] != null) {
        v2 = true;
      }
      return null;
    };
    _nav(tester).pushNamed('/$slug');
    await settle(tester, 2000);
    await _snapLoaded(tester, out);
    final Object? err = tester.takeException();
    out.record(<String, Object?>{
      'test': 'legacy',
      'page': slug,
      'v2': v2,
      'markerUpdates': S18Channel.calls['markers#update'] ?? 0,
      'attach': S18Channel.calls['markers#attach'] ?? 0,
    });
    expect(err, isNull, reason: '$slug 抛出异常');
    expect(v2, isFalse, reason: '$slug 使用了新协议');
    expect(S18Channel.calls['markers#attach'] ?? 0, 0, reason: '$slug 发起了握手');
    _nav(tester).pop();
    await settle(tester, 1200);
  }
  S18Channel.rewrite = null;
}

/// T-DISP-2：进出图片示例页 30 次，每次在加载中（进入后 0.2～1.4s）退出；
/// 无崩溃，进程 RSS 不持续增长。Android 第 0/10/20/30 轮后由主机采 dumpsys meminfo。
Future<void> _tDisp2(WidgetTester tester, S18Out out) async {
  await settle(tester, 3000);
  final int base = ProcessInfo.currentRss;
  out.command('meminfo', 'disp_0');
  await settle(tester, 3000);
  final List<int> rss = <int>[];
  for (int i = 1; i <= 30; i++) {
    _nav(tester).pushNamed('/native-marker-image');
    await settle(tester, 200 + (i * 397) % 1200); // 不同的加载阶段
    _nav(tester).pop();
    await settle(tester, 600);
    expect(tester.takeException(), isNull, reason: '第 $i 次退出抛出异常');
    if (i % 10 == 0) {
      await settle(tester, 3000);
      rss.add(ProcessInfo.currentRss);
      out.command('meminfo', 'disp_$i');
      await settle(tester, 3000);
    }
  }
  final double growth = (rss.last - base) / base;
  out.record(<String, Object?>{
    'test': 'T-DISP-2',
    'baseRss': base,
    'rss': rss,
    'growth': double.parse(growth.toStringAsFixed(4)),
  });
  // RSS 包含 GC 时机与 SDK 瓦片缓存：只判定“不持续增长”，第 20→30 轮增量不超过基线 10%
  expect((rss[2] - rss[1]) / base, lessThan(0.10), reason: 'RSS 持续增长：$rss');
}
