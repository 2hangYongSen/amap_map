import 'package:flutter/foundation.dart' show immutable;

/// 原生单选配置
@immutable
final class MarkerSelectionOptions {
  const MarkerSelectionOptions({
    this.deselectOnMapTap = true,
    this.deselectOnRetap = true,
  });

  /// 点击地图空白处是否取消选择
  final bool deselectOnMapTap;

  /// 再次点击已选中的点是否取消选择
  final bool deselectOnRetap;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerSelectionOptions &&
          deselectOnMapTap == other.deselectOnMapTap &&
          deselectOnRetap == other.deselectOnRetap;

  @override
  int get hashCode => Object.hash(deselectOnMapTap, deselectOnRetap);

  @override
  String toString() => 'MarkerSelectionOptions{'
      'deselectOnMapTap: $deselectOnMapTap, deselectOnRetap: $deselectOnRetap}';
}

/// 选择变化的原因
enum MarkerSelectionReason { markerTap, retap, mapTap, api, invalidated }

/// 选择变化事件
///
/// 在 `onMarkerSelectionChanged` 中只需把结果写回业务状态，
/// 不要再调用 `setSelectedMarker`；传入相同 id 不会产生任何效果。
@immutable
final class MarkerSelectionChange {
  const MarkerSelectionChange({
    required this.selectedId,
    required this.previousId,
    required this.reason,
    required this.revision,
  });

  final String? selectedId;
  final String? previousId;
  final MarkerSelectionReason reason;
  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerSelectionChange &&
          selectedId == other.selectedId &&
          previousId == other.previousId &&
          reason == other.reason &&
          revision == other.revision;

  @override
  int get hashCode => Object.hash(selectedId, previousId, reason, revision);

  @override
  String toString() => 'MarkerSelectionChange{selectedId: $selectedId, '
      'previousId: $previousId, reason: $reason, revision: $revision}';
}

/// 原生错误码
enum NativeMarkerErrorCode {
  imageDecodeFailed,
  imageMissing,
  renderFailed,
  invalidConfig,
  applyFailed,
}

/// 原生端报告的错误
@immutable
final class NativeMarkerError {
  const NativeMarkerError({
    required this.code,
    required this.message,
    this.markerId,
    this.imageId,
  });

  final NativeMarkerErrorCode code;
  final String? markerId;
  final String? imageId;
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerError &&
          code == other.code &&
          markerId == other.markerId &&
          imageId == other.imageId &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, markerId, imageId, message);

  @override
  String toString() => 'NativeMarkerError{code: $code, markerId: $markerId, '
      'imageId: $imageId, message: $message}';
}

/// 集合替换时的过渡策略
@immutable
final class MarkerTransition {
  /// 立即删除（默认，与 1.0.15 行为一致）
  const MarkerTransition.immediate()
      : replaceWhenReadyEnabled = false,
        timeout = null;

  /// 等所有新增点应用完成再删除旧点，最长等待 [timeout]。
  ///
  /// [timeout] 须大于 0 且不超过 5 秒，由校验器检查。
  const MarkerTransition.replaceWhenReady({required Duration this.timeout})
      : replaceWhenReadyEnabled = true;

  /// 是否为 replaceWhenReady 模式
  final bool replaceWhenReadyEnabled;

  /// replaceWhenReady 的超时，immediate 时为空
  final Duration? timeout;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerTransition &&
          replaceWhenReadyEnabled == other.replaceWhenReadyEnabled &&
          timeout == other.timeout;

  @override
  int get hashCode => Object.hash(replaceWhenReadyEnabled, timeout);

  @override
  String toString() => replaceWhenReadyEnabled
      ? 'MarkerTransition.replaceWhenReady(timeout: $timeout)'
      : 'MarkerTransition.immediate()';
}

/// 诊断回执中的内存信息
@immutable
final class MarkerMemoryReport {
  const MarkerMemoryReport({
    this.compositeBytes = 0,
    this.decodedBytes = 0,
    this.compositeOverBudget = false,
    this.decodedOverBudget = false,
  });

  final int compositeBytes;
  final int decodedBytes;
  final bool compositeOverBudget;
  final bool decodedOverBudget;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerMemoryReport &&
          compositeBytes == other.compositeBytes &&
          decodedBytes == other.decodedBytes &&
          compositeOverBudget == other.compositeOverBudget &&
          decodedOverBudget == other.decodedOverBudget;

  @override
  int get hashCode => Object.hash(
      compositeBytes, decodedBytes, compositeOverBudget, decodedOverBudget);

  @override
  String toString() => 'MarkerMemoryReport{compositeBytes: $compositeBytes, '
      'decodedBytes: $decodedBytes, compositeOverBudget: $compositeOverBudget, '
      'decodedOverBudget: $decodedOverBudget}';
}

/// `markers#applied` 诊断回执，仅诊断模式下由原生发送
@immutable
final class MarkerUpdateReport {
  const MarkerUpdateReport({
    required this.syncId,
    required this.nativeT2Ms,
    required this.nativeT4Ms,
    required this.t2ToT3Ms,
    required this.t2ToT4Ms,
    required this.appliedCount,
    required this.drawCount,
    required this.cacheHits,
    required this.cacheMisses,
    required this.bytesReceived,
    this.memory = const MarkerMemoryReport(),
  });

  final int syncId;
  final double nativeT2Ms;
  final double nativeT4Ms;
  final double t2ToT3Ms;
  final double t2ToT4Ms;
  final int appliedCount;
  final int drawCount;
  final int cacheHits;
  final int cacheMisses;
  final int bytesReceived;
  final MarkerMemoryReport memory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerUpdateReport &&
          syncId == other.syncId &&
          nativeT2Ms == other.nativeT2Ms &&
          nativeT4Ms == other.nativeT4Ms &&
          t2ToT3Ms == other.t2ToT3Ms &&
          t2ToT4Ms == other.t2ToT4Ms &&
          appliedCount == other.appliedCount &&
          drawCount == other.drawCount &&
          cacheHits == other.cacheHits &&
          cacheMisses == other.cacheMisses &&
          bytesReceived == other.bytesReceived &&
          memory == other.memory;

  @override
  int get hashCode => Object.hash(
      syncId,
      nativeT2Ms,
      nativeT4Ms,
      t2ToT3Ms,
      t2ToT4Ms,
      appliedCount,
      drawCount,
      cacheHits,
      cacheMisses,
      bytesReceived,
      memory);

  @override
  String toString() => 'MarkerUpdateReport{syncId: $syncId, '
      't2ToT3Ms: $t2ToT3Ms, t2ToT4Ms: $t2ToT4Ms, appliedCount: $appliedCount, '
      'drawCount: $drawCount, cacheHits: $cacheHits, '
      'cacheMisses: $cacheMisses, bytesReceived: $bytesReceived}';
}
