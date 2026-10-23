package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 应用项 (markerId, generation, key, role)（§8.2）：持有缓存条目的一个 pendingRefs。
 * 不携带位置等属性，应用时读最新快照（R-GEN-4）。
 */
final class ApplyItem {
    final PointTable.Entry point;
    final int generation;
    final boolean selected;
    final RenderCache.Entry icon;
    /** 生成时点位上是否已有 Marker，只用于“新增先于修改”的排序（§8.4） */
    final boolean isAdd;
    /** 已丢弃：pendingRefs 已归还，帧回调跳过 */
    boolean dropped = false;

    ApplyItem(PointTable.Entry point, int generation, boolean selected, RenderCache.Entry icon,
              boolean isAdd) {
        this.point = point;
        this.generation = generation;
        this.selected = selected;
        this.icon = icon;
        this.isAdd = isAdd;
    }
}
