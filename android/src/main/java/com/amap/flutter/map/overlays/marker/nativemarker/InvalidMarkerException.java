package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 单个点位校验失败（R-NAT-REJ-1）：只拒绝这个点，不影响同批其他点。
 */
public class InvalidMarkerException extends Exception {
    public InvalidMarkerException(String message) {
        super(message);
    }
}
