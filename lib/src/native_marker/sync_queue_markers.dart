part of 'sync_queue.dart';

/// 点位与资源请求：旧协议、新协议差异、resync（R-SYNC-1～7、R-RES-3/14）。
extension _MarkerSyncMarkers on MarkerSyncQueue {
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
      ..._confirmedOptions.toMap(),
    };
  }

  /// 用初始快照推进 confirmed；[rejectedIds] 中的点按“新增被拒绝”处理。
  void _confirmInitial(Set<String> rejectedIds) {
    _initialMarkers?.forEach((String id, Marker m) {
      if (rejectedIds.contains(id)) {
        _rejected[id] = m;
      } else {
        _confirmed[id] = m;
      }
    });
    _confirmedImages.addAll(_initialImages ?? <String, MarkerImageResource>{});
    _initialMarkers = null;
    _initialImages = null;
  }

  /// 无差异返回 null（同步判断，避免发送循环空转）
  Future<void>? _sendLegacy(MarkerSyncTransport t) {
    final Map<String, Marker> sent = Map<String, Marker>.of(_target);
    final MarkerUpdates updates =
        MarkerUpdates.from(_confirmed.values.toSet(), sent.values.toSet());
    if ((updates.markersToAdd?.isEmpty ?? true) &&
        (updates.markersToChange?.isEmpty ?? true) &&
        (updates.markerIdsToRemove?.isEmpty ?? true)) {
      return null;
    }
    return _doSendLegacy(t, updates, sent);
  }

  Future<void> _doSendLegacy(MarkerSyncTransport t, MarkerUpdates updates,
      Map<String, Marker> sent) async {
    try {
      await t.updateLegacy(updates);
      if (_disposed) {
        return;
      }
      // 旧协议返回即接受，整体推进
      _confirmed
        ..clear()
        ..addAll(sent);
    } catch (e) {
      if (_disposed) {
        return;
      }
      // 旧协议失败：保留基准并报告，不发新版 resync（R-INIT-8）
      _stall('旧协议 markers#update 失败', e);
    }
  }

  /// 无差异返回 null（R-SYNC-2）
  Future<void>? _sendV2(MarkerSyncTransport t) {
    // 需要重发的资源（asset 重试、释放后重新引用）只保留仍在目标中的
    final Set<String> resend = _imageSync.resendIds
        .where((String id) => _targetImages.containsKey(id))
        .toSet();
    _imageSync.resendIds
        .where((String id) => !resend.contains(id))
        .toList()
        .forEach(_imageSync.dropResend);
    final MarkerSyncDiff diff = computeMarkerDiff(
      confirmed: _confirmed,
      rejected: _rejected,
      confirmedImages: _confirmedImages,
      target: _target,
      targetImages: _targetImages,
      resendImageIds: resend,
    );
    return diff.isEmpty ? null : _doSendV2(t, diff);
  }

  Future<void> _doSendV2(MarkerSyncTransport t, MarkerSyncDiff diff) async {
    final int syncId = ++_syncId;
    final bool immediate =
        !_confirmedOptions.transition.replaceWhenReadyEnabled;
    final Map<String, dynamic> payload = diff.toV2Payload(syncId);
    if (_diagOn) {
      // 旧路径点击计时：把 tapId 带回紧接着的那次更新（R-TIME-7）
      final Map<String, Object?>? tap =
          _diag.takeTapFor(<String>[...diff.changes.keys, ...diff.adds.keys]);
      if (tap != null) {
        payload['diagTapId'] = tap;
      }
      _diag.sent(syncId); // t1
    }
    // 在途期间保留新增与释放的资源副本（R-RES-14）
    _inFlightImages = <String, MarkerImageResource>{
      ...diff.imagesToAdd,
      for (final String id in diff.imagesToRelease)
        if (_confirmedImages[id] != null) id: _confirmedImages[id]!,
    };
    _imageSync.markSent(diff.imagesToAdd.keys);
    _retiring.assignSyncId(diff.removes, syncId);
    try {
      final Map<Object?, Object?>? result = await t.update(payload);
      if (_disposed) {
        return;
      }
      _deliverReport(_diag.returned(syncId));
      if (result?['accepted'] != true) {
        _needsResync = true;
        return;
      }
      _applyAccepted(diff, _readIds(result?['rejectedMarkerIds']));
      // immediate 模式删除在请求内完成，过渡条目随之清除（R-DEL-3）
      if (immediate) {
        _retiring.settle(syncId);
      }
      _resyncAttempts = 0;
    } catch (_) {
      if (_disposed) {
        return;
      }
      // 新协议失败：confirmed 不变，转入 resync（R-SYNC-3）
      _needsResync = true;
    } finally {
      if (!_disposed) {
        _inFlightImages = <String, MarkerImageResource>{};
      }
    }
  }

  /// 逐点推进 confirmed（R-SYNC-3）。
  void _applyAccepted(MarkerSyncDiff diff, Set<String> rejectedIds) {
    diff.removes.forEach(_confirmed.remove);
    diff.adds.forEach((String id, Marker m) {
      if (rejectedIds.contains(id)) {
        _rejected[id] = m; // 新增被拒：原生没有该点
      } else {
        _confirmed[id] = m;
        _rejected.remove(id);
      }
    });
    diff.changes.forEach((String id, Marker m) {
      if (rejectedIds.contains(id)) {
        _rejected[id] = m; // 修改被拒：confirmed 保持旧值
      } else {
        _confirmed[id] = m;
        _rejected.remove(id);
      }
    });
    _confirmedImages.addAll(diff.imagesToAdd);
    for (final String id in diff.imagesToRelease) {
      _confirmedImages.remove(id);
      // 释放在途时重新加入：保留状态为 unsent，下一次请求重新登记（R-RES-14）
      _imageSync.released(id, stillWanted: _targetImages.containsKey(id));
    }
    _retiring.dropUnsent(_confirmed.containsKey);
  }

  Future<void> _resync(MarkerSyncTransport t) async {
    final MarkerResyncSnapshot snapshot;
    try {
      snapshot = buildResyncSnapshot(
        confirmed: _confirmed,
        rejected: _rejected,
        confirmedImages: _confirmedImages,
        target: _target,
        targetImages: _targetImages,
      );
    } on StateError catch (e) {
      // 依赖缺失属于不变量失败：报告并停止，不循环恢复（R-RES-14）
      _stall('resync 快照不完整', e);
      return;
    }
    // 次数只在普通请求成功或外部新更新时清零，避免“失败→恢复→失败”无限循环
    if (_resyncAttempts >= MarkerSyncQueue.maxRecoveryAttempts) {
      _stall('markers#resync 已达上限，停止自动恢复', StateError('limit'));
      return;
    }
    _resyncAttempts++;
    final int syncId = ++_syncId;
    _inFlightImages = Map<String, MarkerImageResource>.of(snapshot.images);
    // resync 重新登记全部资源，失败的资源也获得一次重新解码
    _imageSync.markSent(snapshot.images.keys);
    if (_diagOn) {
      _diag.sent(syncId);
    }
    try {
      final Map<Object?, Object?>? result =
          await t.resync(snapshot.toPayload(syncId));
      if (_disposed) {
        return;
      }
      _deliverReport(_diag.returned(syncId));
      if (result?['accepted'] != true) {
        throw MarkerSyncException('resync 未被接受');
      }
      _applyResync(snapshot, _readIds(result?['rejectedMarkerIds']));
    } catch (e) {
      if (_disposed) {
        return;
      }
      onSyncError?.call(MarkerSyncException('markers#resync 失败', e));
      // 延迟后由发送循环再试，次数上限在入口检查，避免忙循环
      _scheduleRetry();
    } finally {
      if (!_disposed) {
        _inFlightImages = <String, MarkerImageResource>{};
      }
    }
  }

  /// 以快照 E 为全量目标推进基准（R-SYNC-7）。
  void _applyResync(MarkerResyncSnapshot s, Set<String> rejectedIds) {
    final Map<String, Marker> next = <String, Marker>{};
    s.markers.forEach((String id, Marker m) {
      final Marker? old = _confirmed[id];
      if (!rejectedIds.contains(id)) {
        next[id] = m;
        // 代入的旧值被接受不代表非法 pending 已修正，rejected 保留
        if (!s.substituted.contains(id)) {
          _rejected.remove(id);
        }
      } else {
        if (old != null) {
          next[id] = old;
        }
        if (!s.substituted.contains(id)) {
          _rejected[id] = m;
        }
      }
    });
    _confirmed
      ..clear()
      ..addAll(next);
    // 不在快照中的资源原生进入 releasing，Dart 副本与镜像随之移除
    for (final String id in _confirmedImages.keys.toList()) {
      if (!s.images.containsKey(id)) {
        _imageSync.released(id, stillWanted: _targetImages.containsKey(id));
      }
    }
    _confirmedImages
      ..clear()
      ..addAll(s.images);
    _needsResync = false;
    // resync 后原生以快照为准，过渡条目全部失效（R-DEL-3）
    _retiring.clear();
    // resync 后基准与目标一致（被拒值除外），不会立刻再触发同一失败
    _resyncAttempts = 0;
  }
}
