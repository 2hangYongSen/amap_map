package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** T-TIME-1/3/4/5（§13）：回执、标记方块、tapId 关联；时钟用可控替身 */
public class DiagnosticsTest {
    private final RenderHarness h = new RenderHarness();
    private final FakeSquare square = new FakeSquare();

    /** 标记方块替身：记录颜色与提交时刻；提交本身耗时 0.25ms（推进假时钟） */
    private final class FakeSquare implements Diagnostics.Square {
        final List<Integer> colors = new ArrayList<>();
        final List<Double> shownAtMs = new ArrayList<>();
        int hides = 0;

        @Override
        public void show(int argb) {
            h.loop.now += 250_000;
            colors.add(argb);
            shownAtMs.add(h.loop.now / 1_000_000.0);
        }

        @Override
        public void hide() {
            hides++;
        }
    }

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    private void enable(boolean on) {
        Map<String, Object> o = new HashMap<>();
        o.put("markerDiagnostics", on);
        h.manager.applyOptions(o);
    }

    private void start(boolean diagnostics) {
        h.manager.setDiagnosticsSquare(square);
        h.enableSelection(); // 含 attach：事件开关打开
        enable(diagnostics);
    }

    private List<Map<String, Object>> receipts() {
        return h.events("markers#applied");
    }

    private static double d(Object o) {
        return ((Number) o).doubleValue();
    }

    // T-TIME-1：字段齐全；同一时钟 t3≥t2、t4≥t2；异步路径 t4 在帧应用之后
    @Test
    public void tTime1_receiptFieldsAndClockOrder() {
        start(true);
        h.loop.now = 5_000_000;
        h.add(Payloads.nativeMarker("A", "a"), Payloads.nativeMarker("B", "b"));
        assertTrue("应用前不发回执", receipts().isEmpty());
        h.loop.drainNoFrame();
        h.loop.now += 3_000_000; // 下一帧在 3ms 后
        h.loop.drain();
        assertEquals(1, receipts().size());
        Map<String, Object> r = receipts().get(0);
        for (String k : new String[]{"syncId", "nativeT2Ms", "nativeT2vMs", "markerColor",
                "nativeT4Ms", "t2ToT3Ms", "t2ToT4Ms", "appliedCount", "drawCount", "cacheHits",
                "cacheMisses", "bytesReceived", "pendingTasks", "memory", "eventSeq"}) {
            assertTrue("缺少 " + k, r.containsKey(k));
        }
        assertEquals(1, r.get("syncId"));
        assertEquals(2, r.get("appliedCount"));
        assertEquals(2L, r.get("drawCount"));
        assertEquals(5.0, d(r.get("nativeT2Ms")), 1e-9);
        assertTrue(d(r.get("t2ToT3Ms")) >= 0);
        assertTrue("异步路径 t4 在帧应用之后", d(r.get("t2ToT4Ms")) >= 3.0);
        assertEquals(d(r.get("nativeT4Ms")) - d(r.get("nativeT2Ms")), d(r.get("t2ToT4Ms")), 1e-9);
        Map<?, ?> mem = (Map<?, ?>) r.get("memory");
        assertEquals(2 * h.icons.bytesPer, ((Number) mem.get("compositeBytes")).longValue());
        assertEquals(false, mem.get("compositeOverBudget"));
    }

    // T-TIME-1：同步完成（icon 点、缓存命中前无可应用项）时 t4 ≤ t3，回执在返回前已发出
    @Test
    public void tTime1_syncPathAllowsT4BeforeT3() {
        start(true);
        Map<String, Object> icon = Payloads.icon("I", "pin");
        h.add(icon);
        assertEquals(1, receipts().size());
        Map<String, Object> r = receipts().get(0);
        assertTrue(d(r.get("t2ToT4Ms")) <= d(r.get("t2ToT3Ms")));
        assertEquals(0L, r.get("drawCount"));
    }

    // 缓存命中：第二个同内容的点不绘制，cacheHits 计 1；bytes 资源计入 bytesReceived
    @Test
    public void cacheHitsAndBytes() {
        start(true);
        h.add(Payloads.nativeMarker("A", "same"));
        h.loop.drain();
        Map<String, Object> u = Payloads.add(9, Payloads.nativeMarker("B", "same"));
        u.put("imagesToAdd", new ArrayList<Object>(java.util.Collections.singletonList(
                Payloads.bytesImage("img"))));
        h.manager.update(u);
        h.loop.drain();
        Map<String, Object> r = receipts().get(1);
        assertEquals(0L, r.get("drawCount"));
        assertEquals(1L, r.get("cacheHits"));
        assertEquals(3L, r.get("bytesReceived"));
        h.change(); // 空修改：appliedCount 0，立即回执
        assertEquals(0, receipts().get(2).get("appliedCount"));
    }

    // T-TIME-3：关闭时不发回执、不显示方块、点击不带 tapId、ping 与清缓存不可用
    @Test
    public void tTime3_disabledEmitsNothing() {
        start(false);
        h.add(Payloads.selectable("A", "a"), Payloads.icon("I", "pin"));
        h.loop.drain();
        h.manager.onMarkerTap("A");
        h.loop.drain();
        assertTrue(receipts().isEmpty());
        assertTrue(h.events("markers#tapApplied").isEmpty());
        assertTrue(square.colors.isEmpty());
        assertFalse(h.events("marker#onTap").get(0).containsKey("tapId"));
        assertFalse(h.events("marker#selectionChanged").get(0).containsKey("tapId"));
        assertNull(h.manager.diagPing());
        assertFalse(h.manager.diagClearCaches());
        // 开启后再关闭：方块隐藏，未完成的记录丢弃，之后不再发送
        enable(true);
        h.add(Payloads.nativeMarker("B", "b"));
        enable(false);
        assertEquals(1, square.hides);
        h.loop.drain();
        assertTrue(receipts().isEmpty());
    }

    // T-TIME-4：方块颜色提交与 t2 属于同一次处理，回执记录真实 t2v；颜色按 syncId 轮换
    @Test
    public void tTime4_markerSquareSameCallAsT2() {
        start(true);
        h.loop.now = 10_000_000;
        h.add(Payloads.icon("I", "pin")); // syncId 1
        h.add(Payloads.icon("J", "pin")); // syncId 2
        assertEquals(2, square.colors.size());
        Map<String, Object> r = receipts().get(0);
        assertEquals(10.0, d(r.get("nativeT2Ms")), 1e-9);
        // 替身提交耗时 0.25ms：t2v 是提交返回的真实时刻，不预设为 t2
        assertEquals(square.shownAtMs.get(0), d(r.get("nativeT2vMs")), 1e-9);
        assertEquals(10.25, d(r.get("nativeT2vMs")), 1e-9);
        assertEquals((long) (Diagnostics.PALETTE[1] & 0xFFFFFFFFL), r.get("markerColor"));
        assertEquals(Diagnostics.PALETTE[2], (int) square.colors.get(1));
        assertTrue("t2v 早于返回 t3", d(r.get("nativeT2vMs")) - d(r.get("nativeT2Ms"))
                <= d(r.get("t2ToT3Ms")));
    }

    // 没有标记方块（平台层不可用）时 t2v 为空，回执照发
    @Test
    public void noSquareLeavesT2vNull() {
        h.enableSelection();
        enable(true);
        h.add(Payloads.icon("I", "pin"));
        assertNull(receipts().get(0).get("nativeT2vMs"));
        assertNull(receipts().get(0).get("markerColor"));
    }

    private List<Map<String, Object>> taps() {
        return h.events("markers#tapApplied");
    }

    /** 旧路径：Dart 收到 onTap 后重发图标，把 tapId 带回 markers#update */
    private Map<String, Object> resendIcon(int syncId, String id, String asset, Object tapId) {
        Map<String, Object> u = Payloads.update(syncId, null, Payloads.icon(id, asset));
        Map<String, Object> tap = new HashMap<>();
        tap.put("tapId", tapId);
        tap.put("markerId", id);
        u.put("diagTapId", tap);
        return u;
    }

    // T-TIME-5（旧路径）：onTap 带 tapId → 更新带回 → setIcon 返回后记 c2，c2 ≥ c1
    @Test
    public void tTime5_legacyIconPathTapId() {
        start(true);
        h.add(Payloads.icon("I", "normal"));
        h.loop.now = 100_000_000;
        h.manager.onMarkerTap("I");
        Object tapId = h.events("marker#onTap").get(0).get("tapId");
        assertNotNull(tapId);
        assertTrue("新路径才会自动记 c2", taps().isEmpty());
        h.loop.now = 160_000_000; // Dart 重新生成 PNG 用了 60ms
        h.manager.update(resendIcon(7, "I", "selected", tapId));
        assertEquals("icon:selected", h.iconOf("I"));
        assertEquals(1, taps().size());
        Map<String, Object> t = taps().get(0);
        assertEquals(tapId, t.get("tapId"));
        assertEquals("I", t.get("markerId"));
        assertEquals("icon", t.get("path"));
        assertEquals(100.0, d(t.get("c1Ms")), 1e-9);
        assertTrue(d(t.get("c2Ms")) >= 160.0);
        // 同一 tapId 不重复记录；markerId 不符的 diagTapId 被忽略
        h.manager.update(resendIcon(8, "I", "normal", tapId));
        h.manager.onMarkerTap("I");
        Object second = h.events("marker#onTap").get(1).get("tapId");
        h.manager.update(resendIcon(9, "J", "x", second));
        assertEquals(1, taps().size());
    }

    // T-TIME-5（新路径）：选中态由原生提交，c2 在外观提交到 SDK 时记录，不经过 Dart
    @Test
    public void tTime5_nativePathTapId() {
        start(true);
        h.add(Payloads.selectableZ("A", "a", 1, 99));
        h.loop.drain(); // 普通态显示、选中态预热完成
        h.loop.now = 200_000_000;
        h.manager.onMarkerTap("A");
        Map<String, Object> sel = h.events("marker#selectionChanged").get(0);
        Object tapId = h.events("marker#onTap").get(0).get("tapId");
        assertEquals("selectionChanged 带同一 tapId（R-TIME-2）", tapId, sel.get("tapId"));
        assertTrue("选中外观在下一帧才提交", taps().isEmpty());
        h.loop.now = 216_000_000;
        h.loop.drain();
        assertEquals(h.r().cache.get(h.point("A").selectedKey()).descriptor, h.iconOf("A"));
        Map<String, Object> t = taps().get(0);
        assertEquals(tapId, t.get("tapId"));
        assertEquals("native", t.get("path"));
        assertEquals(200.0, d(t.get("c1Ms")), 1e-9);
        assertEquals(216.0, d(t.get("c2Ms")), 1e-9);
        // 再点一次（retap 取消）：恢复普通态后记第二条
        h.manager.onMarkerTap("A");
        h.loop.drain();
        assertEquals(2, taps().size());
        assertTrue(d(taps().get(1).get("c2Ms")) >= d(taps().get(1).get("c1Ms")));
    }

    // 点击非 selectable 的 native 点：外观本就一致，c2 不会被记录为“等外观”（只走旧路径）
    @Test
    public void nonSelectableTapWaitsForDart() {
        start(true);
        h.add(Payloads.nativeMarker("D", "district"));
        h.loop.drain();
        h.manager.onMarkerTap("D");
        h.loop.drain();
        assertTrue(taps().isEmpty());
        assertNotNull(h.events("marker#onTap").get(0).get("tapId"));
    }

    // diag#ping 与 FrameClock 同一时钟、同一单位
    @Test
    public void pingUsesSameClock() {
        start(true);
        h.loop.now = 42_000_000;
        assertEquals(42.0, d(h.manager.diagPing().get("nativeMs")), 1e-9);
        assertTrue(h.manager.diagClearCaches());
    }
}
