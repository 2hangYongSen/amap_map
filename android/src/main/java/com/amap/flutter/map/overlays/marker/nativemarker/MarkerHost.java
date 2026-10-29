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

    /**
     * 新增 native Marker：图标与锚点来自合成画布（§9.2），其余属性取最新快照（R-GEN-4）。
     * selected 为真时 zIndex 取 selectedZIndex ?? zIndex（§8.5）
     */
    void addNativeMarker(FullMarkerOptions options, NativeIcon icon, boolean selected);

    /**
     * 更新已有 Marker 为 native 外观。icon 非空：setIcon + 锚点 + 属性；
     * icon 为空：只更新位置等属性，不改图标与锚点（R-GEN-5）。zIndex 规则同上
     */
    void updateNativeMarker(FullMarkerOptions options, NativeIcon icon, boolean selected);

    /**
     * 批量新增 native Marker（三个列表一一对应），生产实现一次 addMarkers。
     * 抛异常时调用方按整批失败处理（生产实现保证不留下其中任何点）；默认逐个调用 addNativeMarker（单测假实现用）
     */
    default void addNativeMarkers(java.util.List<FullMarkerOptions> options,
                                  java.util.List<NativeIcon> icons, java.util.List<Boolean> selected) {
        for (int i = 0; i < options.size(); i++) {
            addNativeMarker(options.get(i), icons.get(i), selected.get(i));
        }
    }
}
