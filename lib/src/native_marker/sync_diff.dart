import '../types/marker.dart';
import '../types/marker_image_resource.dart';
import 'protocol.dart';

/// 一次点位请求的差异（以 confirmed 为基准，R-SYNC-1）。
class MarkerSyncDiff {
  MarkerSyncDiff({
    required this.adds,
    required this.changes,
    required this.removes,
    required this.imagesToAdd,
    required this.imagesToRelease,
  });

  final Map<String, Marker> adds;
  final Map<String, Marker> changes;
  final Set<String> removes;
  final Map<String, MarkerImageResource> imagesToAdd;
  final Set<String> imagesToRelease;

  /// 点位与资源差异都为空时不发送（R-SYNC-2）
  bool get isEmpty =>
      adds.isEmpty &&
      changes.isEmpty &&
      removes.isEmpty &&
      imagesToAdd.isEmpty &&
      imagesToRelease.isEmpty;

  /// 新协议 `markers#update` 载荷（§6.2）
  Map<String, dynamic> toV2Payload(int syncId) => <String, dynamic>{
        'protocolVersion': kMarkerProtocolVersion,
        'syncId': syncId,
        'imagesToAdd': imagesToAdd.values
            .map((MarkerImageResource r) => r.toMap())
            .toList(),
        'imageIdsToRelease': imagesToRelease.toList(),
        'markersToAdd': adds.values.map(markerToV2Map).toList(),
        'markersToChange': changes.values.map(markerToV2Map).toList(),
        'markerIdsToRemove': removes.toList(),
      };
}

/// 计算 confirmed → target 的差异。
///
/// - 与 rejected 中相同的值视为无变化，不重发（R-SYNC-6）；
/// - 资源释放需排除仍被保留点位引用的 id（R-RES-3）：
///   修改可能被拒绝，旧值的依赖在本次请求里继续保留。
MarkerSyncDiff computeMarkerDiff({
  required Map<String, Marker> confirmed,
  required Map<String, Marker> rejected,
  required Map<String, MarkerImageResource> confirmedImages,
  required Map<String, Marker> target,
  required Map<String, MarkerImageResource> targetImages,
  Set<String> resendImageIds = const <String>{},
}) {
  final Map<String, Marker> adds = <String, Marker>{};
  final Map<String, Marker> changes = <String, Marker>{};
  target.forEach((String id, Marker m) {
    if (rejected[id] == m) {
      return;
    }
    final Marker? old = confirmed[id];
    if (old == null) {
      adds[id] = m;
    } else if (old != m) {
      changes[id] = m;
    }
  });
  final Set<String> removes =
      confirmed.keys.where((String id) => !target.containsKey(id)).toSet();

  final Map<String, MarkerImageResource> imagesToAdd =
      <String, MarkerImageResource>{};
  targetImages.forEach((String id, MarkerImageResource r) {
    // 未登记的新资源，或需要重试的已登记资源（R-RES-4/8）
    if (!confirmedImages.containsKey(id) || resendImageIds.contains(id)) {
      imagesToAdd[id] = r;
    }
  });
  // 保护集合：新目标资源 + 本次后仍可能留在原生的点位依赖
  final Set<String> needed = <String>{...targetImages.keys};
  confirmed.forEach((String id, Marker m) {
    if (!removes.contains(id)) {
      needed.addAll(markerImageDeps(m));
    }
  });
  for (final Marker m in <Marker>[...adds.values, ...changes.values]) {
    needed.addAll(markerImageDeps(m));
  }
  final Set<String> imagesToRelease =
      confirmedImages.keys.where((String id) => !needed.contains(id)).toSet();

  return MarkerSyncDiff(
    adds: adds,
    changes: changes,
    removes: removes,
    imagesToAdd: imagesToAdd,
    imagesToRelease: imagesToRelease,
  );
}

/// resync 的有效快照（R-SYNC-7）。
class MarkerResyncSnapshot {
  MarkerResyncSnapshot(this.markers, this.substituted, this.images);

  /// 有效点位快照 E
  final Map<String, Marker> markers;

  /// 因 rejected 而改用 confirmed 旧值的 id
  final Set<String> substituted;

  /// 发送的完整资源集合
  final Map<String, MarkerImageResource> images;

  Map<String, dynamic> toPayload(int syncId) => <String, dynamic>{
        'protocolVersion': kMarkerProtocolVersion,
        'syncId': syncId,
        'images':
            images.values.map((MarkerImageResource r) => r.toMap()).toList(),
        'markers': markers.values.map(markerToV2Map).toList(),
      };
}

/// 构造 resync 快照；依赖资源无法解析时抛出 [StateError]（R-RES-14 不变量）。
MarkerResyncSnapshot buildResyncSnapshot({
  required Map<String, Marker> confirmed,
  required Map<String, Marker> rejected,
  required Map<String, MarkerImageResource> confirmedImages,
  required Map<String, Marker> target,
  required Map<String, MarkerImageResource> targetImages,
}) {
  final Map<String, Marker> effective = <String, Marker>{};
  final Set<String> substituted = <String>{};
  target.forEach((String id, Marker m) {
    if (rejected[id] == m) {
      // 已知非法值不重发，改用 confirmed 旧值（不存在就省略）
      final Marker? old = confirmed[id];
      if (old != null) {
        effective[id] = old;
        substituted.add(id);
      }
    } else {
      effective[id] = m;
    }
  });
  // 资源 = 当前目标资源 ∪ E 的依赖 ∪ E 中点位的 confirmed 旧值依赖
  final Set<String> ids = <String>{...targetImages.keys};
  effective.forEach((String id, Marker m) {
    ids.addAll(markerImageDeps(m));
    final Marker? old = confirmed[id];
    if (old != null) {
      ids.addAll(markerImageDeps(old));
    }
  });
  final Map<String, MarkerImageResource> images =
      <String, MarkerImageResource>{};
  for (final String id in ids) {
    final MarkerImageResource? r = targetImages[id] ?? confirmedImages[id];
    if (r == null) {
      throw StateError("resync 缺少图片资源 '$id'");
    }
    images[id] = r;
  }
  return MarkerResyncSnapshot(effective, substituted, images);
}
