package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Bitmap;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;

import com.amap.flutter.map.overlays.marker.nativemarker.IconFactory;

/**
 * 合成位图与 SDK descriptor 的转换（R-CACHE-3，E-A1 通过）：
 * fromBitmap 内部复制像素，合成位图立即回收；淘汰时回收 SDK 副本，不调用 descriptor.recycle()。
 */
public final class AndroidIconFactory implements IconFactory {
    @Override
    public Object toDescriptor(Object bitmap) {
        Bitmap b = (Bitmap) bitmap;
        try {
            return BitmapDescriptorFactory.fromBitmap(b);
        } finally {
            b.recycle();
        }
    }

    @Override
    public long byteCount(Object descriptor) {
        Bitmap b = ((BitmapDescriptor) descriptor).getBitmap();
        return b == null ? 0 : b.getAllocationByteCount();
    }

    @Override
    public void recycleCopy(Object descriptor) {
        Bitmap b = ((BitmapDescriptor) descriptor).getBitmap();
        if (b != null && !b.isRecycled()) {
            b.recycle();
        }
    }

    @Override
    public void discard(Object bitmap) {
        ((Bitmap) bitmap).recycle();
    }
}
