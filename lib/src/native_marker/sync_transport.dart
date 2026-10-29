import '../types/marker_updates.dart';

/// 队列向原生发送请求的出口；控制器实现它，测试用假实现。
abstract class MarkerSyncTransport {
  /// 旧协议 `markers#update`，成功返回即视为接受（R-INIT-8）
  Future<void> updateLegacy(MarkerUpdates updates);

  /// `markers#attach({protocolVersion: 2})`（R-INIT-3）
  Future<Map<Object?, Object?>?> attach();

  /// 新协议 `markers#update`（§6.2、§6.5）
  Future<Map<Object?, Object?>?> update(Map<String, dynamic> payload);

  /// `markers#resync` 全量快照（R-SYNC-7）
  Future<Map<Object?, Object?>?> resync(Map<String, dynamic> payload);

  /// `map#update.options` 中的点位选项（选择、过渡），仅新协议
  Future<void> updateOptions(Map<String, dynamic> options);

  /// `markers#setSelected`，返回 `{revision}`
  Future<Map<Object?, Object?>?> setSelected(String? markerId);
}

/// 同步过程中的错误（请求失败、恢复停止、会话已销毁等）。
class MarkerSyncException implements Exception {
  MarkerSyncException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'MarkerSyncException: $message${cause == null ? '' : ' ($cause)'}';
}
