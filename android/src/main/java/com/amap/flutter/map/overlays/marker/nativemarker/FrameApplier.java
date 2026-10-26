package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayDeque;

/**
 * 主线程分帧应用（§8.4）：每帧最多 4ms，预算在每一项之后检查；超时剩余留到下一帧。
 * 顺序：选中态相关 → 新增 → 修改（删除在 update 内同步执行或由过渡策略延迟，不经过这里）。
 */
final class FrameApplier {
    static final long DEFAULT_BUDGET_NANOS = 4_000_000L;

    interface Sink {
        /** 应用一项；已丢弃的项不会传进来 */
        void apply(ApplyItem item);
    }

    private final FrameClock clock;
    private final long budgetNanos;
    private final ArrayDeque<ApplyItem> selectedQ = new ArrayDeque<>();
    private final ArrayDeque<ApplyItem> addQ = new ArrayDeque<>();
    private final ArrayDeque<ApplyItem> changeQ = new ArrayDeque<>();
    private final Runnable frame = this::onFrame;
    private Sink sink;
    private boolean posted = false;
    private int overBudgetFrames = 0;
    private boolean disposed = false;

    FrameApplier(FrameClock clock, long budgetNanos) {
        this.clock = clock;
        this.budgetNanos = budgetNanos;
    }

    void setSink(Sink s) {
        this.sink = s;
    }

    void enqueue(ApplyItem item) {
        if (disposed) {
            return;
        }
        (item.urgent ? selectedQ : item.isAdd ? addQ : changeQ).add(item);
        if (!posted) {
            posted = true;
            clock.postFrame(frame);
        }
    }

    private void onFrame() {
        posted = false;
        long start = clock.nanoTime();
        ApplyItem item;
        while ((item = next()) != null) {
            if (!item.dropped) {
                sink.apply(item);
            }
            long spent = clock.nanoTime() - start;
            if (spent >= budgetNanos && size() > 0) {
                break;
            }
        }
        // 单项偶发超长（E-A2 最大 10～15ms）不拆分，只计数供诊断回执
        if (clock.nanoTime() - start > budgetNanos) {
            overBudgetFrames++;
        }
        if (size() > 0 && !disposed) {
            posted = true;
            clock.postFrame(frame);
        }
    }

    private ApplyItem next() {
        if (!selectedQ.isEmpty()) {
            return selectedQ.poll();
        }
        return !addQ.isEmpty() ? addQ.poll() : changeQ.poll();
    }

    /** 队列中的项（含已丢弃、尚未出队的） */
    int size() {
        return selectedQ.size() + addQ.size() + changeQ.size();
    }

    int overBudgetFrames() {
        return overBudgetFrames;
    }

    /** 第一阶段销毁：移除帧回调、清空队列；pendingRefs 由调用方按 PointTable 归还 */
    void dispose() {
        disposed = true;
        if (posted) {
            clock.removeFrame(frame);
            posted = false;
        }
        selectedQ.clear();
        addQ.clear();
        changeQ.clear();
    }
}
