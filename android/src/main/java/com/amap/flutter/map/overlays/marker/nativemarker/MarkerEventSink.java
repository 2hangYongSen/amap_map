package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Map;

/**
 * 原生→Dart 的新协议事件出口（R-PROTO-0：只在新协议启用并握手后调用）。
 */
public interface MarkerEventSink {
    void emit(String method, Map<String, Object> args);
}
