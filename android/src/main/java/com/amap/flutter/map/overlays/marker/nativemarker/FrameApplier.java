package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

/**
 * 主线程应用（§8.4）：
 * - 选中相关项每帧按 4ms 预算立即放；
 * - 普通项（新增、修改）攒到普通态任务全部画完，在同一帧一次放完，地图只重画一次；
 * - 攒的上限按本批点数算（每点 3ms，300ms～1s）；超时仍没画完，改为每 150ms 把已画好的一次放完，
 *   避免一张慢图拖住所有点，也不会一个个冒出来。
 * 删除在 update 内同步执行或由过渡策略延迟，不经过这里。
 */
final class FrameApplier {
    static final long DEFAULT_BUDGET_NANOS = 4_000_000L;

    interface Sink {
        /** 应用一项；已丢弃的项不会传进来 */
        void apply(ApplyItem item);

        /** 一次应用一批新增项（生产实现一次 addMarkers）；已丢弃的项不会传进来 */
        void applyAdds(List<ApplyItem> items);
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

    /** 普通项最多攒多久 = 本批点数 × 每点时长，夹在 [最短, 最长] 内；超时后整批放已画好的 */
    static final long HOLD_PER_ITEM_NANOS = 3_000_000L;
    static final long HOLD_MIN_NANOS = 300_000_000L;
    static final long HOLD_MAX_NANOS = 1_000_000_000L;
    /** 超时后每隔这么久把已画好的一次放完（不逐帧放，避免点一个个冒出来） */
    static final long BATCH_INTERVAL_NANOS = 150_000_000L;

    /** 后台未完成的普通态任务数 */
    interface NormalPending {
        int get();
    }
    private NormalPending normalPending = () -> 0;
    /** 本批的攒点上限、上一次整批放的时刻 */
    private long holdLimit = HOLD_MIN_NANOS;
    private long lastFlush = 0;
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
        int pending = normalPending.get();
        if (pending == 0) {
            timedOut = false;
        } else if (!timedOut && holding && start - holdSince >= holdLimit) {
            timedOut = true; // 画得比预期慢：不再等，开始整批放已画好的
            lastFlush = start - BATCH_INTERVAL_NANOS; // 超时这一帧立即放第一批
        }
        if (pending == 0 || (timedOut && start - lastFlush >= BATCH_INTERVAL_NANOS)) {
            // 全部画完，或超时后到了放下一批的时刻：已画好的一次放完，地图只重画一次
            drainAdds(); // 新增一次批量加，再逐个修改（新增先于修改，§8.4）
            drain(changeQ, start, false);
            lastFlush = start;
            if (pending == 0) {
                holding = false;
            }
        } else if (!holding && addQ.size() + changeQ.size() > 0) {
            holding = true; // 开始攒：按本批点数定上限
            holdSince = start;
            long n = pending + addQ.size() + changeQ.size();
            holdLimit = Math.max(HOLD_MIN_NANOS, Math.min(HOLD_MAX_NANOS, n * HOLD_PER_ITEM_NANOS));
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

    /** 新增队列整体出队，跳过已丢弃项，剩余一次交给 sink */
    private void drainAdds() {
        List<ApplyItem> batch = new ArrayList<>(addQ.size());
        ApplyItem item;
        while ((item = addQ.poll()) != null) {
            if (!item.dropped) {
                batch.add(item);
            }
        }
        if (!batch.isEmpty() && !disposed) {
            sink.applyAdds(batch);
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
