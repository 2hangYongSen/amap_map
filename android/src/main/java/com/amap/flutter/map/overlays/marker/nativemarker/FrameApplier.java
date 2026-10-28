package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayDeque;

/**
 * 主线程应用（§8.4）：
 * - 选中相关项每帧按 4ms 预算立即放；
 * - 普通项（新增、修改）攒到普通态任务全部画完，在同一帧一次放完，地图只重画一次；
 * - 攒了超过 300ms 仍有普通态没画完，剩余项改为每帧按预算放，避免一张慢图拖住所有点。
 * 删除在 update 内同步执行或由过渡策略延迟，不经过这里。
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

    /** 普通项最多攒这么久；超时后按每帧预算先放已画好的 */
    static final long HOLD_TIMEOUT_NANOS = 300_000_000L;

    /** 后台是否还有未完成的普通态任务 */
    interface NormalPending {
        boolean get();
    }
    private NormalPending normalPending = () -> false;
    /** 是否在攒、第一项开始攒的时刻（nanoTime 可以是任意值，不能用 0 当“没在攒”） */
    private boolean holding = false;
    private long holdSince = 0;
    /** 本批已超时：剩余项按每帧预算放，直到普通态任务全部完成 */
    private boolean timedOut = false;

    void setNormalPending(NormalPending p) {
        normalPending = p;
    }

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
        // 选中相关项不攒，按预算先放；用完预算的帧不再放普通项
        drain(selectedQ, start, true);
        if (!selectedQ.isEmpty()) {
            repost();
            return;
        }
        boolean pending = normalPending.get();
        if (!pending) {
            timedOut = false;
        } else if (!timedOut && holding && start - holdSince >= HOLD_TIMEOUT_NANOS) {
            timedOut = true; // 有任务画得慢：不再等，先放已画好的
        }
        if (!pending) {
            // 普通态全部画完：一次放完，地图只重画一次
            drain(addQ, start, false);
            drain(changeQ, start, false);
            holding = false;
        } else if (timedOut) {
            drain(addQ, start, true);
            if (clock.nanoTime() - start < budgetNanos) {
                drain(changeQ, start, true);
            }
        } else if (!holding && addQ.size() + changeQ.size() > 0) {
            holding = true; // 开始攒
            holdSince = start;
        }
        if (addQ.isEmpty() && changeQ.isEmpty()) {
            holding = false; // 项被撤销或已放完：下一批重新计时
        }
        // 单项偶发超长（E-A2 最大 10～15ms）不拆分，只计数供诊断回执
        if (clock.nanoTime() - start > budgetNanos) {
            overBudgetFrames++;
        }
        repost();
    }

    private void repost() {
        if (size() > 0 && !disposed && !posted) {
            posted = true;
            clock.postFrame(frame);
        }
    }

    /** 放出队列中的项；budgeted 为真时超出本帧预算就停（预算在每一项之后检查） */
    private void drain(ArrayDeque<ApplyItem> q, long start, boolean budgeted) {
        ApplyItem item;
        while (!disposed && (item = q.poll()) != null) {
            if (!item.dropped) {
                sink.apply(item);
            }
            if (budgeted && clock.nanoTime() - start >= budgetNanos) {
                return;
            }
        }
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
