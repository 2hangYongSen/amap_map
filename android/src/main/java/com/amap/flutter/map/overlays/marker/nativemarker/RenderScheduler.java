package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CancellationException;
import java.util.concurrent.RejectedExecutionException;

/**
 * TaskTable 与优先级调度（§8.2、§8.3）。主线程挑选下一个任务，后台最多 maxRunning 个并发：
 * 与“单线程执行器 + 优先队列”等价，且提升优先级、撤回 P2 都只是主线程上的一次修改。
 */
final class RenderScheduler {
    interface Callback {
        /** 主线程：任务结束，result 与 error 二选一；资源 RUNNING 引用已归还 */
        void onTaskDone(RenderTask t, MarkerPainter.Result result, Throwable error);
    }

    /** 每个渲染 key 最多一个 queued 或 running 任务 */
    private final Map<String, RenderTask> tasks = new LinkedHashMap<>();
    private final ImageRegistry registry;
    private final TaskRunner runner;
    private final MarkerPainter painter;
    private final int densityUnits;
    private final int maxRunning;
    private Callback callback;
    private long seq = 0;
    private int running = 0;
    private boolean pumpPosted = false;
    private boolean disposed = false;

    RenderScheduler(ImageRegistry registry, TaskRunner runner, MarkerPainter painter,
                    int densityUnits, int maxRunning) {
        this.registry = registry;
        this.runner = runner;
        this.painter = painter;
        this.densityUnits = densityUnits;
        this.maxRunning = maxRunning;
    }

    void setCallback(Callback cb) {
        this.callback = cb;
    }

    RenderTask find(String key) {
        return tasks.get(key);
    }

    /** 新建任务，第一个 waiter 就是调用方；资源取“排队任务”引用 */
    Waiter create(String key, NativeMarkerSpec spec, boolean selected, int priority,
                  String markerId, int generation) {
        RenderTask t = new RenderTask(key, spec, selected, priority, ++seq);
        for (String id : spec.imageIds()) {
            // 记录 key 当时的解析结果，绘制只用这些资源，避免结果与 key 不一致（R-RES-12）
            if (registry.usable(id)) {
                t.expectReady.add(id);
            }
            if (registry.acquire(id, ImageEntry.Ref.QUEUED)) {
                t.images.add(id);
            }
        }
        tasks.put(key, t);
        schedulePump();
        return addWaiter(t, markerId, generation, selected, priority);
    }

    /** 登记到已有任务，必要时提升优先级（R-PRI-2），不新建任务 */
    Waiter addWaiter(RenderTask t, String markerId, int generation, boolean selected,
                     int priority) {
        Waiter w = new Waiter(markerId, generation, selected, t);
        t.waiters.add(w);
        if (priority < t.priority) {
            t.priority = priority;
        }
        return w;
    }

    /** 撤销登记：只有 waiters 为空且仍为 queued 的任务才取消，running 一律执行完（R-GEN-2） */
    void removeWaiter(Waiter w) {
        RenderTask t = w.task;
        t.waiters.remove(w);
        if (t.waiters.isEmpty() && t.state == RenderTask.State.QUEUED) {
            cancel(t);
        }
    }

    private void cancel(RenderTask t) {
        t.state = RenderTask.State.CANCELLED;
        tasks.remove(t.key);
        for (String id : t.images) {
            registry.unref(id, ImageEntry.Ref.QUEUED);
        }
        t.images.clear();
    }

    /** 投递一次挑选；同一次主线程处理内的多次登记合并后再按优先级挑选 */
    void schedulePump() {
        if (!pumpPosted && !disposed) {
            pumpPosted = true;
            runner.main(this::pump);
        }
    }

    private void pump() {
        pumpPosted = false;
        while (!disposed && running < maxRunning) {
            RenderTask best = null;
            for (RenderTask t : tasks.values()) {
                if (t.state == RenderTask.State.QUEUED && ready(t) && (best == null || t.before(best))) {
                    best = t;
                }
            }
            if (best == null) {
                return;
            }
            start(best);
        }
    }

    /** R-RES-5：key 按 ready 解析的资源必须已解码（含淘汰后重新解码完成）才开始 */
    private boolean ready(RenderTask t) {
        for (String id : t.expectReady) {
            ImageEntry e = registry.entry(id);
            if (e == null || e.state() != ImageEntry.State.READY || e.decoded() == null) {
                return false;
            }
        }
        return true;
    }

    /** 开始执行：先取 RUNNING 再还 QUEUED，引用无空档（S8 交接） */
    private void start(RenderTask t) {
        for (String id : t.images) {
            registry.acquire(id, ImageEntry.Ref.RUNNING);
            registry.unref(id, ImageEntry.Ref.QUEUED);
        }
        t.state = RenderTask.State.RUNNING;
        t.job = new PaintJob(t.key, t.spec, t.selected, densityUnits, registry, t.expectReady);
        running++;
        final PaintJob job = t.job;
        boolean accepted = runner.background(() -> {
            MarkerPainter.Result out = null;
            Throwable err = null;
            try {
                if (job.isCancelled()) {
                    // 销毁前还在执行器队列里：不再绘制，直接走归还（§8.6 第一阶段第 2 步）
                    throw new CancellationException("绘制已取消");
                }
                out = painter.paint(job);
            } catch (Exception | Error ex) {
                err = ex; // OOM 等 Error 也不能让后台线程崩溃，按 renderFailed 处理
            } finally {
                // 无论成功、异常还是取消，都把 RUNNING 引用的归还投递回主线程（§8.6 第二阶段）
                final MarkerPainter.Result r = out;
                final Throwable e = err;
                runner.main(() -> finish(t, r, e));
            }
        });
        if (!accepted) {
            // 执行器已关闭：任务不会执行，立即在主线程归还（running--，可能进入 terminated）
            finish(t, null, new RejectedExecutionException("后台执行器已关闭"));
        }
    }

    /** 主线程：归还 RUNNING 引用，移出任务表，再交给回调分发（R-GEN-3） */
    private void finish(RenderTask t, MarkerPainter.Result r, Throwable e) {
        running--;
        tasks.remove(t.key);
        t.state = RenderTask.State.DONE;
        for (String id : t.images) {
            registry.unref(id, ImageEntry.Ref.RUNNING);
        }
        t.images.clear();
        callback.onTaskDone(t, r, e);
        schedulePump();
    }

    /** 当前排队中的任务（P2 撤回、诊断用） */
    List<RenderTask> queued() {
        List<RenderTask> out = new ArrayList<>();
        for (RenderTask t : tasks.values()) {
            if (t.state == RenderTask.State.QUEUED) {
                out.add(t);
            }
        }
        return out;
    }

    /** 第一阶段销毁：撤销排队任务并归还引用；running 只置取消标记，不回收输入（R-DISP-1） */
    void dispose() {
        disposed = true;
        for (RenderTask t : new ArrayList<>(tasks.values())) {
            t.waiters.clear();
            if (t.state == RenderTask.State.QUEUED) {
                cancel(t);
            } else if (t.job != null) {
                t.job.cancel();
            }
        }
    }

    Collection<RenderTask> tasks() { return tasks.values(); }

    int runningCount() { return running; }

    boolean hasQueued(int priority) {
        for (RenderTask t : tasks.values()) {
            if (t.state == RenderTask.State.QUEUED && t.priority == priority) {
                return true;
            }
        }
        return false;
    }
}
