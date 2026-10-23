package com.amap.flutter.map.overlays.marker;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.flutter.map.utils.ConvertUtil;

/**
 * 旧 icon 描述的解码出口；生产用 ConvertUtil，JVM 单测替换为假实现。
 */
public interface MarkerIconDecoder {
    BitmapDescriptor decode(Object rawIcon);

    MarkerIconDecoder DEFAULT = new MarkerIconDecoder() {
        @Override
        public BitmapDescriptor decode(Object rawIcon) {
            return ConvertUtil.toBitmapDescriptor(rawIcon);
        }
    };
}
