package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** 按 Dart markerToV2Map 的结构构造测试载荷 */
final class Payloads {
    private Payloads() {
    }

    /** icon 模式完整对象，全部键都存在（R-PROTO-2） */
    static Map<String, Object> icon(String id, String asset) {
        Map<String, Object> m = base(id);
        m.put("renderMode", "icon");
        m.put("icon", Arrays.asList("fromAsset", asset));
        m.put("nativePresentation", null);
        return m;
    }

    /** native 模式完整对象 */
    static Map<String, Object> nativeMarker(String id, String text) {
        Map<String, Object> content = new HashMap<>();
        content.put("text", text);
        // 最小合法样式：白色圆角矩形（S7 起原生会校验 NormSpec）
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "shape");
        bg.put("kind", "roundedRect");
        bg.put("fillColor", 0xFFFFFFFFL);
        Map<String, Object> style = new HashMap<>();
        style.put("background", bg);
        Map<String, Object> p = new HashMap<>();
        p.put("content", content);
        p.put("style", style);
        Map<String, Object> m = base(id);
        m.put("renderMode", "native");
        m.put("icon", null);
        m.put("nativePresentation", p);
        return m;
    }

    /** native 点位，指定纬度（只改位置的测试用） */
    static Map<String, Object> nativeAt(String id, String text, double lat) {
        Map<String, Object> m = nativeMarker(id, text);
        m.put("position", Arrays.asList(lat, 116.4));
        return m;
    }

    /** 可选中的 native 点位，带选中态样式（P2 预热测试用） */
    @SuppressWarnings("unchecked")
    static Map<String, Object> selectable(String id, String text) {
        Map<String, Object> m = nativeMarker(id, text);
        m.put("selectable", true);
        Map<String, Object> p = (Map<String, Object>) m.get("nativePresentation");
        Map<String, Object> sel = new HashMap<>((Map<String, Object>) p.get("style"));
        sel.put("textColor", 0xFFFF0000L);
        p.put("selectedStyle", sel);
        return m;
    }

    /** 背景为图片资源的 native 点位（固定尺寸，避免依赖解码尺寸） */
    @SuppressWarnings("unchecked")
    static Map<String, Object> withImage(String id, String text, String imageId) {
        Map<String, Object> m = nativeMarker(id, text);
        Map<String, Object> p = (Map<String, Object>) m.get("nativePresentation");
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "image");
        bg.put("imageId", imageId);
        bg.put("size", Arrays.asList(40.0, 20.0));
        ((Map<String, Object>) p.get("style")).put("background", bg);
        return m;
    }

    /** 九宫格背景点位：不设 size，宽高按圆角矩形规则计算；cap 为 [l,t,r,b] 逻辑像素 */
    @SuppressWarnings("unchecked")
    static Map<String, Object> ninePatch(String id, String text, String imageId, double... cap) {
        Map<String, Object> m = withImage(id, text, imageId);
        Map<String, Object> st = (Map<String, Object>) ((Map<String, Object>)
                m.get("nativePresentation")).get("style");
        Map<String, Object> bg = (Map<String, Object>) st.get("background");
        bg.remove("size");
        bg.put("capInsets", Arrays.asList(cap[0], cap[1], cap[2], cap[3]));
        st.put("padding", Arrays.asList(8.0, 4.0, 8.0, 4.0));
        return m;
    }

    /** imagesToAdd 的一项（asset，可重试） */
    static Map<String, Object> assetImage(String id) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("type", "asset");
        m.put("asset", "assets/" + id + ".png");
        m.put("pixelRatio", 2.0);
        return m;
    }

    /** imagesToAdd 的一项（bytes） */
    static Map<String, Object> bytesImage(String id) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("type", "bytes");
        m.put("data", new byte[]{1, 2, 3});
        m.put("pixelRatio", 2.0);
        return m;
    }

    static Map<String, Object> base(String id) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("position", Arrays.asList(39.9, 116.4));
        m.put("alpha", 1.0);
        m.put("anchor", Arrays.asList(0.5, 1.0));
        m.put("clickable", true);
        m.put("draggable", false);
        m.put("infoWindowEnable", true);
        m.put("infoWindow", new HashMap<String, Object>());
        m.put("rotation", 0.0);
        m.put("visible", true);
        m.put("zIndex", 0.0);
        m.put("selectable", false);
        m.put("selectedZIndex", null);
        return m;
    }

    @SafeVarargs
    static Map<String, Object> update(int syncId, List<Object> remove,
                                      Map<String, Object>... changes) {
        Map<String, Object> u = new HashMap<>();
        u.put("protocolVersion", 2);
        u.put("syncId", syncId);
        u.put("imagesToAdd", new ArrayList<>());
        u.put("imageIdsToRelease", new ArrayList<>());
        u.put("markersToAdd", new ArrayList<>());
        u.put("markersToChange", new ArrayList<Object>(Arrays.asList((Object[]) changes)));
        u.put("markerIdsToRemove", remove == null ? new ArrayList<>() : remove);
        return u;
    }

    @SafeVarargs
    static Map<String, Object> add(int syncId, Map<String, Object>... adds) {
        Map<String, Object> u = update(syncId, null);
        u.put("markersToAdd", new ArrayList<Object>(Arrays.asList((Object[]) adds)));
        return u;
    }
}
