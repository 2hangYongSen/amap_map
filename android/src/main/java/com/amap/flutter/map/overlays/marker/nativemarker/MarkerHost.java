package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 管理器对地图 SDK 的全部操作出口；生产实现是 MarkersController，JVM 单测用假实现。
 * 所有方法都在主线程调用。
 */
public interface MarkerHost {
    /** 地图上是否已有该 Dart id 的 Marker（含旧协议登记的点，R-PROTO-1a） */
    boolean hasMarker(String id);

    /** 新增 Marker；icon 为 decodeIcon 或 defaultIcon 的返回值 */
    void addMarker(FullMarkerOptions options, Object icon);

    /** 完整替换已有 Marker 的属性；icon 为 null 表示保留当前图标（R-PROTO-4） */
    void updateMarker(FullMarkerOptions options, Object icon);

    /** 删除 Marker，id 不存在时忽略 */
    void removeMarker(String id);

    /** 当前地图上全部 Marker 的 Dart id（resync 清理用） */
    Iterable<String> markerIds();

    /** 解码旧 icon 描述；无法解析时抛 RuntimeException */
    Object decodeIcon(Object rawIcon);

    /** native 点位尚未绘制时的占位图标（S5：默认 icon） */
    Object defaultIcon();
}
