package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** T-GEN-1～9：共享任务与点位代次的衔接（§8.2） */
public class RenderGenerationTest {
    private final RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    private RenderTask onlyTask() {
        assertEquals("任务数", 1, h.r().scheduler.tasks().size());
        return h.r().scheduler.tasks().iterator().next();
    }

    // T-GEN-1：延迟删除到期前同 ID 重新加入，删除因代次不匹配被丢弃
    @Test
    public void tGen1_staleRemovalIgnoredAfterReAdd() {
        h.add(Payloads.nativeMarker("h:1", "3000"));
        h.loop.drain();
        int g = h.r().beginRemoval("h:1");
        h.add(Payloads.nativeMarker("h:1", "3000"));
        assertFalse("旧删除应作废", h.r().finishRemoval("h:1", g));
        h.loop.drain();
        assertTrue(h.host.hasMarker("h:1"));
        assertEquals(0, h.host.count("remove:"));
        assertEquals(1, h.painter.count());
    }

    // T-GEN-2：已显示的点在其他任务执行期间改位置，走 setPosition，不增加绘制
    @Test
    public void tGen2_shownMarkerMoveUsesSetPosition() {
        h.add(Payloads.nativeMarker("a", "A"));
        h.loop.drain();
        h.add(Payloads.nativeMarker("b", "B"));
        h.loop.runMain(); // b 的任务进入 running
        h.change(Payloads.nativeAt("a", "A", 30.0));
        assertEquals(1, h.host.count("props:a"));
        assertEquals(30.0, h.lat("a"), 0);
        h.loop.drain();
        assertEquals(2, h.painter.count());
        assertEquals(0, h.host.count("setIcon:a"));
    }

    // T-GEN-3：共享任务的一个点在执行中改 key，另一个点照常拿到结果
    @Test
    public void tGen3_sharedTaskSurvivesOneWaiterLeaving() {
        h.add(Payloads.nativeMarker("h:3", "K"), Payloads.nativeMarker("h:4", "K"));
        h.loop.runMain();
        RenderTask k = onlyTask();
        assertEquals(RenderTask.State.RUNNING, k.state);
        h.change(Payloads.nativeMarker("h:3", "K2"));
        assertEquals("任务不能被取消", RenderTask.State.RUNNING, k.state);
        assertEquals(1, k.waiters.size());
        assertEquals("h:4", k.waiters.get(0).markerId);
        h.loop.drain();
        assertEquals(h.point("h:4").normalKey(), h.point("h:4").shown().key);
        assertEquals(h.point("h:3").normalKey(), h.point("h:3").shown().key);
        assertEquals(2, h.painter.count());
    }

    // T-GEN-4：100 个点只改位置，绘制 0 次，setPosition 100 次
    @Test
    public void tGen4_moveOnlyDoesNotRepaint() {
        List<Map<String, Object>> adds = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            adds.add(Payloads.nativeMarker("p" + i, "T" + (i % 7)));
        }
        h.add(adds.toArray(new Map[0]));
        h.loop.drain();
        int painted = h.painter.count();
        List<Map<String, Object>> moves = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            moves.add(Payloads.nativeAt("p" + i, "T" + (i % 7), 20.0));
        }
        h.change(moves.toArray(new Map[0]));
        h.loop.drain();
        assertEquals(painted, h.painter.count());
        assertEquals(100, h.host.count("props:"));
        assertEquals(20.0, h.lat("p42"), 0);
    }

    // T-GEN-5：同 key 的 50 个点同时新增，只绘制 1 次，waiters 为 50
    @Test
    public void tGen5_sameKeyPaintedOnce() {
        List<Map<String, Object>> adds = new ArrayList<>();
        for (int i = 0; i < 50; i++) {
            adds.add(Payloads.nativeMarker("s" + i, "same"));
        }
        h.add(adds.toArray(new Map[0]));
        assertEquals(50, onlyTask().waiters.size());
        h.loop.drain();
        assertEquals(1, h.painter.count());
        assertEquals(50, h.host.count("add:"));
    }

    // T-GEN-6：任务 queued 时只改位置，不取消、waiter 换成新代次、以新位置 addMarker
    @Test
    public void tGen6_moveWhileQueued() {
        h.add(Payloads.nativeMarker("A", "t"));
        RenderTask t = onlyTask();
        assertEquals(RenderTask.State.QUEUED, t.state);
        h.change(Payloads.nativeAt("A", "t", 10.0));
        assertSame("任务不能被替换或取消", t, onlyTask());
        assertEquals(RenderTask.State.QUEUED, t.state);
        assertEquals(1, t.waiters.size());
        assertEquals(h.point("A").generation(), t.waiters.get(0).generation);
        assertFalse("新增点在位图就绪前不 addMarker", h.host.hasMarker("A"));
        h.loop.drain();
        assertEquals(10.0, h.lat("A"), 0);
        assertEquals(1, h.painter.count());
    }

    // T-GEN-7：任务 running 时只改位置
    @Test
    public void tGen7_moveWhileRunning() {
        h.add(Payloads.nativeMarker("A", "t"));
        h.loop.runMain();
        assertEquals(RenderTask.State.RUNNING, onlyTask().state);
        h.change(Payloads.nativeAt("A", "t", 11.0));
        h.loop.drain();
        assertEquals(11.0, h.lat("A"), 0);
        assertEquals(1, h.painter.count());
    }

    // T-GEN-8：结果在 ApplyQueue 中时只改位置：旧项丢弃，新代次直接从缓存生成应用项
    @Test
    public void tGen8_moveWhileApplyPending() {
        h.add(Payloads.nativeMarker("A", "t"));
        h.loop.drainNoFrame();
        RenderCache.Entry c = h.r().cache.get(h.point("A").normalKey());
        assertEquals(1, c.pendingRefs());
        ApplyItem old = h.point("A").applying[0];
        h.change(Payloads.nativeAt("A", "t", 12.0));
        assertTrue(old.dropped);
        assertEquals(h.point("A").generation(), h.point("A").applying[0].generation);
        assertEquals(1, c.pendingRefs());
        h.loop.drain();
        assertEquals(0, c.pendingRefs());
        assertEquals(12.0, h.lat("A"), 0);
        assertEquals(1, h.painter.count());
        assertEquals(1, h.host.count("add:A"));
    }

    // T-GEN-9：执行期间连续改 10 次位置，绘制 1 次，最终位置为最后一次
    @Test
    public void tGen9_manyMovesWhileRunning() {
        h.add(Payloads.nativeMarker("A", "t"));
        h.loop.runMain();
        for (int i = 1; i <= 10; i++) {
            h.change(Payloads.nativeAt("A", "t", i));
        }
        h.loop.drain();
        assertEquals(1, h.painter.count());
        assertEquals(10.0, h.lat("A"), 0);
    }
}
