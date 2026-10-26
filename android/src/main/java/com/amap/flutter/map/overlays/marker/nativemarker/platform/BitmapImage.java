package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Bitmap;

import com.amap.flutter.map.overlays.marker.nativemarker.DecodedImage;

/** 解码结果：包装 Bitmap，占用取 getAllocationByteCount()（R-RES-11） */
public final class BitmapImage implements DecodedImage {
    public final Bitmap bitmap;

    BitmapImage(Bitmap bitmap) {
        this.bitmap = bitmap;
    }

    @Override public int width() { return bitmap.getWidth(); }
    @Override public int height() { return bitmap.getHeight(); }
    @Override public long byteCount() { return bitmap.getAllocationByteCount(); }
    @Override public void recycle() { bitmap.recycle(); }
    @Override public boolean isRecycled() { return bitmap.isRecycled(); }
}
