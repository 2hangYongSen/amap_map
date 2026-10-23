part of 'sync_queue.dart';

/// 发送循环与各类请求的处理（拆出以控制文件长度）。
extension _MarkerSyncOps on MarkerSyncQueue {
  /// 串行发送：同一时刻最多一个在途请求，返回后再看是否还有工作。
  Future<void> _pump() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      while (true) {
        // 决策必须同步完成，避免在“判定无事可做”与“释放 busy”之间漏掉新目标
        final Future<void>? request = _nextRequest();
        if (request == null) {
          break;
        }
        await request;
      }
    } finally {
      _busy = false;
    }
  }

  /// 选出下一个要发的请求；无事可做返回 null。
  Future<void>? _nextRequest() {
    final MarkerSyncTransport? transport = _transport;
    if (_disposed || _stalled || transport == null) {
      return null;
    }
    // 1. 新协议创建：先握手确认初始快照（R-SYNC-4）
    if (_initialMarkers != null) {
      return _attach(transport, initial: true);
    }
    // 2. 运行中首次需要新能力：等旧请求返回后握手升级（R-PROTO-0）
    if (_wantV2 && !_v2) {
      return _attach(transport, initial: false);
    }
    // 不在目标中的 id 清除拒绝记录（R-SYNC-6）
    _rejected.removeWhere((String id, _) => !_target.containsKey(id));
    // 3. 失败恢复只走新协议（R-INIT-8）
    if (_v2 && _needsResync) {
      return _resync(transport);
    }
    return _v2 ? _sendV2(transport) : _sendLegacy(transport);
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

  Future<void> _attach(MarkerSyncTransport t, {required bool initial}) async {
    _attachAttempts++;
    try {
      final Map<Object?, Object?>? result = await t.attach();
      if (_disposed) {
        return;
      }
      _attachAttempts = 0;
      _v2 = true;
      if (initial) {
        _confirmInitial(_readIds(result?['rejectedMarkerIds']));
      }
      // 运行中升级：保留现有 confirmed，不重放初始快照（R-INIT-3）
    } catch (e) {
      if (_disposed) {
        return;
      }
      // 最多自动重试一次，之后停止，等外部新更新再触发（R-INIT-7）
      if (_attachAttempts >= MarkerSyncQueue.maxRecoveryAttempts) {
        _stall('markers#attach 失败，已停止自动重试', e);
      }
    }
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
    final MarkerSyncDiff diff = computeMarkerDiff(
      confirmed: _confirmed,
      rejected: _rejected,
      confirmedImages: _confirmedImages,
      target: _target,
      targetImages: _targetImages,
    );
    return diff.isEmpty ? null : _doSendV2(t, diff);
  }

  Future<void> _doSendV2(MarkerSyncTransport t, MarkerSyncDiff diff) async {
    final int syncId = ++_syncId;
    try {
      final Map<Object?, Object?>? result =
          await t.update(diff.toV2Payload(syncId));
      if (_disposed) {
        return;
      }
      if (result?['accepted'] != true) {
        _needsResync = true;
        return;
      }
      _applyAccepted(diff, _readIds(result?['rejectedMarkerIds']));
      _resyncAttempts = 0;
    } catch (_) {
      if (_disposed) {
        return;
      }
      // 新协议失败：confirmed 不变，转入 resync（R-SYNC-3）
      _needsResync = true;
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
    diff.imagesToRelease.forEach(_confirmedImages.remove);
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
    try {
      final Map<Object?, Object?>? result =
          await t.resync(snapshot.toPayload(syncId));
      if (_disposed) {
        return;
      }
      if (result?['accepted'] != true) {
        throw MarkerSyncException('resync 未被接受');
      }
      _applyResync(snapshot, _readIds(result?['rejectedMarkerIds']));
    } catch (e) {
      if (_disposed) {
        return;
      }
      // 失败后由发送循环再试，次数上限在入口检查
      onSyncError?.call(MarkerSyncException('markers#resync 失败', e));
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
    _confirmedImages
      ..clear()
      ..addAll(s.images);
    _needsResync = false;
    // resync 后基准与目标一致（被拒值除外），不会立刻再触发同一失败
    _resyncAttempts = 0;
  }

  void _stall(String message, Object cause) {
    _stalled = true;
    onSyncError?.call(MarkerSyncException(message, cause));
  }

  Set<String> _readIds(Object? raw) => raw is List
      ? raw.whereType<String>().toSet()
      : const <String>{};
}
