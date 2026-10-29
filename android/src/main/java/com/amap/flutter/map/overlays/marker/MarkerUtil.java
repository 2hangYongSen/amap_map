package com.amap.flutter.map.overlays.marker;

import com.amap.flutter.map.utils.ConvertUtil;

import java.util.List;
import java.util.Map;

/**
 * @author whm
 * @date 2020/11/6 8:06 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
public class MarkerUtil {
    /** 旧协议解析：字段为 null 即跳过（“缺失等于不修改”，R-PROTO-3） */
    public static String interpretMarkerOptions(Object o, MarkerOptionsSink sink) {
        return interpretMarkerOptions(o, sink, MarkerIconDecoder.DEFAULT);
    }

    /** 同上，图标解码可替换（JVM 单测用） */
    public static String interpretMarkerOptions(Object o, MarkerOptionsSink sink,
                                                MarkerIconDecoder decoder) {
        if (null == o) {
            return null;
        }
        final Map<?, ?> data = ConvertUtil.toMap(o);
        final Object alpha = data.get("alpha");
        if (alpha != null) {
            sink.setAlpha(ConvertUtil.toFloat(alpha));
        }
        final Object anchor = data.get("anchor");
        if (anchor != null) {
            final List<?> anchorData = ConvertUtil.toList(anchor);
            sink.setAnchor(ConvertUtil.toFloat(anchorData.get(0)), ConvertUtil.toFloat(anchorData.get(1)));
        }
        final Object consumeTapEvents = data.get("consumeTapEvents");
        final Object draggable = data.get("draggable");
        if (draggable != null) {
            sink.setDraggable(ConvertUtil.toBoolean(draggable));
        }
        final Object flat = data.get("flat");
        if (flat != null) {
            sink.setFlat(ConvertUtil.toBoolean(flat));
        }
        final Object icon = data.get("icon");
        if (icon != null) {
            sink.setIcon(decoder.decode(icon));
        }

        final Object infoWindow = data.get("infoWindow");
        if (infoWindow != null) {
            interpretInfoWindowOptions(sink, (Map<String, Object>) infoWindow);
        }
        final Object position = data.get("position");
        if (position != null) {
            sink.setPosition(ConvertUtil.toLatLng(position));
        }
        final Object rotation = data.get("rotation");
        if (rotation != null) {
            sink.setRotation(Math.abs(360 - ConvertUtil.toFloat(rotation)));
        }
        final Object visible = data.get("visible");
        if (visible != null) {
            sink.setVisible(ConvertUtil.toBoolean(visible));
        }
        final Object zIndex = data.get("zIndex");
        if (zIndex != null) {
            sink.setZIndex(ConvertUtil.toFloat(zIndex));
        }

        final Object infoWindowEnable = data.get("infoWindowEnable");

        if (infoWindowEnable != null) {
            sink.setInfoWindowEnable(ConvertUtil.toBoolean(infoWindowEnable));
        }

        final Object clickable = data.get("clickable");
        if (null != clickable) {
            sink.setClickable(ConvertUtil.toBoolean(clickable));
        }

        final String markerId = (String) data.get("id");
        if (markerId == null) {
            throw new IllegalArgumentException("markerId was null");
        } else {
            return markerId;
        }
    }

    private static void interpretInfoWindowOptions(
            MarkerOptionsSink sink, Map<String, Object> infoWindow) {
        String title = (String) infoWindow.get("title");
        String snippet = (String) infoWindow.get("snippet");
        // snippet is nullable. 与 TextUtils.isEmpty 等价，便于 JVM 单测
        if (title != null && !title.isEmpty()) {
            sink.setTitle(title);
        }
        if (snippet != null && !snippet.isEmpty()) {
            sink.setSnippet(snippet);
        }
    }
}
