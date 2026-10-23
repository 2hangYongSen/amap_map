package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public class NativeMarkerManagerTest {
    private FakeMarkerHost host;
    private final List<Map<String, Object>> emitted = new ArrayList<>();
    private NativeMarkerManager manager;

    @Before
    public void setUp() {
        host = new FakeMarkerHost();
        emitted.clear();
        manager = new NativeMarkerManager(host, (method, args) -> emitted.add(args));
    }

    // T-PROTO-2：同一点位依次 native(A)、icon(X)，原生状态清除，最终显示 icon X
    @Test
    public void tProto2_nativeThenIconClearsNativeState() {
        manager.update(Payloads.add(1, Payloads.nativeMarker("p", "A")));
        assertEquals(1, manager.points().size());
        assertEquals(FakeMarkerHost.DEFAULT_ICON, host.markers.get("p").icon);

        Map<String, Object> r = manager.update(Payloads.update(2, null, Payloads.icon("p", "X")));
        assertEquals(true, r.get("accepted"));
        assertNull("PointTable 不应残留 presentation", manager.points().get("p"));
        assertEquals("icon:X", host.markers.get("p").icon);
        assertFalse(host.markers.get("p").options.isNative());
        // S9 起此处还要断言调度器中没有该点的任务
    }

    // R-PROTO-4：icon→native 绘制完成前保留旧图标
    @Test
    public void iconToNativeKeepsOldIcon() {
        manager.update(Payloads.add(1, Payloads.icon("p", "X")));
        manager.update(Payloads.update(2, null, Payloads.nativeMarker("p", "A")));
        assertEquals("icon:X", host.markers.get("p").icon);
        assertEquals(1, manager.points().get("p").generation);
    }

    // R-PROTO-2/3：显式 null 也要应用，恢复默认值，不沿用旧值
    @Test
    public void fullReplaceRestoresDefaults() {
        Map<String, Object> first = Payloads.icon("p", "X");
        first.put("alpha", 0.3);
        first.put("zIndex", 9.0);
        first.put("visible", false);
        manager.update(Payloads.add(1, first));
        assertEquals(0.3f, host.markers.get("p").options.alpha, 1e-6);

        Map<String, Object> second = Payloads.icon("p", "X");
        second.put("alpha", null);
        second.put("zIndex", null);
        second.remove("visible"); // 缺失与 null 同义
        manager.update(Payloads.update(2, null, second));
        FullMarkerOptions o = host.markers.get("p").options;
        assertEquals(1f, o.alpha, 1e-6);
        assertEquals(0f, o.zIndex, 1e-6);
        assertTrue(o.visible);
    }

    // R-NAT-REJ-1 最小版：非法点只拒绝自己，被拒绝的修改不改变原生状态
    @Test
    public void rejectsInvalidMarkersIndividually() {
        manager.update(Payloads.add(1, Payloads.icon("c", "C0")));
        Map<String, Object> badAdd = Payloads.icon("b", "X");
        badAdd.remove("renderMode"); // R-PROTO-1：缺 renderMode 必须拒绝
        Map<String, Object> badChange = Payloads.icon("c", "bad"); // 图标解码失败
        Map<String, Object> u = Payloads.add(2, Payloads.icon("a", "A"), badAdd);
        u.put("markersToChange", Collections.singletonList(badChange));

        Map<String, Object> r = manager.update(u);
        assertEquals(true, r.get("accepted"));
        assertEquals(Arrays.asList("b", "c"), r.get("rejectedMarkerIds"));
        assertTrue(host.hasMarker("a"));
        assertFalse(host.hasMarker("b"));
        assertEquals("icon:C0", host.markers.get("c").icon);
    }

    // 结构错误：整体不修改，accepted=false（§6.5）
    @Test
    public void malformedPayloadIsRejectedWhole() {
        Map<String, Object> u = Payloads.add(3, Payloads.icon("a", "A"));
        u.put("markerIdsToRemove", "not-a-list");
        Map<String, Object> r = manager.update(u);
        assertEquals(false, r.get("accepted"));
        assertEquals(3, r.get("syncId"));
        assertTrue(host.markers.isEmpty());
    }

    // R-INIT-2/5：握手前错误只缓冲，attach 返回历史错误后再实时发送
    @Test
    public void errorsBufferedUntilAttach() {
        Map<String, Object> bad = Payloads.nativeMarker("n", "t");
        bad.put("nativePresentation", null);
        Map<String, Object> params = Payloads.add(0, bad);
        manager.applyCreation(params);
        assertTrue("握手前不得发送事件", emitted.isEmpty());

        Map<String, Object> snap = manager.attach();
        assertEquals(Collections.singletonList("n"), snap.get("rejectedMarkerIds"));
        assertEquals(1, snap.get("lastEventSeq"));
        assertEquals(1, ((List<?>) snap.get("errors")).size());
        assertEquals(0, snap.get("syncId"));

        manager.update(Payloads.add(1, bad));
        assertEquals(1, emitted.size());
        assertEquals("invalidConfig", emitted.get(0).get("code"));
        assertEquals(2, emitted.get(0).get("eventSeq"));
    }

    // S7：NormSpec 校验失败（规范化后字号为 0）按 R-NAT-REJ-1 同步拒绝，同批其他点不受影响
    @Test
    @SuppressWarnings("unchecked")
    public void invalidNormSpecRejectedPerMarker() {
        manager.attach();
        Map<String, Object> bad = Payloads.nativeMarker("bad", "t");
        Map<String, Object> p = (Map<String, Object>) bad.get("nativePresentation");
        ((Map<String, Object>) p.get("style")).put("fontSize", 0.001);
        Map<String, Object> r = manager.update(Payloads.add(1, Payloads.nativeMarker("ok", "t"), bad));
        assertEquals(Collections.singletonList("bad"), r.get("rejectedMarkerIds"));
        assertNull(manager.points().get("bad"));
        assertTrue(manager.points().get("ok").desired.spec != null);
    }

    // R-INIT-3：attach 幂等，不重复创建点位；syncId 为最近接受的请求
    @Test
    public void attachIsIdempotent() {
        manager.attach();
        manager.update(Payloads.add(7, Payloads.nativeMarker("n", "t")));
        Map<String, Object> again = manager.attach();
        assertEquals(7, again.get("syncId"));
        assertEquals(Collections.emptyList(), again.get("rejectedMarkerIds"));
        assertEquals(Collections.singletonList("add:n"), host.calls);
    }

    // R-PROTO-1a：旧协议登记的点在新协议下可被整体替换
    @Test
    public void legacyMarkerReplacedByV2() {
        host.addLegacy("old", "icon:L");
        manager.attach();
        manager.update(Payloads.update(1, null, Payloads.nativeMarker("old", "t")));
        assertEquals("icon:L", host.markers.get("old").icon);
        assertEquals(Collections.singletonList("update:old"), host.calls);
    }

    // R-RES-9：resync 以快照为准，多余点位删除
    @Test
    public void resyncRemovesExtraMarkers() {
        manager.update(Payloads.add(1, Payloads.icon("a", "A"), Payloads.nativeMarker("b", "t")));
        Map<String, Object> snap = Payloads.update(2, null);
        snap.put("markers", Collections.singletonList(Payloads.icon("a", "A2")));
        Map<String, Object> r = manager.resync(snap);
        assertEquals(true, r.get("accepted"));
        assertFalse(host.hasMarker("b"));
        assertNull(manager.points().get("b"));
        assertEquals("icon:A2", host.markers.get("a").icon);
    }

    // §8.6 第一阶段：移除全部 Marker，之后不发事件、不修改地图
    @Test
    public void disposeRemovesEverythingAndStopsEvents() {
        manager.attach();
        manager.update(Payloads.add(1, Payloads.icon("a", "A"), Payloads.nativeMarker("b", "t")));
        manager.dispose();
        manager.dispose(); // 幂等
        assertTrue(host.markers.isEmpty());
        assertEquals(0, manager.points().size());

        Map<String, Object> bad = Payloads.icon("c", "bad");
        Map<String, Object> r = manager.update(Payloads.add(2, bad));
        assertEquals(false, r.get("accepted"));
        assertTrue(emitted.isEmpty());
        assertTrue(host.markers.isEmpty());
    }

    @Test
    public void detectsProtocolVersion() {
        assertTrue(NativeMarkerManager.isV2Payload(Payloads.update(1, null)));
        Map<String, Object> legacy = Payloads.update(1, null);
        legacy.remove("protocolVersion");
        assertFalse(NativeMarkerManager.isV2Payload(legacy));
        assertFalse(NativeMarkerManager.isV2Payload(null));
    }
}
