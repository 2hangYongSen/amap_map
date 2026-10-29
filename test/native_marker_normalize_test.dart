import 'dart:convert';
import 'dart:io';

import 'package:amap_map/src/native_marker/normalize.dart';
import 'package:flutter_test/flutter_test.dart';

// T-NORM-1（Dart 端）：舍入结果与共享夹具一致。
void main() {
  final Map<String, dynamic> fixture = jsonDecode(
          File('test/fixtures/native_marker_layout.json').readAsStringSync())
      as Map<String, dynamic>;
  final Map<String, dynamic> norm =
      fixture['normalization'] as Map<String, dynamic>;

  int unitsOf(String kind, double v) => kind == 'length'
      ? normalizeLengthUnits(v)
      : normalizeRatioUnits(v);

  test('夹具的缩放系数与实现一致', () {
    expect(norm['lengthScale'], kLengthScale);
    expect(norm['ratioScale'], kRatioScale);
  });

  group('T-NORM-1 夹具逐条核对', () {
    final List<dynamic> cases = norm['cases'] as List<dynamic>;
    for (final dynamic c in cases) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test(m['name'] as String, () {
        final double input = (m['input'] as num).toDouble();
        expect(unitsOf(m['kind'] as String, input), m['units']);
      });
    }
  });

  group('T-NORM-1 同组输入舍入后相同', () {
    final List<dynamic> groups = norm['sameGroups'] as List<dynamic>;
    for (final dynamic g in groups) {
      final Map<String, dynamic> m = g as Map<String, dynamic>;
      test(m['name'] as String, () {
        final List<int> units = (m['inputs'] as List<dynamic>)
            .map((dynamic e) => unitsOf(m['kind'] as String, (e as num).toDouble()))
            .toList();
        expect(units.toSet().length, 1, reason: '$units');
      });
    }
  });

  test('规范化后的值等于 units / scale', () {
    expect(normalizeLength(0.3), 19 / 64);
    expect(normalizeRatio(0.5000001), 0.5);
  });

  test('负零规范化为 0', () {
    expect(normalizeLengthUnits(-0.0), 0);
    expect(normalizeLength(-0.0).isNegative, isFalse);
  });

  test('非有限值直接报错，不返回垃圾数据', () {
    for (final double v in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      double.maxFinite, // 乘以缩放系数后溢出
    ]) {
      expect(() => normalizeLengthUnits(v), throwsArgumentError,
          reason: '$v');
      expect(() => normalizeRatioUnits(v), throwsArgumentError,
          reason: '$v');
    }
  });
}
