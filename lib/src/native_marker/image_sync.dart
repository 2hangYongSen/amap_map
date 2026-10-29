import 'dart:async';

import '../types/marker_image_resource.dart';

/// Dart 端资源镜像状态（§7.2）
enum MarkerImageState { unsent, sent, ready, failed }

/// 单个资源的镜像
class MarkerImageStatus {
  MarkerImageStatus(this.state, {this.attempts = 0});

  MarkerImageState state;

  /// 失败次数（R-RES-7）
  int attempts;

  @override
  String toString() => 'MarkerImageStatus($state, attempts: $attempts)';
}

/// 资源状态镜像与 asset 自动重试（R-RES-2/4/7/8）。
///
/// 只记录状态，不持有资源对象；对象由发送队列的保留集合提供（R-RES-14）。
class MarkerImageSync {
  MarkerImageSync({required this.onRetryDue});

  /// asset 失败后的重试间隔，最多 3 次（R-RES-8）
  static const List<Duration> retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 4),
    Duration(seconds: 16),
  ];

  /// 重试时间到，需要重新发送；由队列触发一次发送
  final void Function() onRetryDue;

  final Map<String, MarkerImageStatus> _status = <String, MarkerImageStatus>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  final Set<String> _resend = <String>{};
  bool _disposed = false;

  /// 状态只读视图
  Map<String, MarkerImageStatus> get status =>
      Map<String, MarkerImageStatus>.unmodifiable(_status);

  /// 已登记但需要再次放入 imagesToAdd 的 id
  Set<String> get resendIds => Set<String>.unmodifiable(_resend);

  /// 是否有等待中的重试计时器
  bool get hasPendingRetry => _timers.isNotEmpty;

  MarkerImageStatus? operator [](String id) => _status[id];

  /// 已随请求发出：进入 sent，等待原生结果（R-RES-2）
  void markSent(Iterable<String> ids) {
    for (final String id in ids) {
      _resend.remove(id);
      _cancelTimer(id);
      (_status[id] ??= MarkerImageStatus(MarkerImageState.sent)).state =
          MarkerImageState.sent;
    }
  }

  /// 原生回报 ready
  void markReady(String id) {
    final MarkerImageStatus? s = _status[id];
    if (s == null) {
      return; // 已释放的资源，迟到结果忽略
    }
    _cancelTimer(id);
    _resend.remove(id);
    s.state = MarkerImageState.ready;
  }

  /// 原生回报 failed：失败次数 +1，asset 按退避重试（R-RES-7/8）。
  ///
  /// 已处于 failed 的重复结果不再计数，保证幂等。
  void markFailed(String id, MarkerImageResource? resource) {
    final MarkerImageStatus? s = _status[id];
    if (s == null || s.state == MarkerImageState.failed) {
      return;
    }
    s
      ..state = MarkerImageState.failed
      ..attempts += 1;
    // 字节资源内容确定，失败不重试；asset 可能暂不可读
    if (resource?.type != MarkerImageSourceType.asset ||
        s.attempts > retryDelays.length) {
      return;
    }
    _cancelTimer(id);
    _timers[id] = Timer(retryDelays[s.attempts - 1], () {
      _timers.remove(id);
      if (_disposed || _status[id]?.state != MarkerImageState.failed) {
        return;
      }
      _resend.add(id);
      onRetryDue();
    });
  }

  /// 资源先移除再加入：asset 失败的重新获得重试机会（R-RES-8）
  void reintroduced(String id, MarkerImageResource resource) {
    final MarkerImageStatus? s = _status[id];
    if (s == null ||
        s.state != MarkerImageState.failed ||
        resource.type != MarkerImageSourceType.asset ||
        _timers.containsKey(id)) {
      return;
    }
    s.attempts = 0;
    _resend.add(id);
  }

  /// 不再需要重发（例如已不在目标集合中）
  void dropResend(String id) => _resend.remove(id);

  /// 释放已确认：仍被引用时回到 unsent 等待重新登记，否则彻底移除（R-RES-14）
  void released(String id, {required bool stillWanted}) {
    _cancelTimer(id);
    _resend.remove(id);
    if (stillWanted) {
      _status[id] = MarkerImageStatus(MarkerImageState.unsent);
    } else {
      _status.remove(id);
    }
  }

  /// 销毁：取消全部计时器并清空（R-DART-DISP）
  void dispose() {
    _disposed = true;
    for (final Timer t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _status.clear();
    _resend.clear();
  }

  void _cancelTimer(String id) => _timers.remove(id)?.cancel();
}
