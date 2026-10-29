import '../types/marker_diagnostics.dart';
import '../types/marker_selection.dart';

/// Dart 端诊断关联（§13）：按 syncId 补上 t1 与返回时刻，按 markerId 把 tapId 带回下一次更新。
///
/// 只在诊断开启时有数据；关闭时各方法都不产生任何通道调用（T-TIME-3）。
class MarkerDiagnosticsTracker {
  /// 最多保留的在途记录，超出丢弃最早的（回执丢失时不无限增长）
  static const int maxEntries = 64;

  final Map<int, _SyncTimes> _syncs = <int, _SyncTimes>{};
  final Map<String, int> _tapByMarker = <String, int>{};

  /// 发出请求前记录 t1
  void sent(int syncId) {
    _syncs[syncId] = _SyncTimes(MarkerDiagnosticsClock.nowMs());
    _trim(_syncs);
  }

  /// 收到返回；若回执已先到，返回补全后的回执
  MarkerUpdateReport? returned(int syncId) {
    final _SyncTimes? s = _syncs[syncId];
    if (s == null) {
      return null;
    }
    s.returnMs = MarkerDiagnosticsClock.nowMs();
    final Map<Object?, Object?>? held = s.heldReport;
    if (held == null) {
      return null; // 回执还没到，到了再交付
    }
    _syncs.remove(syncId);
    return _build(held, s);
  }

  /// 收到 `markers#applied`；返回尚未到达时暂存，返回后再交付（Android 同步应用时回执先于返回）
  MarkerUpdateReport? applied(Map<Object?, Object?> raw) {
    final Object? id = raw['syncId'];
    if (id is! num) {
      return null;
    }
    final _SyncTimes? s = _syncs[id.toInt()];
    if (s == null) {
      return _build(raw, null); // 未记录发送时刻（如创建参数）：只带原生字段
    }
    if (s.returnMs == null) {
      s.heldReport = raw;
      return null;
    }
    _syncs.remove(id.toInt());
    return _build(raw, s);
  }

  /// `marker#onTap` 带来的 tapId（旧路径：等该点的下一次更新带回原生）
  void tapped(String markerId, int tapId) {
    _tapByMarker[markerId] = tapId;
    _trim(_tapByMarker);
  }

  /// 本次请求新增或修改了某个刚被点击的点时，取出 `diagTapId`（R-TIME-7）
  Map<String, Object?>? takeTapFor(Iterable<String> changedIds) {
    for (final String id in changedIds) {
      final int? tapId = _tapByMarker.remove(id);
      if (tapId != null) {
        return <String, Object?>{'tapId': tapId, 'markerId': id};
      }
    }
    return null;
  }

  void clear() {
    _syncs.clear();
    _tapByMarker.clear();
  }

  static void _trim<K, V>(Map<K, V> m) {
    while (m.length > maxEntries) {
      m.remove(m.keys.first);
    }
  }

  static MarkerUpdateReport? _build(Map<Object?, Object?> raw, _SyncTimes? s) =>
      markerUpdateReportFromMap(raw,
          dartT1Ms: s?.t1Ms, dartReturnMs: s?.returnMs);
}

class _SyncTimes {
  _SyncTimes(this.t1Ms);

  final double t1Ms;
  double? returnMs;
  Map<Object?, Object?>? heldReport;
}

double _d(Object? v) => v is num ? v.toDouble() : 0;
int _i(Object? v) => v is num ? v.toInt() : 0;

/// 解析 `markers#applied`（R-TIME-4）；缺少 syncId 时返回 null
MarkerUpdateReport? markerUpdateReportFromMap(Map<Object?, Object?> raw,
    {double? dartT1Ms, double? dartReturnMs}) {
  if (raw['syncId'] is! num) {
    return null;
  }
  final Object? m = raw['memory'];
  final Map<Object?, Object?> mem = m is Map ? m : const <Object?, Object?>{};
  final Object? t2v = raw['nativeT2vMs'];
  final Object? color = raw['markerColor'];
  return MarkerUpdateReport(
    syncId: _i(raw['syncId']),
    nativeT2Ms: _d(raw['nativeT2Ms']),
    nativeT4Ms: _d(raw['nativeT4Ms']),
    t2ToT3Ms: _d(raw['t2ToT3Ms']),
    t2ToT4Ms: _d(raw['t2ToT4Ms']),
    appliedCount: _i(raw['appliedCount']),
    drawCount: _i(raw['drawCount']),
    cacheHits: _i(raw['cacheHits']),
    cacheMisses: _i(raw['cacheMisses']),
    bytesReceived: _i(raw['bytesReceived']),
    memory: MarkerMemoryReport(
      compositeBytes: _i(mem['compositeBytes']),
      decodedBytes: _i(mem['decodedBytes']),
      compositeOverBudget: mem['compositeOverBudget'] == true,
      decodedOverBudget: mem['decodedOverBudget'] == true,
    ),
    nativeT2vMs: t2v is num ? t2v.toDouble() : null,
    markerColor: color is num ? color.toInt() : null,
    pendingTasks: _i(raw['pendingTasks']),
    dartT1Ms: dartT1Ms,
    dartReturnMs: dartReturnMs,
  );
}

/// 解析 `markers#tapApplied`（R-TIME-7）；字段不全时返回 null
MarkerTapReport? markerTapReportFromMap(Map<Object?, Object?> raw) {
  final Object? id = raw['tapId'];
  final Object? markerId = raw['markerId'];
  if (id is! num || markerId is! String) {
    return null;
  }
  return MarkerTapReport(
    tapId: id.toInt(),
    markerId: markerId,
    c1Ms: _d(raw['c1Ms']),
    c2Ms: _d(raw['c2Ms']),
    path: raw['path'] == 'native' ? MarkerTapPath.native : MarkerTapPath.icon,
    drawCount: _i(raw['drawCount']),
  );
}
