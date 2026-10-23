import 'dart:async';

import '../types/base_overlay.dart';
import '../types/marker.dart';
import '../types/marker_image_resource.dart';
import '../types/marker_updates.dart';
import 'protocol.dart';
import 'sync_diff.dart';
import 'validator.dart';

part 'sync_queue_ops.dart';

/// 队列向原生发送请求的出口；控制器实现它，测试用假实现。
abstract class MarkerSyncTransport {
  /// 旧协议 `markers#update`，成功返回即视为接受（R-INIT-8）
  Future<void> updateLegacy(MarkerUpdates updates);

  /// `markers#attach({protocolVersion: 2})`（R-INIT-3）
  Future<Map<Object?, Object?>?> attach();

  /// 新协议 `markers#update`（§6.2、§6.5）
  Future<Map<Object?, Object?>?> update(Map<String, dynamic> payload);

  /// `markers#resync` 全量快照（R-SYNC-7）
  Future<Map<Object?, Object?>?> resync(Map<String, dynamic> payload);
}

/// 同步过程中的错误（请求失败、恢复停止等），交给调用方上报。
class MarkerSyncException implements Exception {
  MarkerSyncException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'MarkerSyncException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 点位发送队列（§6.4）：最多 1 个在途请求 + 1 份合并后的目标快照。
///
/// - 差异基准是逐点推进的 [confirmed]，从不以未确认的请求为基准；
/// - 新协议单向锁存，启用后不回退（R-PROTO-0）。
class MarkerSyncQueue {
  /// 用初始点位与资源创建；校验失败直接抛 [ArgumentError]。
  MarkerSyncQueue({
    required Set<Marker> markers,
    Set<MarkerImageResource> images = const <MarkerImageResource>{},
    this.onSyncError,
  }) {
    NativeMarkerValidator.validate(markers: markers, images: images);
    _assignTarget(markers, images);
    _wantV2 = _targetNeedsV2();
    createdAsV2 = _wantV2;
    _initialMarkers = Map<String, Marker>.of(_target);
    _initialImages = Map<String, MarkerImageResource>.of(_targetImages);
  }

  /// 同步错误回调；为空时忽略
  final void Function(MarkerSyncException error)? onSyncError;

  /// 恢复请求（attach、resync）的最多尝试次数：首次 + 自动重试一次
  static const int maxRecoveryAttempts = 2;

  /// 创建参数是否已采用新协议
  late final bool createdAsV2;

  final Map<String, Marker> _confirmed = <String, Marker>{};
  final Map<String, Marker> _rejected = <String, Marker>{};
  final Map<String, MarkerImageResource> _confirmedImages =
      <String, MarkerImageResource>{};
  Map<String, Marker> _target = <String, Marker>{};
  Map<String, MarkerImageResource> _targetImages =
      <String, MarkerImageResource>{};
  Set<Marker>? _lastMarkers;
  Set<MarkerImageResource>? _lastImages;

  // 初始快照：作为第一个“在途请求”，确认后清空（R-SYNC-4）
  Map<String, Marker>? _initialMarkers;
  Map<String, MarkerImageResource>? _initialImages;

  bool _wantV2 = false;
  bool _v2 = false;
  MarkerSyncTransport? _transport;
  bool _busy = false;
  bool _disposed = false;
  bool _stalled = false;
  bool _needsResync = false;
  int _attachAttempts = 0;
  int _resyncAttempts = 0;
  int _syncId = 0;
  Map<String, dynamic>? _creationParams;

  /// 新协议是否已经握手完成
  bool get isProtocolV2 => _v2;

  /// 原生当前持有的期望状态（只读视图）
  Map<String, Marker> get confirmed => Map<String, Marker>.unmodifiable(_confirmed);

  /// 被原生拒绝的值（只读视图）
  Map<String, Marker> get rejected => Map<String, Marker>.unmodifiable(_rejected);

  /// 已确认登记在原生的资源 id
  Set<String> get confirmedImageIds => _confirmedImages.keys.toSet();

  /// 是否有在途请求
  bool get isBusy => _busy;

  /// 当前目标点位（最近一次通过校验的集合）
  Iterable<Marker> get targetMarkers => _target.values;

  /// 创建参数中与点位有关的部分，只计算一次（R-SYNC-4）。
  ///
  /// 旧协议只有 `markersToAdd`，与 1.0.15 一致；新协议额外带
  /// `protocolVersion` 与 `imagesToAdd`。
  Map<String, dynamic> get creationParams => _creationParams ??= _buildCreation();

  /// 控制器就绪后调用：旧协议直接确认初始快照，新协议先握手。
  void attachTransport(MarkerSyncTransport transport) {
    if (_disposed || _transport != null) {
      return;
    }
    _transport = transport;
    if (!createdAsV2) {
      // 旧协议：map#waitForMap 成功即确认创建参数（R-SYNC-4）
      _confirmInitial(const <String>{});
    }
    unawaited(_pump());
  }

  /// 写入新的目标快照并尝试发送（R-SYNC-1）。
  ///
  /// 校验失败抛 [ArgumentError]，本次更新整体不生效、不发送（T-VAL-2）。
  void setTarget(Set<Marker> markers, Set<MarkerImageResource> images) {
    if (_disposed) {
      return;
    }
    // 同一对集合对象（如相机移动触发的 updateMarkers）无需重复校验
    if (identical(markers, _lastMarkers) && identical(images, _lastImages)) {
      return;
    }
    NativeMarkerValidator.validate(markers: markers, images: images);
    _assignTarget(markers, images);
    // 单向锁存：一旦需要就不再回退
    _wantV2 = _wantV2 || _targetNeedsV2();
    // 外部新更新可以重新触发已停止的自动恢复（R-INIT-7、R-RES-14）
    _stalled = false;
    _attachAttempts = 0;
    _resyncAttempts = 0;
    unawaited(_pump());
  }

  /// 销毁：停止发送，迟到结果不再推进状态。
  void dispose() {
    _disposed = true;
    _transport = null;
    _confirmed.clear();
    _rejected.clear();
    _confirmedImages.clear();
    _target = <String, Marker>{};
    _targetImages = <String, MarkerImageResource>{};
  }

  void _assignTarget(Set<Marker> markers, Set<MarkerImageResource> images) {
    _lastMarkers = markers;
    _lastImages = images;
    _target = <String, Marker>{for (final Marker m in markers) m.id: m};
    _targetImages = <String, MarkerImageResource>{
      for (final MarkerImageResource r in images) r.id: r,
    };
  }

  bool _targetNeedsV2() =>
      _targetImages.isNotEmpty || _target.values.any(markerNeedsProtocolV2);

  Map<String, dynamic> _buildCreation() {
    final Iterable<Marker> markers = _initialMarkers?.values ?? _target.values;
    if (!createdAsV2) {
      return <String, dynamic>{
        'markersToAdd': serializeOverlaySet(markers.toSet()),
      };
    }
    final Iterable<MarkerImageResource> images =
        _initialImages?.values ?? _targetImages.values;
    return <String, dynamic>{
      'protocolVersion': kMarkerProtocolVersion,
      'imagesToAdd': images.map((MarkerImageResource r) => r.toMap()).toList(),
      'markersToAdd': markers.map(markerToV2Map).toList(),
    };
  }
}
