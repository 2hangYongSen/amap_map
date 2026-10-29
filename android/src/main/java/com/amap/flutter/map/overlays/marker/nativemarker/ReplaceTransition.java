package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * replaceWhenReady 集合替换（§12）：删除延迟到本批新增点全部应用或超时，主线程访问。
 * 纯逻辑：真正删除、就绪判断、计时都由调用方提供。
 */
final class ReplaceTransition {
    static final String MODE_REPLACE = "replaceWhenReady";
    static final long DEFAULT_TIMEOUT_MS = 1000;

    interface Ops {
        /** 执行删除；g 为 null 表示 icon 点。返回是否真的删除（代次变化则作废） */
        boolean remove(String id, Integer g);

        /** 该点本批是否已处理完（已应用、失败或不再需要等待） */
        boolean settled(String id);

        void emit(String method, Map<String, Object> args);
    }

    private static final class Pending {
        final Integer generation;
        final int syncId;

        Pending(Integer g, int syncId) {
            this.generation = g;
            this.syncId = syncId;
        }
    }

    private final Ops ops;
    private final TaskRunner runner;
    private boolean enabled = false;
    private long timeoutMs = DEFAULT_TIMEOUT_MS;
    private final Map<String, Pending> pending = new LinkedHashMap<>();
    private final Set<String> waits = new LinkedHashSet<>();
    /** 当前这次 update 新登记的删除与等待 */
    private final Map<String, Pending> fresh = new LinkedHashMap<>();
    private final Set<String> freshWaits = new LinkedHashSet<>();
    /** 本批超时计时；从第一次进入待删除开始，后续更新不重新计时（R-DEL-4） */
    private Runnable timer;

    ReplaceTransition(Ops ops, TaskRunner runner) {
        this.ops = ops;
        this.runner = runner;
    }

    boolean enabled() {
        return enabled;
    }

    /** markerTransition 选项；切回 immediate 时立即执行全部待删除 */
    void configure(Object raw) {
        Map<?, ?> m = raw instanceof Map ? (Map<?, ?>) raw : null;
        enabled = m != null && MODE_REPLACE.equals(m.get("mode"));
        Object t = m == null ? null : m.get("timeoutMs");
        timeoutMs = t instanceof Number ? ((Number) t).longValue() : DEFAULT_TIMEOUT_MS;
        if (!enabled) {
            flush();
        }
    }

    /** update 处理期间不判断（等待条件尚未登记完整） */
    private boolean updating = false;

    void beginUpdate() {
        updating = true;
    }

    /** 本次 update 的一条删除；Marker 暂不移除 */
    void defer(String id, Integer g, int syncId) {
        Pending p = new Pending(g, syncId);
        fresh.put(id, p);
        pending.put(id, p);
    }

    /** 同一 id 重新加入：旧删除作废，不发 markers#removed（R-DEL-4） */
    void revive(String id) {
        pending.remove(id);
        fresh.remove(id);
    }

    boolean isPending(String id) {
        return pending.containsKey(id);
    }

    /** 本次 update 中需要等待绘制的新增或修改 */
    void waitFor(String id) {
        freshWaits.add(id);
    }

    /** 一次 update 结束：没有需要等待的新点就是显式删除，立即执行（R-DEL-1） */
    void endUpdate() {
        updating = false;
        if (!fresh.isEmpty() && freshWaits.isEmpty()) {
            for (String id : fresh.keySet()) {
                pending.remove(id);
            }
            execute(new LinkedHashMap<>(fresh));
        }
        waits.addAll(freshWaits);
        fresh.clear();
        freshWaits.clear();
        if (!pending.isEmpty() && timer == null) {
            startTimer();
        }
        check();
    }

    /** 新点应用或失败后调用：全部处理完就在当前帧执行删除（R-DEL-2/5） */
    void check() {
        if (updating) {
            return;
        }
        if (pending.isEmpty()) {
            finish();
            return;
        }
        for (String id : waits) {
            if (!ops.settled(id)) {
                return;
            }
        }
        flush();
    }

    /** 立即执行全部待删除（超时、resync、切回 immediate） */
    void flush() {
        Map<String, Pending> all = new LinkedHashMap<>(pending);
        pending.clear();
        finish();
        execute(all);
    }

    /** 销毁：撤销计时，不再发送事件 */
    void dispose() {
        pending.clear();
        fresh.clear();
        freshWaits.clear();
        finish();
    }

    private void finish() {
        waits.clear();
        if (timer != null && runner != null) {
            runner.cancelMainDelayed(timer);
        }
        timer = null;
    }

    private void startTimer() {
        if (runner == null) {
            flush(); // 协议桩模式没有异步绘制，不需要等待
            return;
        }
        final Runnable t = new Runnable() {
            @Override
            public void run() {
                if (timer == this) {
                    timer = null;
                    flush();
                }
            }
        };
        timer = t;
        runner.mainDelayed(t, timeoutMs);
    }

    /** 删除后发送 markers#removed，释放 Dart 保留的过渡回调（R-DEL-3） */
    private void execute(Map<String, Pending> batch) {
        List<String> ids = new ArrayList<>();
        List<Integer> syncIds = new ArrayList<>();
        for (Map.Entry<String, Pending> e : batch.entrySet()) {
            if (ops.remove(e.getKey(), e.getValue().generation)) {
                ids.add(e.getKey());
                syncIds.add(e.getValue().syncId);
            }
        }
        if (!ids.isEmpty()) {
            Map<String, Object> args = new HashMap<>();
            args.put("markerIds", ids);
            args.put("removeSyncIds", syncIds);
            ops.emit("markers#removed", args);
        }
    }
}
