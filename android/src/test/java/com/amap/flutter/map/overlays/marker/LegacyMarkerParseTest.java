package com.amap.flutter.map.overlays.marker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.LatLng;
import com.amap.flutter.map.overlays.marker.nativemarker.NativeMarkerManager;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** T-PROTO-3：不带 protocolVersion 的旧格式载荷，处理结果与 1.0.15 一致 */
public class LegacyMarkerParseTest {

    /** 按调用顺序记录 sink 收到的设置 */
    private static final class RecordingSink implements MarkerOptionsSink {
        final List<String> calls = new ArrayList<>();

        @Override public void setAlpha(float alpha) { calls.add("alpha=" + alpha); }
        @Override public void setAnchor(float u, float v) { calls.add("anchor=" + u + "," + v); }
        @Override public void setDraggable(boolean d) { calls.add("draggable=" + d); }
        @Override public void setFlat(boolean f) { calls.add("flat=" + f); }
        @Override public void setIcon(BitmapDescriptor b) { calls.add("icon"); }
        @Override public void setTitle(String t) { calls.add("title=" + t); }
        @Override public void setSnippet(String s) { calls.add("snippet=" + s); }
        @Override public void setPosition(LatLng p) { calls.add("position=" + p.latitude + "," + p.longitude); }
        @Override public void setRotation(float r) { calls.add("rotation=" + r); }
        @Override public void setVisible(boolean v) { calls.add("visible=" + v); }
        @Override public void setZIndex(float z) { calls.add("zIndex=" + z); }
        @Override public void setInfoWindowEnable(boolean e) { calls.add("infoWindowEnable=" + e); }
        @Override public void setClickable(boolean c) { calls.add("clickable=" + c); }
    }

    /** 记录收到的原始图标描述，返回 null 代替 SDK 对象 */
    private final List<Object> decoded = new ArrayList<>();
    private final MarkerIconDecoder decoder = raw -> {
        decoded.add(raw);
        return null;
    };

    /** 1.0.15 的 Marker.toMap：只输出非空字段 */
    private static Map<String, Object> legacyMarker() {
        Map<String, Object> info = new HashMap<>();
        info.put("title", "T");
        Map<String, Object> m = new HashMap<>();
        m.put("id", "m1");
        m.put("alpha", 0.5);
        m.put("anchor", Arrays.asList(0.5, 1.0));
        m.put("clickable", true);
        m.put("draggable", false);
        m.put("icon", Arrays.asList("defaultMarker"));
        m.put("infoWindowEnable", true);
        m.put("infoWindow", info);
        m.put("position", Arrays.asList(39.9, 116.4));
        m.put("rotation", 30.0);
        m.put("visible", true);
        m.put("zIndex", 2.0);
        return m;
    }

    @Test
    public void fullLegacyPayloadAppliesSameFieldsInSameOrder() {
        RecordingSink sink = new RecordingSink();
        String id = MarkerUtil.interpretMarkerOptions(legacyMarker(), sink, decoder);
        assertEquals("m1", id);
        // 1.0.15 的应用顺序与换算（rotation = |360 - r|，空 snippet 跳过）
        assertEquals(Arrays.asList(
                "alpha=0.5", "anchor=0.5,1.0", "draggable=false", "icon",
                "title=T", "position=39.9,116.4", "rotation=330.0",
                "visible=true", "zIndex=2.0", "infoWindowEnable=true",
                "clickable=true"), sink.calls);
        assertEquals(Arrays.asList("defaultMarker"), decoded.get(0));
    }

    // 旧语义：缺失字段不修改（与新协议的完整替换相反）
    @Test
    public void missingFieldsAreSkipped() {
        Map<String, Object> m = new HashMap<>();
        m.put("id", "m1");
        m.put("zIndex", 5.0);
        RecordingSink sink = new RecordingSink();
        MarkerUtil.interpretMarkerOptions(m, sink, decoder);
        assertEquals(Arrays.asList("zIndex=5.0"), sink.calls);
        assertEquals(0, decoded.size());
    }

    @Test(expected = IllegalArgumentException.class)
    public void missingIdThrowsAsBefore() {
        Map<String, Object> m = legacyMarker();
        m.remove("id");
        MarkerUtil.interpretMarkerOptions(m, new RecordingSink(), decoder);
    }

    // 旧格式载荷不会被分流到新协议
    @Test
    public void legacyUpdateIsNotRoutedToV2() {
        Map<String, Object> u = new HashMap<>();
        u.put("markersToAdd", Arrays.asList(legacyMarker()));
        u.put("markersToChange", new ArrayList<>());
        u.put("markerIdsToRemove", new ArrayList<>());
        assertFalse(NativeMarkerManager.isV2Payload(u));
    }
}
