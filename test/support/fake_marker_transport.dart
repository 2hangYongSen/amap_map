import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';

/// 一次通道调用的记录
class SentCall {
  SentCall(this.method, this.payload);

  final String method;
  final Object? payload;

  Map<String, dynamic> get map => payload as Map<String, dynamic>;
}

/// 可控的假通道：默认立即接受；可让某次调用挂起或失败。
class FakeMarkerTransport implements MarkerSyncTransport {
  final List<SentCall> calls = <SentCall>[];

  /// 下一次调用的处理器，返回 null 表示用默认行为
  final List<Future<Map<Object?, Object?>?> Function(SentCall)> _scripted =
      <Future<Map<Object?, Object?>?> Function(SentCall)>[];

  /// 追加一个按顺序消费的处理器
  void next(Future<Map<Object?, Object?>?> Function(SentCall call) handler) =>
      _scripted.add(handler);

  /// 下一次调用挂起，返回用于放行的 Completer
  Completer<Map<Object?, Object?>?> hold() {
    final Completer<Map<Object?, Object?>?> c =
        Completer<Map<Object?, Object?>?>();
    next((_) => c.future);
    return c;
  }

  /// 下一次调用抛出异常
  void fail() => next((_) async => throw Exception('mock failure'));

  /// 下一次调用接受，但拒绝指定点位
  void reject(List<String> ids) => next((SentCall c) async => accepted(c, ids));

  static Map<Object?, Object?> accepted(SentCall c,
      [List<String> rejected = const <String>[]]) {
    final Object? p = c.payload;
    return <Object?, Object?>{
      'syncId': p is Map ? p['syncId'] ?? 0 : 0,
      'accepted': true,
      'rejectedMarkerIds': rejected,
    };
  }

  List<SentCall> byMethod(String method) =>
      calls.where((SentCall c) => c.method == method).toList();

  Future<Map<Object?, Object?>?> _dispatch(SentCall call) {
    calls.add(call);
    if (_scripted.isNotEmpty) {
      return _scripted.removeAt(0)(call);
    }
    return Future<Map<Object?, Object?>?>.value(accepted(call));
  }

  @override
  Future<void> updateLegacy(MarkerUpdates updates) =>
      _dispatch(SentCall('legacy', updates.toMap()));

  @override
  Future<Map<Object?, Object?>?> attach() => _dispatch(
      SentCall('markers#attach', <String, dynamic>{'protocolVersion': 2}));

  @override
  Future<Map<Object?, Object?>?> update(Map<String, dynamic> payload) =>
      _dispatch(SentCall('markers#update', payload));

  @override
  Future<Map<Object?, Object?>?> resync(Map<String, dynamic> payload) =>
      _dispatch(SentCall('markers#resync', payload));

  @override
  Future<void> updateOptions(Map<String, dynamic> options) =>
      _dispatch(SentCall('map#update', options));

  /// 选择命令默认返回递增的 revision
  int revision = 0;

  @override
  Future<Map<Object?, Object?>?> setSelected(String? markerId) {
    final SentCall call =
        SentCall('markers#setSelected', <String, dynamic>{'markerId': markerId});
    if (_scripted.isNotEmpty) {
      calls.add(call);
      return _scripted.removeAt(0)(call);
    }
    calls.add(call);
    return Future<Map<Object?, Object?>?>.value(
        <Object?, Object?>{'revision': ++revision});
  }
}

/// 构造一条新协议原生事件
MarkerProtocolMessage msg(String method, int seq, Map<String, Object?> args) =>
    MarkerProtocolMessage(method, <Object?, Object?>{...args, 'eventSeq': seq});

/// 让微任务与已完成的 Future 回调全部执行
Future<void> flush() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 从载荷中取某个列表里的点位 id
List<String> idsIn(Map<String, dynamic> payload, String key) =>
    (payload[key] as List<dynamic>)
        .map((dynamic m) => (m as Map<String, dynamic>)['id'] as String)
        .toList();
