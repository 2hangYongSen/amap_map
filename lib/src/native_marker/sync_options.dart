import 'package:flutter/foundation.dart' show immutable;

import '../types/marker_selection.dart';

/// 走发送队列的点位相关地图选项。
///
/// 这些选项依赖新协议，必须在握手成功后才发送（R-INIT-7），
/// 不经原有的 `_updateOptions` 路径抢先发出。
@immutable
class MarkerSyncOptions {
  const MarkerSyncOptions({
    this.selection,
    this.transition = const MarkerTransition.immediate(),
  });

  /// 原生单选配置，为空表示关闭
  final MarkerSelectionOptions? selection;

  /// 集合替换过渡策略
  final MarkerTransition transition;

  /// 非默认值即需要新协议（R-PROTO-0）
  bool get needsProtocolV2 =>
      selection != null || transition.replaceWhenReadyEnabled;

  /// `map#update.options` 与创建参数中的键
  Map<String, dynamic> toMap() {
    final MarkerSelectionOptions? s = selection;
    return <String, dynamic>{
      'markerSelection': s == null
          ? null
          : <String, dynamic>{
              'deselectOnMapTap': s.deselectOnMapTap,
              'deselectOnRetap': s.deselectOnRetap,
            },
      'markerTransition': <String, dynamic>{
        'mode': transition.replaceWhenReadyEnabled
            ? 'replaceWhenReady'
            : 'immediate',
        'timeoutMs': transition.timeout?.inMilliseconds,
      },
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerSyncOptions &&
          selection == other.selection &&
          transition == other.transition;

  @override
  int get hashCode => Object.hash(selection, transition);
}

/// 队列向上层（`_MapState`）交付的事件，全部可选。
class MarkerSyncCallbacks {
  const MarkerSyncCallbacks({this.onNativeError, this.onSelectionChanged});

  /// `marker#nativeError`，已按 eventSeq 去重（R-INIT-5）
  final void Function(NativeMarkerError error)? onNativeError;

  /// `marker#selectionChanged`，已过滤过期 revision
  final void Function(MarkerSelectionChange change)? onSelectionChanged;
}
