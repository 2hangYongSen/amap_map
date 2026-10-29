part of 'sync_queue.dart';

/// 握手快照、原生事件去重、过渡条目跟踪与销毁（R-INIT-3～5、R-DEL-3、R-DART-DISP）。
extension _MarkerSyncEvents on MarkerSyncQueue {
  /// 先安装握手快照，再按序处理暂存事件（R-INIT-4）
  void _installSnapshot(Map<Object?, Object?>? result) {
    final Object? images = result?['images'];
    if (images is Map) {
      _applyImageResult(images);
    }
    final Object? selection = result?['selection'];
    if (selection is Map && selection['revision'] is num) {
      _selectionRevision = (selection['revision'] as num).toInt();
    }
    final Object? errors = result?['errors'];
    if (errors is List) {
      for (final Object? e in errors) {
        if (e is Map) {
          _processError(MarkerProtocolMessage('marker#nativeError', e));
        }
      }
    }
    final Object? dropped = result?['errorsDropped'];
    if (dropped is num && dropped > 0) {
      onSyncError?.call(MarkerSyncException('握手前有 $dropped 条原生错误被丢弃'));
    }
    final Object? seq = result?['lastEventSeq'];
    if (seq is num && seq.toInt() > _lastEventSeq) {
      _lastEventSeq = seq.toInt();
    }
    // 快照已包含的状态变化不重放；按序号顺序处理其余事件
    final List<MarkerProtocolMessage> buffered =
        List<MarkerProtocolMessage>.of(_buffer)
          ..sort((MarkerProtocolMessage a, MarkerProtocolMessage b) =>
              (a.eventSeq ?? 0).compareTo(b.eventSeq ?? 0));
    _buffer.clear();
    buffered.forEach(_processMessage);
  }

  void _processMessage(MarkerProtocolMessage m) {
    if (m.method == 'marker#nativeError') {
      _processError(m); // 错误单独按序号去重（R-INIT-5）
      return;
    }
    final int? seq = m.eventSeq;
    if (seq != null) {
      if (seq <= _lastEventSeq) {
        return; // 快照或之前的事件已经包含
      }
      _lastEventSeq = seq;
    }
    switch (m.method) {
      case 'marker#imagesResult':
        _applyImageResult(m.args);
      case 'marker#selectionChanged':
        final MarkerSelectionChange? change = selectionChangeFromMap(m.args);
        // revision 只增不减，过期事件丢弃
        if (change != null && change.revision > _selectionRevision) {
          _selectionRevision = change.revision;
          callbacks.onSelectionChanged?.call(change);
        }
      // 诊断事件只在诊断已确认开启时交付；关闭后迟到的丢弃
      case 'markers#applied':
        if (_diagOn) {
          _deliverReport(_diag.applied(m.args));
        }
      case 'markers#tapApplied':
        final MarkerTapReport? tap = markerTapReportFromMap(m.args);
        if (_diagOn && tap != null) {
          callbacks.onTapApplied?.call(tap);
        }
      case 'marker#onTap':
        // 诊断模式下的 tapId，等该点的下一次更新带回原生（R-TIME-7）
        final Object? id = m.args['markerId'];
        final Object? tapId = m.args['tapId'];
        if (_diagOn && id is String && tapId is num) {
          _diag.tapped(id, tapId.toInt());
        }
      case 'markers#removed':
        final List<Object?> ids =
            m.args['markerIds'] as List<Object?>? ?? <Object?>[];
        final List<Object?> syncIds =
            m.args['removeSyncIds'] as List<Object?>? ?? <Object?>[];
        for (int i = 0; i < ids.length && i < syncIds.length; i++) {
          final Object? id = ids[i];
          final Object? sid = syncIds[i];
          if (id is String && sid is num) {
            _retiring.removed(id, sid.toInt());
          }
        }
    }
  }

  /// 错误事件按序号去重；imageMissing 触发有界 resync（R-RES-9、R-RES-14）
  void _processError(MarkerProtocolMessage m) {
    final int? seq = m.eventSeq;
    if (seq != null && !_seenErrorSeqs.add(seq)) {
      return;
    }
    final NativeMarkerError? error = nativeMarkerErrorFromMap(m.args);
    if (error == null) {
      return;
    }
    callbacks.onNativeError?.call(error);
    if (error.code == NativeMarkerErrorCode.imageMissing && _v2) {
      if (_missingResyncs >= MarkerSyncQueue.maxRecoveryAttempts) {
        onSyncError?.call(MarkerSyncException('imageMissing 恢复已达上限'));
        return;
      }
      _missingResyncs++;
      _needsResync = true;
      _kick();
    }
  }

  /// `{ready: [id], failed: [{id, code, message}], pending: [id]}`
  void _applyImageResult(Map<Object?, Object?> raw) {
    for (final Object? id in raw['ready'] as List<Object?>? ?? <Object?>[]) {
      if (id is String) {
        _imageSync.markReady(id);
      }
    }
    for (final Object? f in raw['failed'] as List<Object?>? ?? <Object?>[]) {
      final Object? id = f is Map ? f['id'] : f;
      if (id is String) {
        _imageSync.markFailed(id, _resolveImage(id));
      }
    }
  }

  MarkerImageResource? _resolveImage(String id) =>
      _targetImages[id] ?? _confirmedImages[id] ?? _inFlightImages[id];

  /// 从集合消失的点移入过渡条目，重新加入的立即删除（R-DEL-3，仅新协议）
  void _trackRetiring(Map<String, Marker> oldTarget) {
    _target.keys.forEach(_retiring.revive);
    if (!_wantV2) {
      return; // 旧协议：已移除的 id 收到点击时丢弃，与 1.0.15 一致
    }
    oldTarget.forEach((String id, Marker m) {
      // 原生可能持有该点：已确认，或在途请求可能刚把它加上
      if (!_target.containsKey(id) && (_confirmed.containsKey(id) || _busy)) {
        _retiring.retire(m);
      }
    });
  }

  /// asset 资源先移除再加入：失败的重新获得重试机会（R-RES-8）
  void _trackReintroduced(Map<String, MarkerImageResource> oldImages) {
    _targetImages.forEach((String id, MarkerImageResource r) {
      if (!oldImages.containsKey(id)) {
        _imageSync.reintroduced(id, r);
      }
    });
  }

  void _disposeQueue() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _transport = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _imageSync.dispose();
    _diag.clear();
    _failCommands(MarkerSyncException('地图已销毁'));
    _buffer.clear();
    _retiring.clear();
    _confirmed.clear();
    _rejected.clear();
    _confirmedImages.clear();
    _inFlightImages = <String, MarkerImageResource>{};
    _target = <String, Marker>{};
    _targetImages = <String, MarkerImageResource>{};
    _initialMarkers = null;
    _initialImages = null;
  }
}
