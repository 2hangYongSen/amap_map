package com.amap.flutter.map.overlays.marker.nativemarker;

/** 解码结果的抽象：Android 为 Bitmap（BitmapImage），JVM 测试为替身 */
public interface DecodedImage {
    /** 像素宽高 */
    int width();

    int height();

    /** 内存占用，Android 取 getAllocationByteCount()（R-RES-11） */
    long byteCount();

    void recycle();

    boolean isRecycled();
}
