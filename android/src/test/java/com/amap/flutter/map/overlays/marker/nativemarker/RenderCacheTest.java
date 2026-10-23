package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** T-CACHE-1～5：合成位图缓存引用与预算（§8.5、R-PRI-3） */
public class RenderCacheTest {
    private RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object>[] markers(String prefix, int n, String text) {
        List<Map<String, Object>> l = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            l.add(Payloads.nativeMarker(prefix + i, text));
        }
        return l.toArray(new Map[0]);
    }

    // T-CACHE-1：20 个点共享 K，逐个切走，只有最后一个切走后 K 才可淘汰
    @Test
    public void tCache1_sharedEntryEvictableOnlyAfterLast() {
        h.add(markers("p", 20, "3000"));
        h.loop.drain();
        String k = h.point("p0").normalKey();
        RenderCache.Entry e = h.r().cache.get(k);
        assertEquals(20, e.displayRefs());
        for (int i = 0; i < 20; i++) {
            h.change(Payloads.nativeMarker("p" + i, "31" + i));
            h.loop.drain();
            assertEquals("第 " + i + " 个切走后", i == 19, e.evictable());
            assertEquals(19 - i, e.displayRefs());
        }
    }

    // T-CACHE-2：应用项等待期间（pendingRefs=1）强制淘汰，条目不被淘汰
    @Test
    public void tCache2_pendingEntryNotEvicted() {
        h.add(Payloads.nativeMarker("A", "t"));
        h.loop.drainNoFrame();
        String k = h.point("A").normalKey();
        assertEquals(1, h.r().cache.get(k).pendingRefs());
        h.r().cache.evictAllEvictable();
        assertTrue(h.r().cache.contains(k));
        h.loop.drain();
        assertEquals(h.r().cache.get(k).descriptor, h.iconOf("A"));
    }

    private int queuedP2() {
        int n = 0;
        for (RenderTask t : h.r().scheduler.queued()) {
            if (t.priority == RenderTask.P2) {
                n++;
            }
        }
        return n;
    }

    // T-CACHE-3：P0/P1 排队或缓存 ≥90% 时 P2 不入队，已排队的 P2 被撤回，P1 不受影响
    @Test
    @SuppressWarnings("unchecked")
    public void tCache3_prewarmStopsNearBudget() {
        h = new RenderHarness(1, 100_000); // 每条 10_000，10 条即满
        h.add(Payloads.selectable("S0", "a"), Payloads.selectable("S1", "b"));
        assertEquals("普通态排队时不预热", 0, queuedP2());
        for (int i = 0; i < 20 && queuedP2() == 0; i++) {
            h.loop.runMain();
            h.loop.runBg();
        }
        // 单线程：一个 P2 已开始执行，另一个仍在排队
        assertEquals(1, queuedP2());
        Map<String, Object>[] plain = new Map[7];
        for (int i = 0; i < 7; i++) {
            plain[i] = Payloads.nativeMarker("p" + i, "plain" + i);
        }
        h.add(plain);
        assertEquals("P1 入队后排队中的 P2 被撤回", 0, queuedP2());
        h.loop.drain();
        assertTrue(h.r().cache.nearBudget());
        assertEquals(0, queuedP2());
        int prewarmed = 0;
        for (String key : h.painter.painted) {
            if (key.equals(h.point("S0").selectedKey()) || key.equals(h.point("S1").selectedKey())) {
                prewarmed++;
            }
        }
        assertEquals("只有撤回前已在执行的 P2 完成", 1, prewarmed);
        for (int i = 0; i < 7; i++) {
            assertTrue("P1 不受影响", h.host.hasMarker("p" + i));
        }
    }

    // 预算充足时 P2 预热在普通态完成后执行，结果只进缓存，不改变显示（R-PRI-1）
    @Test
    public void prewarmRunsAfterNormal() {
        h.add(Payloads.selectable("S", "a"));
        h.loop.drain();
        PointTable.Entry s = h.point("S");
        assertTrue(h.r().cache.contains(s.selectedKey()));
        assertEquals(s.normalKey(), s.shown().key);
        assertEquals(0, h.r().cache.get(s.selectedKey()).displayRefs());
        assertEquals(2, h.painter.count());
    }

    // T-CACHE-4：销毁前三类引用与实际一致，销毁完成后全部归零、表为空
    @Test
    public void tCache4_refsMatchRealityThenZero() {
        h.add(Payloads.nativeMarker("shown", "s"));
        h.loop.drain();
        h.add(Payloads.nativeMarker("pending", "p"));
        h.loop.drainNoFrame(); // 结果停在应用队列
        h.add(Payloads.nativeMarker("running", "r"));
        h.loop.runMain(); // 任务进入 running
        RenderInvariants.check(h);
        assertEquals(1, h.r().cache.get(h.point("pending").normalKey()).pendingRefs());
        assertEquals(1, h.r().cache.get(h.point("shown").normalKey()).displayRefs());
        h.manager.dispose();
        assertFalse("仍有 running 任务，尚未终止", h.manager.isTerminated());
        int adds = h.host.count("add:");
        h.loop.drain();
        assertEquals("销毁后不得 addMarker", adds, h.host.count("add:"));
        assertEquals(1, h.icons.discarded.size());
        RenderInvariants.checkTerminated(h);
    }

    // T-CACHE-5：淘汰时回收 SDK 副本 1 次、不调 descriptor.recycle()、预算减去；有引用的不回收
    @Test
    public void tCache5_evictionRecyclesCopyOnce() {
        h = new RenderHarness(1, 30_000);
        h.add(Payloads.nativeMarker("A", "a"), Payloads.nativeMarker("B", "b"),
                Payloads.nativeMarker("C", "c"));
        h.loop.drain();
        String ka = h.point("A").normalKey();
        FakeRender.Descriptor da = (FakeRender.Descriptor) h.r().cache.get(ka).descriptor;
        h.change(Payloads.nativeMarker("A", "a2"));
        h.loop.drain();
        assertFalse(h.r().cache.contains(ka));
        assertEquals(1, da.copyRecycles);
        assertFalse(da.descriptorRecycleCalled);
        assertEquals(30_000, h.r().cache.bytes());
        for (RenderCache.Entry e : h.r().cache.entries()) {
            assertEquals(0, ((FakeRender.Descriptor) e.descriptor).copyRecycles);
        }
        assertNull(h.r().cache.get(ka));
    }
}
