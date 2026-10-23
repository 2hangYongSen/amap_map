import '../types/marker_selection.dart';

/// 新协议的原生事件（§6.1），由通道层原样交给发送队列处理。
///
/// 包括 `marker#imagesResult`、`marker#selectionChanged`、
/// `markers#removed`、`marker#nativeError`。
class MarkerProtocolMessage {
  MarkerProtocolMessage(this.method, this.args);

  /// 从通道参数构造；参数不是 Map 时按空 Map 处理
  factory MarkerProtocolMessage.fromArguments(String method, Object? raw) =>
      MarkerProtocolMessage(
          method, raw is Map ? raw : const <Object?, Object?>{});

  final String method;
  final Map<Object?, Object?> args;

  /// 原生按会话单调递增分配的序号；缺省时不参与去重
  int? get eventSeq => (args['eventSeq'] as num?)?.toInt();
}

/// 解析 `marker#selectionChanged`；原因未知时返回 null。
MarkerSelectionChange? selectionChangeFromMap(Map<Object?, Object?> raw) {
  final Object? reason = raw['reason'];
  final Object? revision = raw['revision'];
  if (revision is! num) {
    return null;
  }
  for (final MarkerSelectionReason r in MarkerSelectionReason.values) {
    if (r.name == reason) {
      return MarkerSelectionChange(
        selectedId: raw['selectedId'] as String?,
        previousId: raw['previousId'] as String?,
        reason: r,
        revision: revision.toInt(),
      );
    }
  }
  return null;
}
