import 'package:flutter/foundation.dart' show immutable;

/// 诊断计时用的 Dart 会话单调时钟（R-TIME-3）。
///
/// 业务埋点 t0、插件记录 t1、`diag#ping` 的 d0/d1 都用它，单位毫秒，
/// 同一进程内共用一个零点，不能和其他 Stopwatch 的读数混用。
abstract final class MarkerDiagnosticsClock {
  static final Stopwatch _watch = Stopwatch()..start();

  /// 当前读数（毫秒，微秒精度）
  static double nowMs() => _watch.elapsedMicroseconds / 1000.0;
}

/// 点击计时所走的路径（R-TIME-7）
enum MarkerTapPath {
  /// 旧路径：Dart 重发图标，原生在 `markers#update` 中 setIcon 后记录 c2
  icon,

  /// 新路径：原生提交选中外观后记录 c2，不经过 Dart
  native,
}

/// `markers#tapApplied` 诊断事件：同一个原生时钟上的 c1（SDK 点击回调）与
/// c2（外观提交返回），两者直接相减（R-TIME-7）。
@immutable
final class MarkerTapReport {
  const MarkerTapReport({
    required this.tapId,
    required this.markerId,
    required this.c1Ms,
    required this.c2Ms,
    required this.path,
  });

  final int tapId;
  final String markerId;
  final double c1Ms;
  final double c2Ms;
  final MarkerTapPath path;

  /// c1 → c2，原生同一时钟
  double get c1ToC2Ms => c2Ms - c1Ms;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerTapReport &&
          tapId == other.tapId &&
          markerId == other.markerId &&
          c1Ms == other.c1Ms &&
          c2Ms == other.c2Ms &&
          path == other.path;

  @override
  int get hashCode => Object.hash(tapId, markerId, c1Ms, c2Ms, path);

  @override
  String toString() => 'MarkerTapReport{tapId: $tapId, markerId: $markerId, '
      'c1ToC2Ms: $c1ToC2Ms, path: ${path.name}}';
}

/// 一次 `diag#ping`：Dart 发出 d0、收到 d1（[MarkerDiagnosticsClock]），
/// 原生处理时的读数 n（原生单调时钟），统一为毫秒。
@immutable
final class MarkerClockSample {
  const MarkerClockSample(
      {required this.d0Ms, required this.nativeMs, required this.d1Ms});

  final double d0Ms;
  final double nativeMs;
  final double d1Ms;

  /// 往返时间
  double get rttMs => d1Ms - d0Ms;

  @override
  String toString() =>
      'MarkerClockSample{d0Ms: $d0Ms, nativeMs: $nativeMs, d1Ms: $d1Ms}';
}

/// 时钟校准估算（R-TIME-3）：取往返最短的样本，
/// offset = n − (d0+d1)/2，真实偏移落在 [n−d1, n−d0]（前提：偏移稳定、n 采于往返之间）。
///
/// 报告中须标注为“时钟校准估算”；半宽只是这次校准的不确定区间，
/// 不是后续任何显示耗时的误差保证。
@immutable
final class MarkerClockCalibration {
  const MarkerClockCalibration._(this.best);

  /// 从一组样本中取往返最短的一个；样本为空时抛 [ArgumentError]
  factory MarkerClockCalibration.fromSamples(
      Iterable<MarkerClockSample> samples) {
    MarkerClockSample? best;
    for (final MarkerClockSample s in samples) {
      if (best == null || s.rttMs < best.rttMs) {
        best = s;
      }
    }
    if (best == null) {
      throw ArgumentError.value(samples, 'samples', '至少需要一个 ping 样本');
    }
    return MarkerClockCalibration._(best);
  }

  /// 选中的样本
  final MarkerClockSample best;

  /// 原生时钟 − Dart 时钟 的估计值
  double get offsetMs => best.nativeMs - (best.d0Ms + best.d1Ms) / 2;

  /// 真实偏移下界 n − d1
  double get lowerMs => best.nativeMs - best.d1Ms;

  /// 真实偏移上界 n − d0
  double get upperMs => best.nativeMs - best.d0Ms;

  /// 区间半宽（= 最短往返的一半）
  double get halfWidthMs => best.rttMs / 2;

  /// 原生读数换算到 Dart 时钟（估算）
  double toDartMs(double nativeMs) => nativeMs - offsetMs;

  /// 数据到达（Dart t0）→ 原生应用完成（t4）的估算：t4 − offset − t0
  double arrivalToAppliedMs(
          {required double dartT0Ms, required double nativeT4Ms}) =>
      nativeT4Ms - offsetMs - dartT0Ms;

  @override
  String toString() => 'MarkerClockCalibration{offsetMs: $offsetMs, '
      'range: [$lowerMs, $upperMs]}';
}
