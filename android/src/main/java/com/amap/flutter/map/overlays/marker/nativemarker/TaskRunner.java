package com.amap.flutter.map.overlays.marker.nativemarker;

/** 线程出口：后台执行与投递回主线程。JVM 测试用可控替身逐步执行 */
public interface TaskRunner {
    void background(Runnable r);

    void main(Runnable r);
}
