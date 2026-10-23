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
        Map<String, Object> p = new HashMap<>();
        p.put("content", content);
        Map<String, Object> m = base(id);
        m.put("renderMode", "native");
        m.put("icon", null);
        m.put("nativePresentation", p);
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
