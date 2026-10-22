import 'dart:typed_data';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('T-BYTES-1 构造后修改原数组，id 与序列化字节不变', () {
    final Uint8List src = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final MarkerImageResource r = MarkerImageResource.bytes(src);
    final String id = r.id;
    src[0] = 99;
    expect(r.id, id);
    expect(r.toMap()['data'], <int>[1, 2, 3, 4]);
    // 与用原始内容新建的资源 id 相同
    expect(MarkerImageResource.bytes(Uint8List.fromList(<int>[1, 2, 3, 4])).id,
        id);
  });

  test('T-BYTES-2 相同字节同像素比 id 相等，像素比不同 id 不同', () {
    final Uint8List a = Uint8List.fromList(<int>[1, 2, 3]);
    final MarkerImageResource r1 = MarkerImageResource.bytes(a, pixelRatio: 3);
    final MarkerImageResource r2 = MarkerImageResource.bytes(
        Uint8List.fromList(<int>[1, 2, 3]),
        pixelRatio: 3);
    final MarkerImageResource r3 = MarkerImageResource.bytes(a, pixelRatio: 2);
    final MarkerImageResource r4 = MarkerImageResource.bytes(
        Uint8List.fromList(<int>[1, 2, 4]),
        pixelRatio: 3);
    expect(r1.id, r2.id);
    expect(r1, r2);
    expect(r1.id, isNot(r3.id));
    expect(r1.id, isNot(r4.id));
    // id 格式：b: + 32 位十六进制 + @ + pixelRatio
    expect(r1.id, matches(RegExp(r'^b:[0-9a-f]{32}@3\.0$')));
  });

  testWidgets('T-BYTES-3 连续 build 50 次，摘要只在构造时计算', (WidgetTester tester) async {
    final int before = MarkerImageResource.debugDigestComputeCount;
    final MarkerImageResource r =
        MarkerImageResource.bytes(Uint8List.fromList(<int>[7, 8, 9]));
    expect(MarkerImageResource.debugDigestComputeCount, before + 1);

    final ValueNotifier<int> tick = ValueNotifier<int>(0);
    int builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (BuildContext context, int v, Widget? child) {
        builds++;
        // build 中只读取缓存的资源对象，不重新创建
        return Directionality(
            textDirection: TextDirection.ltr, child: Text(r.id));
      },
    ));
    for (int i = 0; i < 50; i++) {
      tick.value++;
      await tester.pump();
    }
    expect(builds, 51);
    expect(MarkerImageResource.debugDigestComputeCount, before + 1);
  });

  test('asset 资源序列化与 == ', () {
    const MarkerImageResource a = MarkerImageResource.asset(
        id: 'spot', assetName: 'assets/spot.png', pixelRatio: 2);
    expect(a.toMap(), <String, dynamic>{
      'id': 'spot',
      'type': 'asset',
      'asset': 'assets/spot.png',
      'package': null,
      'pixelRatio': 2.0,
    });
    expect(
        a,
        const MarkerImageResource.asset(
            id: 'spot', assetName: 'other.png', pixelRatio: 1));
  });
}
