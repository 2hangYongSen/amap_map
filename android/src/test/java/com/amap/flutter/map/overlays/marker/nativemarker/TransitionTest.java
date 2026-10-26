package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

/** T-DEL-1～6：显式删除与 replaceWhenReady 集合替换（§12） */
public class TransitionTest {
    private final RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    /** 同一次 update：删除 removes，新增 adds */
    @SafeVarargs
    private final void replace(List<Object> removes, Map<String, Object>... adds) {
        Map<String, Object> u = Payloads.add(900 + h.emitted.size(), adds);
        u.put("markerIdsToRemove", removes);
        h.manager.update(u);
    }

    private List<Map<String, Object>> removed() {
        return h.events("markers#removed");
    }

    // T-DEL-1：immediate 下删除在本次调用内完成，remove() 次数等于删除数
    @Test
    public void tDel1_immediateRemovesInCall() {
        h.manager.attach();
        h.add(Payloads.nativeMarker("A", "a"), Payloads.nativeMarker("B", "b"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A", "B"), Payloads.nativeMarker("C", "c"));
        assertEquals(2, h.host.count("remove:"));
        assertFalse(h.host.hasMarker("A"));
        assertTrue("immediate 不发 removed", removed().isEmpty());
        h.loop.drain();
    }

    // replaceWhenReady 下没有新增的显式删除仍立即执行（R-DEL-1），并发 removed
    @Test
    public void explicitRemoveIsImmediateUnderReplace() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        h.remove("A");
        assertFalse(h.host.hasMarker("A"));
        assertEquals(Arrays.asList("A"), removed().get(0).get("markerIds"));
    }

    // T-DEL-2：新增全部应用前旧点仍在；全部应用后旧点在同一帧删除，removed 带 syncId
    @Test
    public void tDel2_oldKeptUntilAllApplied() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"), Payloads.nativeMarker("B", "b"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A", "B"), Payloads.nativeMarker("C", "c"),
                Payloads.nativeMarker("D", "d"));
        h.loop.drainNoFrame();
        assertTrue(h.host.hasMarker("A") && h.host.hasMarker("B"));
        h.loop.frame();
        assertTrue(h.host.hasMarker("C") && h.host.hasMarker("D"));
        assertFalse("同一帧删除", h.host.hasMarker("A") || h.host.hasMarker("B"));
        Map<String, Object> ev = removed().get(0);
        assertEquals(Arrays.asList("A", "B"), ev.get("markerIds"));
        assertEquals(2, ((List<?>) ev.get("removeSyncIds")).size());
    }

    // T-DEL-3：延迟期间同一 id 重新加入，最终存在，不发 removed
    @Test
    public void tDel3_reAddDuringDelayKeepsMarker() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A"), Payloads.nativeMarker("C", "c"));
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        h.loop.fireDelayed();
        assertTrue(h.host.hasMarker("A"));
        assertTrue(removed().isEmpty());
    }

    // T-DEL-4：连续 3 次更新不重新计时，第一次的 timeout 到期即删除
    @Test
    public void tDel4_timeoutNotRestarted() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A"), Payloads.nativeMarker("C", "c"));
        h.add(Payloads.nativeMarker("D", "d"));
        h.add(Payloads.nativeMarker("E", "e"));
        assertEquals("只有一个计时", 1, h.loop.delayed.size());
        h.loop.fireDelayed(); // 绘制尚未执行，超时
        assertFalse(h.host.hasMarker("A"));
        assertEquals(1, removed().size());
        h.loop.drain();
    }

    // T-DEL-5：延迟期间点击待删除点：onTap 照常，selectable 点同时产生选择事件
    @Test
    public void tDel5_retiringMarkerStillTappable() {
        h.enableReplace(1000);
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"), Payloads.nativeMarker("D", "d"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A", "D"), Payloads.nativeMarker("C", "c"));
        h.manager.onMarkerTap("A");
        h.manager.onMarkerTap("D");
        assertEquals(2, h.events("marker#onTap").size());
        assertEquals(1, h.events("marker#selectionChanged").size());
        assertEquals("A", h.manager.selection().selectedId());
        h.loop.drain();
        assertFalse(h.host.hasMarker("A"));
    }

    // T-DEL-6：新增中 1 个绘制失败，删除仍执行，并发 renderFailed
    @Test
    public void tDel6_failedAddDoesNotBlock() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A"), Payloads.nativeMarker("X", "bad"),
                Payloads.nativeMarker("C", "c"));
        h.painter.failing.add(h.point("X").normalKey()); // 任务尚未执行
        h.loop.drain();
        assertFalse(h.host.hasMarker("A"));
        assertTrue(h.host.hasMarker("C"));
        assertEquals(1, removed().size());
        boolean reported = false;
        for (Map<String, Object> e : h.events("marker#nativeError")) {
            reported |= "renderFailed".equals(e.get("code")) && "X".equals(e.get("markerId"));
        }
        assertTrue(reported);
    }

    // 切回 immediate 时待删除立即执行
    @Test
    public void switchToImmediateFlushes() {
        h.enableReplace(1000);
        h.add(Payloads.nativeMarker("A", "a"));
        h.loop.drain();
        replace(Arrays.<Object>asList("A"), Payloads.nativeMarker("C", "c"));
        Map<String, Object> t = new java.util.HashMap<>();
        t.put("mode", "immediate");
        Map<String, Object> o = new java.util.HashMap<>();
        o.put("markerTransition", t);
        h.manager.applyOptions(o);
        assertFalse(h.host.hasMarker("A"));
        assertTrue(h.loop.delayed.isEmpty());
        h.loop.drain();
    }
}
