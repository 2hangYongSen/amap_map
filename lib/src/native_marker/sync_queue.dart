import 'dart:async';

import '../types/base_overlay.dart';
import '../types/marker.dart';
import '../types/marker_diagnostics.dart';
import '../types/marker_image_resource.dart';
import '../types/marker_selection.dart';
import '../types/marker_updates.dart';
import 'diagnostics_tracker.dart';
import 'image_sync.dart';
import 'protocol.dart';
import 'protocol_message.dart';
import 'retiring_markers.dart';
import 'sync_diff.dart';
import 'sync_options.dart';
import 'sync_transport.dart';
import 'validator.dart';

export 'image_sync.dart' show MarkerImageState, MarkerImageStatus;
export 'protocol_message.dart' show MarkerProtocolMessage;
export 'sync_options.dart';
export 'sync_transport.dart';

part 'sync_queue_events.dart';
part 'sync_queue_markers.dart';
part 'sync_queue_ops.dart';

/// 点位发送队列（§6.4）：最多 1 个在途请求 + 1 份合并后的目标快照。
///
/// - 差异基准是逐点推进的 [confirmed]，从不以未确认的请求为基准；
/// - 新协议单向锁存，启用后不回退（R-PROTO-0）；
/// - 销毁是终态：之后任何迟到结果都不推进状态、不回调（R-DART-DISP）。
class MarkerSyncQueue {
  /// 用初始点位、资源与选项创建；校验失败直接抛 [ArgumentError]。
  MarkerSyncQueue({
    required Set<Marker> markers,
    Set<MarkerImageResource> images = const <MarkerImageResource>{},
    MarkerSyncOptions options = const MarkerSyncOptions(),
    this.onSyncError,
    this.callbacks = const MarkerSyncCallbacks(),
    this.retryDelay = const Duration(milliseconds: 500),
  }) : _options = options {
    NativeMarkerValidator.validate(markers: markers, images: images);
    NativeMarkerValidator.validateTransition(options.transition);
    _assignTarget(markers, images);
    _wantV2 = _targetNeedsV2() || options.needsProtocolV2;
    createdAsV2 = _wantV2;
    _initialMarkers = Map<String, Marker>.of(_target);
    _initialImages = Map<String, MarkerImageResource>.of(_targetImages);
    // 旧协议创建时原生没有这些选项，基准为默认值
    _confirmedOptions = createdAsV2 ? options : const MarkerSyncOptions();
    if (createdAsV2) {
      _imageSync.markSent(_targetImages.keys);
    }
  }

  /// 同步错误回调；为空时忽略
  final void Function(MarkerSyncException error)? onSyncError;

  /// 新协议事件的交付出口
  final MarkerSyncCallbacks callbacks;

  /// 恢复请求（attach、resync）的最多尝试次数：首次 + 自动重试一次
  static const int maxRecoveryAttempts = 2;

  /// 握手前暂存事件的上限，超出丢弃最早的
  static const int maxBufferedMessages = 256;

  /// 创建参数是否已采用新协议
  late final bool createdAsV2;

  final Map<String, Marker> _confirmed = <String, Marker>{};
  final Map<String, Marker> _rejected = <String, Marker>{};
  final Map<String, MarkerImageResource> _confirmedImages =
      <String, MarkerImageResource>{};
  Map<String, Marker> _target = <String, Marker>{};
  Map<String, MarkerImageResource> _targetImages =
      <String, MarkerImageResource>{};
  // 在途请求涉及的资源（新增与释放），属于 R-RES-14 的保护集合
  Map<String, MarkerImageResource> _inFlightImages =
      <String, MarkerImageResource>{};
  Set<Marker>? _lastMarkers;
  Set<MarkerImageResource>? _lastImages;
  MarkerSyncOptions _options;
  late MarkerSyncOptions _confirmedOptions;
  MarkerSyncOptions? _failedOptions;
  late final MarkerImageSync _imageSync = MarkerImageSync(onRetryDue: _kick);
  final RetiringMarkers _retiring = RetiringMarkers();

  // 初始快照：作为第一个“在途请求”，确认后清空（R-SYNC-4）
  Map<String, Marker>? _initialMarkers;
  Map<String, MarkerImageResource>? _initialImages;

  // 握手前暂存的事件与去重状态（R-INIT-4/5）
  final List<MarkerProtocolMessage> _buffer = <MarkerProtocolMessage>[];
  final Set<int> _seenErrorSeqs = <int>{};
  int _lastEventSeq = -1;
  int _selectionRevision = -1;

  final List<_SelectCommand> _commands = <_SelectCommand>[];

  // 诊断关联（§13）：原生已开启诊断（选项已确认）才记录，关闭时不产生任何通道调用
  final MarkerDiagnosticsTracker _diag = MarkerDiagnosticsTracker();
  bool get _diagOn => _v2 && _confirmedOptions.diagnostics;

  void _deliverReport(MarkerUpdateReport? r) {
    if (r != null && !_disposed) {
      callbacks.onUpdateApplied?.call(r);
    }
  }

  bool _wantV2 = false;
  bool _v2 = false;
  MarkerSyncTransport? _transport;
  bool _busy = false;
  bool _disposed = false;
  bool _stalled = false;
  bool _needsResync = false;
  int _attachAttempts = 0;
  int _resyncAttempts = 0;
  int _missingResyncs = 0;
  int _syncId = 0;
  Map<String, dynamic>? _creationParams;
  Timer? _retryTimer;

  /// 握手与 resync 失败后的重试间隔
  final Duration retryDelay;

  /// 新协议是否已经握手完成
  bool get isProtocolV2 => _v2;

  /// 是否已销毁
  bool get isDisposed => _disposed;

  /// 原生当前持有的期望状态（只读视图）
  Map<String, Marker> get confirmed => Map<String, Marker>.unmodifiable(_confirmed);

  /// 被原生拒绝的值（只读视图）
  Map<String, Marker> get rejected => Map<String, Marker>.unmodifiable(_rejected);

  /// 已确认登记在原生的资源 id
  Set<String> get confirmedImageIds => _confirmedImages.keys.toSet();

  /// Dart 保留的资源副本（R-RES-14）：目标 ∪ 已登记 ∪ 在途
  Set<String> get retainedImageIds => <String>{
        ..._targetImages.keys,
        ..._confirmedImages.keys,
        ..._inFlightImages.keys,
      };

  /// 资源镜像状态（只读视图，§7.2）
  Map<String, MarkerImageStatus> get imageStatus => _imageSync.status;

  /// 是否有在途请求
  bool get isBusy => _busy;

  /// 是否有等待中的计时器（asset 重试、握手或 resync 重试）
  bool get hasPendingTimers => _imageSync.hasPendingRetry || _retryTimer != null;

  /// 当前目标点位（最近一次通过校验的集合）
  Iterable<Marker> get targetMarkers => _target.values;

  /// 过渡中待删除点的最后一次 Marker，用于点击分发（R-DEL-3）
  Marker? retiringMarker(String id) => _retiring[id];

  /// 过渡条目 id（测试与诊断用）
  Iterable<String> get retiringIds => _retiring.ids;

  /// 创建参数中与点位有关的部分，只计算一次（R-SYNC-4）。
  ///
  /// 旧协议只有 `markersToAdd`，与 1.0.15 一致；新协议额外带
  /// `protocolVersion`、`imagesToAdd`、`markerSelection`、`markerTransition`。
  Map<String, dynamic> get creationParams => _creationParams ??= _buildCreation();

  /// 控制器就绪后调用：旧协议直接确认初始快照，新协议先握手（R-INIT-1）。
  void attachTransport(MarkerSyncTransport transport) {
    if (_disposed || _transport != null) {
      return;
    }
    _transport = transport;
    if (!createdAsV2) {
      // 旧协议：map#waitForMap 成功即确认创建参数（R-SYNC-4）
      _confirmInitial(const <String>{});
    }
    _kick();
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
    final Map<String, Marker> oldTarget = _target;
    final Map<String, MarkerImageResource> oldImages = _targetImages;
    _assignTarget(markers, images);
    // 单向锁存：一旦需要就不再回退
    _wantV2 = _wantV2 || _targetNeedsV2();
    _trackRetiring(oldTarget);
    _trackReintroduced(oldImages);
    _resumeAfterExternalChange();
  }

  /// 更新选择与过渡选项；非默认值触发协议升级（R-PROTO-0、R-INIT-7）。
  void setOptions(MarkerSyncOptions options) {
    if (_disposed || options == _options) {
      return;
    }
    NativeMarkerValidator.validateTransition(options.transition);
    _options = options;
    _failedOptions = null;
    _wantV2 = _wantV2 || options.needsProtocolV2;
    _resumeAfterExternalChange();
  }

  /// 设置原生选中点，返回原生提交后的 revision（§5.5）。
  ///
  /// 首次调用（包括 null）触发协议升级；命令在握手及选项更新之后发送，
  /// 握手最终失败或会话销毁时以 [MarkerSyncException] 结束。
  Future<int> setSelected(String? markerId) {
    if (_disposed) {
      return Future<int>.error(MarkerSyncException('地图已销毁'));
    }
    final _SelectCommand cmd = _SelectCommand(markerId);
    _commands.add(cmd);
    _wantV2 = true;
    _resumeAfterExternalChange();
    return cmd.completer.future;
  }

  /// 处理新协议原生事件；握手完成前先暂存（R-INIT-4）。
  void handleMessage(MarkerProtocolMessage message) {
    if (_disposed) {
      return;
    }
    if (!_v2) {
      _buffer.add(message);
      if (_buffer.length > maxBufferedMessages) {
        _buffer.removeAt(0);
      }
      return;
    }
    _processMessage(message);
  }

  /// 销毁：同步停止一切，迟到结果只做必要清理（R-DART-DISP）。
  void dispose() => _disposeQueue();
}

/// 等待发送的 `setSelectedMarker` 命令
class _SelectCommand {
  _SelectCommand(this.markerId);

  final String? markerId;
  final Completer<int> completer = Completer<int>();
}
