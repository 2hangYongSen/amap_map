/// R-NORM-2：长度类数值按 1/64 逻辑像素量化。
const int kLengthScale = 64;

/// R-NORM-2：锚点比例和像素比按 1/1024 量化。
const int kRatioScale = 1024;

// 超过 2^53 的整数在 Java/ObjC 的 double 转换里会丢精度，直接拒绝
const double _maxExactUnits = 9007199254740992;

int _toUnits(double v, int scale) {
  final double scaled = v * scale;
  // 乘法可能溢出为无穷，所以对乘积再检查一次
  if (!v.isFinite || !scaled.isFinite || scaled.abs() > _maxExactUnits) {
    throw ArgumentError.value(v, 'value', '无法规范化：必须是有限且不过大的数值');
  }
  // Dart 的 round() 对一半的情况远离零取整，与 R-NORM-2 一致
  return scaled.round();
}

/// 长度类数值规范化为整数单位（1/64 逻辑像素）。
int normalizeLengthUnits(double v) => _toUnits(v, kLengthScale);

/// 锚点比例或像素比规范化为整数单位（1/1024）。
int normalizeRatioUnits(double v) => _toUnits(v, kRatioScale);

/// 规范化后的长度值。
double normalizeLength(double v) => normalizeLengthUnits(v) / kLengthScale;

/// 规范化后的锚点比例或像素比。
double normalizeRatio(double v) => normalizeRatioUnits(v) / kRatioScale;
