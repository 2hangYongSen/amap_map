part of 'sync_queue.dart';

/// 发送循环、握手、选项与选择命令（R-INIT-7 的发送顺序）。
extension _MarkerSyncOps on MarkerSyncQueue {
  /// 触发一次发送循环；已销毁时什么都不做
  void _kick() {
    if (!_disposed) {
      unawaited(_pump());
    }
  }

  /// 外部新更新可以重新触发已停止的自动恢复（R-INIT-7、R-RES-14）
  void _resumeAfterExternalChange() {
    _stalled = false;
    _attachAttempts = 0;
    _resyncAttempts = 0;
    _missingResyncs = 0;
    _kick();
  }

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
  ///
  /// 顺序：握手 → 选项 → resync → 点位 → 选择命令（R-INIT-7）。
  Future<void>? _nextRequest() {
    final MarkerSyncTransport? t = _transport;
    if (_disposed || _stalled || t == null || _retryTimer != null) {
      return null;
    }
    // 1. 新协议创建：先握手确认初始快照（R-SYNC-4）
    if (_initialMarkers != null) {
      return _attach(t, initial: true);
    }
    // 2. 运行中首次需要新能力：等旧请求返回后握手升级（R-PROTO-0）
    if (_wantV2 && !_v2) {
      return _attach(t, initial: false);
    }
    // 3. 选项只在握手后发送，不被“无变化不发送”抑制
    final MarkerSyncOptions o = _options;
    if (_v2 && o != _confirmedOptions && o != _failedOptions) {
      return _sendOptions(t, o);
    }
    // 不在目标中的 id 清除拒绝记录（R-SYNC-6）
    _rejected.removeWhere((String id, _) => !_target.containsKey(id));
    // 4. 失败恢复只走新协议（R-INIT-8）
    if (_v2 && _needsResync) {
      return _resync(t);
    }
    final Future<void>? markers = _v2 ? _sendV2(t) : _sendLegacy(t);
    if (markers != null) {
      return markers;
    }
    // 5. 选择命令排在点位之后，只等请求接受，不等绘制
    if (_v2 && _commands.isNotEmpty) {
      return _sendSelect(t, _commands.removeAt(0));
    }
    return null;
  }

  Future<void> _attach(MarkerSyncTransport t, {required bool initial}) async {
    _attachAttempts++;
    final Map<Object?, Object?>? result;
    try {
      result = await t.attach();
    } catch (e) {
      if (_disposed) {
        return;
      }
      // 依赖请求不发往未就绪协议，排队命令以错误结束（R-INIT-7）
      _failCommands(MarkerSyncException('markers#attach 失败', e));
      if (_attachAttempts >= MarkerSyncQueue.maxRecoveryAttempts) {
        _stall('markers#attach 失败，已停止自动重试', e);
      } else {
        _scheduleRetry();
      }
      return;
    }
    if (_disposed) {
      return;
    }
    _attachAttempts = 0;
    _v2 = true;
    if (initial) {
      _confirmInitial(_readIds(result?['rejectedMarkerIds']));
    }
    // 运行中升级：保留现有 confirmed，不重放初始快照（R-INIT-3）
    _installSnapshot(result);
  }

  Future<void> _sendOptions(MarkerSyncTransport t, MarkerSyncOptions o) async {
    try {
      await t.updateOptions(o.toMap());
      if (_disposed) {
        return;
      }
      _confirmedOptions = o;
    } catch (e) {
      if (_disposed) {
        return;
      }
      // 同一份选项不再自动重发，等外部改动（避免忙循环）
      _failedOptions = o;
      onSyncError?.call(MarkerSyncException('点位选项更新失败', e));
    }
  }

  Future<void> _sendSelect(MarkerSyncTransport t, _SelectCommand cmd) async {
    try {
      final Map<Object?, Object?>? r = await t.setSelected(cmd.markerId);
      final Object? revision = r?['revision'];
      if (_disposed) {
        // 迟到结果不交付成功，按已销毁结束（R-DART-DISP）
        throw MarkerSyncException('地图已销毁');
      }
      if (revision is! num) {
        throw MarkerSyncException('markers#setSelected 返回缺少 revision');
      }
      cmd.completer.complete(revision.toInt());
    } catch (e) {
      if (!cmd.completer.isCompleted) {
        cmd.completer.completeError(e is MarkerSyncException
            ? e
            : MarkerSyncException('markers#setSelected 失败', e));
      }
    }
  }

  /// 握手或 resync 失败后延迟再试；计时器在销毁时取消
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      _kick();
    });
  }

  void _failCommands(MarkerSyncException error) {
    final List<_SelectCommand> pending = List<_SelectCommand>.of(_commands);
    _commands.clear();
    for (final _SelectCommand c in pending) {
      if (!c.completer.isCompleted) {
        c.completer.completeError(error);
      }
    }
  }

  void _stall(String message, Object cause) {
    _stalled = true;
    final MarkerSyncException error = MarkerSyncException(message, cause);
    _failCommands(error);
    onSyncError?.call(error);
  }

  Set<String> _readIds(Object? raw) => raw is List
      ? raw.whereType<String>().toSet()
      : const <String>{};
}
