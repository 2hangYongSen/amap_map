import '../types/marker.dart';

/// 过渡中的待删除点（R-DEL-3）：保留最后一次的 Marker，点击时仍能调用其回调。
class RetiringMarkers {
  final Map<String, _RetiringEntry> _entries = <String, _RetiringEntry>{};

  /// 当前过渡条目的 id
  Iterable<String> get ids => _entries.keys;

  bool get isEmpty => _entries.isEmpty;

  /// 查找过渡点的最后一次 Marker
  Marker? operator [](String id) => _entries[id]?.marker;

  /// 点位从集合中消失：记录最后一次的对象，syncId 等发送时再填
  void retire(Marker marker) => _entries[marker.id] = _RetiringEntry(marker);

  /// 同一 id 重新加入集合：立即删除过渡条目
  void revive(String id) => _entries.remove(id);

  /// 携带删除的请求已发出：为尚未分配的条目记下 removeSyncId
  void assignSyncId(Iterable<String> removedIds, int syncId) {
    for (final String id in removedIds) {
      final _RetiringEntry? e = _entries[id];
      if (e != null && e.removeSyncId == null) {
        e.removeSyncId = syncId;
      }
    }
  }

  /// immediate 模式下请求被接受：删除已在请求内完成
  void settle(int syncId) =>
      _entries.removeWhere((_, _RetiringEntry e) => e.removeSyncId == syncId);

  /// `markers#removed`：只在 syncId 匹配时删除，避免误删后来的条目
  void removed(String id, int syncId) {
    if (_entries[id]?.removeSyncId == syncId) {
      _entries.remove(id);
    }
  }

  /// 删除从未随请求发出、原生也没有的条目（例如新增被拒后又移除）
  void dropUnsent(bool Function(String id) onNative) => _entries.removeWhere(
      (String id, _RetiringEntry e) => e.removeSyncId == null && !onNative(id));

  /// resync 返回或会话销毁时清空
  void clear() => _entries.clear();
}

class _RetiringEntry {
  _RetiringEntry(this.marker);

  final Marker marker;
  int? removeSyncId;
}
