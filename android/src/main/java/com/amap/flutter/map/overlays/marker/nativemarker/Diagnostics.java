package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 诊断与计时（§13）：markers#applied 回执、标记方块、tapId 关联、diag#ping。
 * 只在 markerDiagnostics 开启时工作；关闭时不发任何事件、不碰标记方块（T-TIME-3）。
 * 所有时间点用同一个原生单调时钟（FrameClock.nanoTime），换算为毫秒（R-TIME-4）。主线程访问。
 */
public final class Diagnostics {
    /** 地图角落的 8×8 标记方块（R-TIME-6），由平台层提供 */
    public interface Square {
        void show(int argb);

        void hide();
    }

    /** 回执所需的渲染器状态；协议桩模式全部为 0、settled 恒为真 */
    interface Source {
        boolean settled(String id);

        /** 该点当前显示的外观与选择状态一致（选中时为选中态，否则为普通态） */
        boolean appearanceCurrent(String id);

        long draws();

        long cacheHits();

        long cacheMisses();

        int pendingTasks();

        long compositeBytes();

        long decodedBytes();

        boolean compositeOverBudget();

        boolean decodedOverBudget();
    }

    /** 按 syncId 轮换的颜色，录屏中据此关联 syncId */
    static final int[] PALETTE = {0xFFFF0000, 0xFF00C853, 0xFF2962FF, 0xFFFFD600,
            0xFFD500F9, 0xFF00E5FF, 0xFFFF6D00, 0xFF000000};
    /** 未完成的点击最多保留条数，超出丢弃最早的 */
    static final int MAX_TAPS = 32;

    static final String PATH_ICON = "icon";
    static final String PATH_NATIVE = "native";

    private final FrameClock clock;
    private final NativeEventLog events;
    private final Source source;
    private Square square;
    private boolean enabled = false;
    private int tapSeq = 0;
    private final LinkedHashMap<Integer, Tap> taps = new LinkedHashMap<>();
    private final List<Sync> syncs = new ArrayList<>();
    /** 等待 t4 的请求最多保留条数（资源一直不就绪时不无限增长），超出丢弃最早的 */
    static final int MAX_SYNCS = 64;
    /** 当前请求中的 diagTapId（R-TIME-7），只在 update 处理期间有效 */
    private Integer requestTapId;

    /** clock 为 null 时（协议桩模式）用 System.nanoTime */
    Diagnostics(FrameClock clock, NativeEventLog events, Source source) {
        this.clock = clock;
        this.events = events;
        this.source = source;
    }

    double nowMs() {
        return (clock != null ? clock.nanoTime() : System.nanoTime()) / 1_000_000.0;
    }

    public boolean enabled() {
        return enabled;
    }

    /** map#update.options / 创建参数中的 markerDiagnostics；关闭时隐藏方块、丢弃未完成记录 */
    void setEnabled(boolean on) {
        if (enabled == on) {
            return;
        }
        enabled = on;
        if (!on) {
            taps.clear();
            syncs.clear();
            if (square != null) {
                square.hide();
            }
        }
    }

    void setSquare(Square s) {
        this.square = s;
    }

    // ---------- 更新回执（R-TIME-4/6） ----------

    /** 一次 markers#update / resync 的计时记录 */
    static final class Sync {
        final int syncId;
        double t2;
        Double t2v;
        Integer color;
        double t3;
        Double t4;
        int applied;
        long bytes;
        long draws0, hits0, misses0;
        final Set<String> remaining = new java.util.LinkedHashSet<>();

        Sync(int syncId) {
            this.syncId = syncId;
        }
    }

    /** t2：请求到达；同一次调用内切换标记方块颜色并记录 t2v。未开启时返回 null */
    Sync begin(int syncId, Object args) {
        if (!enabled) {
            return null;
        }
        Sync s = new Sync(syncId);
        s.t2 = nowMs();
        if (square != null) {
            s.color = PALETTE[Math.floorMod(syncId, PALETTE.length)];
            square.show(s.color);
            s.t2v = nowMs(); // 标记已提交（不等于上屏，R-TIME-6）
        }
        s.bytes = countBytes(args);
        s.draws0 = source.draws();
        s.hits0 = source.cacheHits();
        s.misses0 = source.cacheMisses();
        armFromRequest(args);
        return s;
    }

    /** 本次请求中被接受（未拒绝）的新增或修改点 */
    void touched(Sync s, String id) {
        if (s != null) {
            s.applied++;
            s.remaining.add(id);
        }
    }

    /** t3：通道返回前。同步应用已全部完成时 t4 记在 t3 之前（t4 ≤ t3，T-TIME-1） */
    void end(Sync s) {
        if (s == null) {
            return;
        }
        prune(s);
        if (s.remaining.isEmpty()) {
            s.t4 = nowMs();
        }
        s.t3 = nowMs();
        syncs.add(s);
        if (syncs.size() > MAX_SYNCS) {
            syncs.remove(0);
        }
        check();
    }

    /** 应用项处理完、任务结束后调用：本次涉及的点都已应用（或已失败）即发回执 */
    void check() {
        if (!enabled) {
            return;
        }
        checkTaps();
        for (Iterator<Sync> it = syncs.iterator(); it.hasNext(); ) {
            Sync s = it.next();
            prune(s);
            if (!s.remaining.isEmpty()) {
                continue;
            }
            if (s.t4 == null) {
                s.t4 = nowMs();
            }
            it.remove();
            events.event("markers#applied", receipt(s));
        }
    }

    private void prune(Sync s) {
        for (Iterator<String> it = s.remaining.iterator(); it.hasNext(); ) {
            if (source.settled(it.next())) {
                it.remove();
            }
        }
    }

    // ---------- 点击计时（R-TIME-2/7） ----------

    /** 一次点击：c1 在 SDK 点击回调里记录；awaiting 为真时等外观到位再记 c2 */
    static final class Tap {
        final int tapId;
        final String markerId;
        final double c1;
        /** c1 时的累计绘制次数；c2 时回报差值（§13.5 缓存命中点击不绘制） */
        final long draws0;
        String path = PATH_ICON;
        boolean awaiting = false;

        Tap(int tapId, String markerId, double c1, long draws0) {
            this.tapId = tapId;
            this.markerId = markerId;
            this.c1 = c1;
            this.draws0 = draws0;
        }
    }

    /** c1：SDK 点击回调；返回 tapId，未开启时返回 null */
    Integer tapBegin(String markerId) {
        if (!enabled) {
            return null;
        }
        Tap t = new Tap(++tapSeq, markerId, nowMs(), source.draws());
        taps.put(t.tapId, t);
        if (taps.size() > MAX_TAPS) {
            taps.remove(taps.keySet().iterator().next());
        }
        return t.tapId;
    }

    /** 新路径：选择已提交，等原生选中外观提交到 SDK 后记 c2，不经过 Dart */
    void tapAwaitNative(Integer tapId) {
        Tap t = tapId == null ? null : taps.get(tapId);
        if (t != null) {
            t.path = PATH_NATIVE;
            t.awaiting = true;
        }
    }

    /** 请求中的 diagTapId: {tapId, markerId}（旧路径，Dart 重发图标） */
    private void armFromRequest(Object args) {
        requestTapId = null;
        Object raw = args instanceof Map ? ((Map<?, ?>) args).get("diagTapId") : null;
        if (!(raw instanceof Map)) {
            return;
        }
        Object id = ((Map<?, ?>) raw).get("tapId");
        Tap t = id instanceof Number ? taps.get(((Number) id).intValue()) : null;
        if (t != null && !t.awaiting && t.markerId.equals(((Map<?, ?>) raw).get("markerId"))) {
            requestTapId = t.tapId;
        }
    }

    /**
     * 本次请求应用了某个点之后调用。旧 icon 点：setIcon 已返回，立即记 c2；
     * native 点：等外观到位（check 中判断）
     */
    void applied(String markerId, boolean nativeMode) {
        Tap t = requestTapId == null ? null : taps.get(requestTapId);
        if (t == null || !t.markerId.equals(markerId)) {
            return;
        }
        requestTapId = null;
        if (nativeMode) {
            t.awaiting = true;
        } else {
            finishTap(t);
        }
    }

    private void finishTap(Tap t) {
        taps.remove(t.tapId);
        Map<String, Object> m = new HashMap<>();
        m.put("tapId", t.tapId);
        m.put("markerId", t.markerId);
        m.put("c1Ms", t.c1);
        m.put("c2Ms", nowMs());
        m.put("path", t.path);
        m.put("drawCount", source.draws() - t.draws0);
        events.event("markers#tapApplied", m);
    }

    private void checkTaps() {
        for (Tap t : new ArrayList<>(taps.values())) {
            if (t.awaiting && source.appearanceCurrent(t.markerId)) {
                finishTap(t);
            }
        }
    }

    // ---------- 时钟校准与冷测试（R-TIME-3、§13.4） ----------

    /** diag#ping：返回原生读数 n；未开启返回 null */
    Map<String, Object> ping() {
        if (!enabled) {
            return null;
        }
        Map<String, Object> m = new HashMap<>();
        m.put("nativeMs", nowMs());
        return m;
    }

    /** 请求中所有字节数组的总长（bytes 资源与旧 fromBytes 图标） */
    static long countBytes(Object o) {
        if (o instanceof byte[]) {
            return ((byte[]) o).length;
        }
        long n = 0;
        if (o instanceof Map) {
            for (Object v : ((Map<?, ?>) o).values()) {
                n += countBytes(v);
            }
        } else if (o instanceof List) {
            for (Object v : (List<?>) o) {
                n += countBytes(v);
            }
        }
        return n;
    }

    private Map<String, Object> receipt(Sync s) {
        Map<String, Object> r = new HashMap<>();
        r.put("syncId", s.syncId);
        r.put("nativeT2Ms", s.t2);
        r.put("nativeT2vMs", s.t2v);
        r.put("markerColor", s.color == null ? null : (long) (s.color & 0xFFFFFFFFL));
        r.put("nativeT4Ms", s.t4);
        r.put("t2ToT3Ms", s.t3 - s.t2);
        r.put("t2ToT4Ms", s.t4 - s.t2);
        r.put("appliedCount", s.applied);
        r.put("drawCount", source.draws() - s.draws0);
        r.put("cacheHits", source.cacheHits() - s.hits0);
        r.put("cacheMisses", source.cacheMisses() - s.misses0);
        r.put("bytesReceived", s.bytes);
        r.put("pendingTasks", source.pendingTasks());
        Map<String, Object> mem = new HashMap<>();
        mem.put("compositeBytes", source.compositeBytes());
        mem.put("decodedBytes", source.decodedBytes());
        mem.put("compositeOverBudget", source.compositeOverBudget());
        mem.put("decodedOverBudget", source.decodedOverBudget());
        r.put("memory", mem);
        return r;
    }
}
