package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** §15 调度器不变量：所有渲染测试在 tearDown 中调用 */
final class RenderInvariants {
    private RenderInvariants() {
    }

    static void check(RenderHarness h) {
        NativeRenderer r = h.r();
        Map<RenderCache.Entry, Integer> display = new HashMap<>();
        Map<RenderCache.Entry, Integer> pending = new HashMap<>();
        Set<RenderTask> referenced = new HashSet<>();
        int waiterCount = 0;
        for (PointTable.Entry e : h.manager.points().values()) {
            if (e.shown != null) {
                display.merge(e.shown, 1, Integer::sum);
                // 显示条目对应的 Marker 确实在地图上并显示该 descriptor
                assertEquals(e.id + " 显示不一致", e.shown.descriptor, h.iconOf(e.id));
            }
            for (int role = 0; role < 2; role++) {
                Waiter w = e.waiting[role];
                ApplyItem a = e.applying[role];
                assertTrue(e.id + " role " + role + " 同时有两条接收路径", w == null || a == null);
                if (w != null) {
                    waiterCount++;
                    referenced.add(w.task);
                    assertTrue("waiter 必须在任务的 waiters 中", w.task.waiters.contains(w));
                    assertEquals("waiter 代次必须为当前值", e.generation, w.generation);
                }
                if (a != null) {
                    pending.merge(a.icon, 1, Integer::sum);
                }
            }
            // 有效点位缺少普通态时恰好有一条接收路径（R-GEN-2）
            if (e.placeholder) {
                // D-6 占位点：没有 key、没有接收路径、不持有资源
                assertTrue(e.id + " 占位点不应有接收路径", e.waiting[0] == null && e.applying[0] == null);
                assertTrue(e.id + " 占位点不应持有资源", e.heldImages.isEmpty());
                continue;
            }
            if (e.hidden) {
                // D-5 不显示的点：不在地图上、没有显示条目与接收路径
                assertTrue(e.id + " 隐藏点不应在地图上", !h.host.hasMarker(e.id) && e.shown == null);
                assertTrue(e.id + " 隐藏点不应有接收路径", e.waiting[0] == null && e.applying[0] == null);
                continue;
            }
            boolean needNormal = !e.isRemoving() && (e.shown == null || !e.shown.key.equals(e.normalKey))
                    && !e.normalKey.equals(e.failedKey[0]);
            if (needNormal && !r.isTerminated()) {
                assertTrue(e.id + " 缺少普通态接收路径", e.waiting[0] != null || e.applying[0] != null);
            }
        }
        for (RenderCache.Entry c : r.cache.entries()) {
            assertEquals(c.key + " displayRefs", (int) display.getOrDefault(c, 0), c.displayRefs());
            assertEquals(c.key + " pendingRefs", (int) pending.getOrDefault(c, 0), c.pendingRefs());
            assertEquals(c.key + " retainedRefs", 0, c.retainedRefs());
        }
        for (RenderCache.Entry c : display.keySet()) {
            assertNotNull("显示中的条目必须仍在缓存中", r.cache.get(c.key));
        }
        // 每个 key 最多一个任务；任务 waiters 恰好就是点位持有的登记
        int total = 0;
        Set<String> keys = new HashSet<>();
        for (RenderTask t : r.scheduler.tasks()) {
            assertTrue("同一 key 只能有一个任务", keys.add(t.key));
            total += t.waiters.size();
        }
        assertEquals("任务 waiters 与点位登记一致", waiterCount, total);
        checkImageRefs(h);
    }

    /** 资源引用：DESIRED = 点位持有数，QUEUED/RUNNING = 任务持有数 */
    private static void checkImageRefs(RenderHarness h) {
        NativeRenderer r = h.r();
        Map<String, Integer> desired = new HashMap<>();
        for (PointTable.Entry e : h.manager.points().values()) {
            for (String id : e.heldImages) {
                desired.merge(id, 1, Integer::sum);
            }
        }
        Map<String, Integer> queued = new HashMap<>();
        Map<String, Integer> running = new HashMap<>();
        for (RenderTask t : r.scheduler.tasks()) {
            Map<String, Integer> m = t.state == RenderTask.State.RUNNING ? running : queued;
            for (String id : t.images) {
                m.merge(id, 1, Integer::sum);
            }
        }
        for (ImageEntry e : r.registry.entries()) {
            assertEquals(e.id + " DESIRED", (int) desired.getOrDefault(e.id, 0), e.refs(ImageEntry.Ref.DESIRED));
            assertEquals(e.id + " QUEUED", (int) queued.getOrDefault(e.id, 0), e.refs(ImageEntry.Ref.QUEUED));
            assertEquals(e.id + " RUNNING", (int) running.getOrDefault(e.id, 0), e.refs(ImageEntry.Ref.RUNNING));
        }
    }

    /** 销毁最终完成：缓存、资源注册表、任务表都为空 */
    static void checkTerminated(RenderHarness h) {
        NativeRenderer r = h.r();
        assertTrue("管理器应进入 terminated", h.manager.isTerminated());
        assertEquals(0, r.cache.size());
        assertEquals(0, r.registry.size());
        assertEquals(0, r.scheduler.tasks().size());
    }
}
