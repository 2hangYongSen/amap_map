package com.amap.flutter.map.overlays.marker.nativemarker;

/** 合成位图与 SDK descriptor 的转换和回收（R-CACHE-3/4），主线程调用；S10 提供 SDK 实现 */
public interface IconFactory {
    /** fromBitmap 后立即回收合成位图，只返回 descriptor（SDK 已复制像素） */
    Object toDescriptor(Object bitmap);

    /** 统计用：descriptor.getBitmap().getAllocationByteCount() */
    long byteCount(Object descriptor);

    /** 淘汰条目：回收 SDK 副本 descriptor.getBitmap()；不调用 descriptor.recycle()（空操作） */
    void recycleCopy(Object descriptor);

    /** 销毁后迟到的任务输出：从未交给 SDK，直接回收合成位图（R-DISP-2） */
    void discard(Object bitmap);
}
