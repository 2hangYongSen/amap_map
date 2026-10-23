package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 布局与渲染 key 查询资源解析结果（R-RES-12）。S8 由 ImageRegistry 提供实现。
 */
public interface ImageResolver {
    /** ready 或 pending 视为可用（pending 按 ready 解析 key）；failed 或未知为 fallback */
    boolean usable(String imageId);

    /** ready 时返回逻辑尺寸 [w, h]（像素 / pixelRatio）；尚未解码时返回 null */
    double[] logicalSize(String imageId);
}
