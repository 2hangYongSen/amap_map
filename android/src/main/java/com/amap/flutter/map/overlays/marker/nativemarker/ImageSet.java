package com.amap.flutter.map.overlays.marker.nativemarker;

/** 绘制阶段读取资源：在解析结果之外还能拿到解码结果与像素比（PaintJob 在主线程拍快照） */
public interface ImageSet extends ImageResolver {
    /** 可用资源的解码结果；不可用时为 null */
    DecodedImage image(String imageId);

    /** 资源像素比（与 logicalSize 的换算同源）；不可用时返回 1 */
    double pixelRatio(String imageId);
}
