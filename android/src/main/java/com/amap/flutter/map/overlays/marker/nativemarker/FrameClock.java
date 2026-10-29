package com.amap.flutter.map.overlays.marker.nativemarker;

/** 帧回调与计时：Android 用 Choreographer 与 System.nanoTime，JVM 测试用可控替身 */
public interface FrameClock {
    void postFrame(Runnable r);

    void removeFrame(Runnable r);

    long nanoTime();
}
