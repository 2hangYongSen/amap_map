package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** 批量派发（maxRunning 个在途）与后台优先级队列：P0 不被一批 P1/P2 挡住 */
public class BatchDispatchTest {

    /** 一次主线程挑选就把在途填满，后台不必每画一个都等主线程 */
    @Test
    public void onePumpFillsInFlightSlots() {
        RenderHarness h = new RenderHarness(8);
        h.add(points(20));
        h.loop.runMain(); // 只处理主线程：执行一次挑选
        assertEquals(8, h.r().scheduler.runningCount());
        assertEquals(8, h.loop.bg.size());
        h.loop.drain();
        assertEquals(20, h.host.markers.size());
        assertEquals(0, h.r().scheduler.runningCount());
    }

    /** 在途已满时，选中点的 P0 任务仍立即派发，并排到后台队列最前 */
    @Test
    public void selectedTaskBypassesFullBatch() {
        RenderHarness h = new RenderHarness(4);
        h.enableSelection();
        h.add(selectablePoints(10));
        h.loop.drain(); // 普通态全部显示；预热已完成
        // 换一批新文案：普通态、选中态都要重画；先只挑选，后台不执行
        h.change(selectablePoints(10, "新"));
        h.loop.runMain();
        assertEquals(4, h.r().scheduler.runningCount());
        h.select("p9"); // p9 选中态缓存已失效，需要 P0
        h.loop.runMain();
        assertEquals("P0 应占用额外名额立即派发", 5, h.r().scheduler.runningCount());
        // 后台队列按优先级执行：最先画的是 p9 的选中态
        RenderTask p0 = null;
        for (RenderTask t : h.r().scheduler.tasks()) {
            if (t.priority == RenderTask.P0) {
                p0 = t;
            }
        }
        assertTrue(p0 != null && p0.state == RenderTask.State.RUNNING);
        h.loop.drain();
        assertEquals(0, h.r().scheduler.runningCount());
    }

    /** 真实线程池：同一时刻排队的任务按 (优先级, 提交顺序) 出队；非绘制任务（解码）最先 */
    @Test
    public void executorRunsByPriorityThenOrder() throws Exception {
        PaintExecutor ex = new PaintExecutor(1, Thread::new);
        final CountDownLatch gate = new CountDownLatch(1);
        final List<String> order = Collections.synchronizedList(new ArrayList<String>());
        ex.execute(() -> await(gate)); // 占住唯一线程，后面的都进队列
        ex.execute(task(RenderTask.P2, "p2a", order));
        ex.execute(task(RenderTask.P1, "p1a", order));
        ex.execute(task(RenderTask.P2, "p2b", order));
        ex.execute(task(RenderTask.P0, "p0", order));
        ex.execute(task(RenderTask.P1, "p1b", order));
        ex.execute(() -> order.add("decode"));
        final CountDownLatch done = new CountDownLatch(1);
        ex.execute(task(9, "last", order, done));
        gate.countDown();
        assertTrue(done.await(5, TimeUnit.SECONDS));
        ex.shutdown();
        assertEquals(java.util.Arrays.asList("decode", "p0", "p1a", "p1b", "p2a", "p2b", "last"),
                order);
    }

    // ---------- 辅助 ----------

    @SuppressWarnings("unchecked")
    private static java.util.Map<String, Object>[] points(int n) {
        java.util.Map<String, Object>[] ms = new java.util.Map[n];
        for (int i = 0; i < n; i++) {
            ms[i] = Payloads.nativeMarker("p" + i, "¥" + (1000 + i));
        }
        return ms;
    }

    private static java.util.Map<String, Object>[] selectablePoints(int n) {
        return selectablePoints(n, "");
    }

    @SuppressWarnings("unchecked")
    private static java.util.Map<String, Object>[] selectablePoints(int n, String prefix) {
        java.util.Map<String, Object>[] ms = new java.util.Map[n];
        for (int i = 0; i < n; i++) {
            ms[i] = Payloads.selectable("p" + i, prefix + "¥" + (1000 + i));
        }
        return ms;
    }

    private static PaintExecutor.Prioritized task(int p, String name, List<String> out) {
        return task(p, name, out, null);
    }

    private static PaintExecutor.Prioritized task(final int p, final String name,
                                                  final List<String> out, final CountDownLatch done) {
        return new PaintExecutor.Prioritized() {
            @Override public int priority() { return p; }

            @Override public void run() {
                out.add(name);
                if (done != null) {
                    done.countDown();
                }
            }
        };
    }

    private static void await(CountDownLatch l) {
        try {
            l.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
