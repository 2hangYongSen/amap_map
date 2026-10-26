package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 完整渲染模式（§7、§8）：点位同步、资源事件、预热与销毁。由 NativeMarkerManager 委托，主线程访问。
 */
final class NativeRenderer implements ImageRegistry.Listener, RenderPipeline.Listener {
    static final String ERR_RENDER_FAILED = "renderFailed";
    static final String ERR_IMAGE_MISSING = "imageMissing";

    final PointTable points;
    final ImageRegistry registry;
    final RenderCache cache;
    final RenderScheduler scheduler;
    final FrameApplier applier;
    private final ImageRefs refs;
    private final RenderPipeline pipeline;
    /** terminate 后置空：主线程 Handler 里残留的 Runnable 不再间接持有 amap 与通道（R-DISP-3） */
    private MarkerHost host;
    private NativeEventLog events;
    /** 同一实例用于投递与撤销 */
    private final Runnable stuckCheck = this::checkStuck;
    private final int densityUnits;
    private final TaskRunner runner;
    private final MarkerPainter painter;
    private final RenderDeps.DiagLog log;
    private final long stuckCheckMillis;
    /** 销毁 10s 后仍未归还的 running 任务数（诊断模式计入 disposeStuckTasks） */
    private int stuckTasks = 0;
    /**
     * 最近一次数据刷新时的淘汰计数；之后再发生淘汰就暂停预热到下次刷新，
     * 避免“预热入缓存 → 超预算淘汰 → 再预热”的循环（R-PRI-3）
     */
    private int evictsAtRefresh = 0;
    private boolean disposed = false;
    private boolean terminated = false;

    NativeRenderer(PointTable points, MarkerHost host, NativeEventLog events, RenderDeps d) {
        this.points = points;
        this.host = host;
        this.events = events;
        this.densityUnits = d.densityUnits;
        this.runner = d.runner;
        this.log = d.log;
        this.stuckCheckMillis = d.stuckCheckMillis;
        this.painter = d.painter;
        registry = new ImageRegistry(d.decoder, d.runner, d.decodeBudget);
        registry.setListener(this);
        refs = new ImageRefs(registry);
        cache = new RenderCache(d.icons, d.cacheBudget);
        scheduler = new RenderScheduler(registry, d.runner, d.painter, d.densityUnits, d.maxRunning);
        applier = new FrameApplier(d.clock, d.frameBudgetNanos);
        pipeline = new RenderPipeline(points, cache, scheduler, applier, host, d.icons);
        pipeline.setListener(this);
    }

    // ---------- 资源 ----------

    void registerImages(List<ImageSource> sources) {
        for (ImageSource s : sources) {
            registry.register(s);
        }
    }

    void releaseImages(List<String> ids) {
        for (String id : ids) {
            registry.release(id);
        }
    }

    void releaseImagesExcept(Set<String> keep) {
        registry.releaseAllExcept(keep);
    }

    // ---------- 点位 ----------

    /** 新增或整体替换 native 点位（R-PROTO-2）：代次 +1，按新 key 接续（R-GEN-2/5） */
    void applyNative(FullMarkerOptions opt) {
        if (!painter.supports(opt.spec)) {
            applyPlaceholder(opt);
            return;
        }
        PointTable.Entry e = points.put(opt);
        e.placeholder = false;
        for (String id : refs.hold(e, opt.spec.imageIds())) {
            events.error(ERR_IMAGE_MISSING, opt.id, id, "资源未登记: " + id);
        }
        if (host.hasMarker(opt.id)) {
            try {
                if (e.shown != null) {
                    host.updateNativeMarker(opt, null); // 只改属性，如 setPosition（R-GEN-5）
                } else {
                    host.updateMarker(opt, null); // icon→native：完成前保留旧图标（R-PROTO-4）
                }
            } catch (RuntimeException ex) {
                events.error(NativeMarkerManager.ERR_APPLY_FAILED, opt.id, null,
                        String.valueOf(ex.getMessage()));
            }
        }
        computeKeys(e);
        reportCapOverflow(e);
        reconcileRoles(e);
    }

    /**
     * R-NAT-REJ-2：九宫格 capInsets 要等资源 ready 才能判断。超限时保留期望快照、按默认背景显示，
     * 同一 normalKey 只报一次 invalidConfig；只有快照或资源解析结果变化（key 变化）才重新判断。
     */
    private void reportCapOverflow(PointTable.Entry e) {
        NativeMarkerSpec spec = e.desired.spec;
        boolean overflow = spec.normal.capOverflow(registry)
                || (spec.selected != null && spec.selected.capOverflow(registry));
        if (!overflow || e.normalKey.equals(e.capErrorKey)) {
            return;
        }
        e.capErrorKey = e.normalKey;
        events.error(NativeMarkerManager.ERR_INVALID_CONFIG, e.id, null,
                "capInsets 超出图片逻辑尺寸（R-VAL-5），按默认背景显示");
    }

    /** D-5：背景图失败、图标未配置或失败、且没有文字时不显示该点 */
    private boolean shouldHide(NativeMarkerSpec spec) {
        boolean bgFailed = spec.normal.isImage() && !registry.usable(spec.normal.imageId);
        boolean iconGone = spec.iconId == null || !registry.usable(spec.iconId);
        return bgFailed && iconGone && spec.text == null;
    }

    /**
     * D-6：painter 暂不支持（含图标或图片背景，S11 开放）的点位保持协议桩行为：
     * 只登记期望快照、显示占位图标，不调度、不持有资源引用、不报 renderFailed。
     */
    private void applyPlaceholder(FullMarkerOptions opt) {
        PointTable.Entry e = points.put(opt);
        pipeline.revokeAll(e);
        refs.releaseAll(e);
        e.placeholder = true;
        e.normalKey = null;
        e.selectedKey = null;
        boolean exists = host.hasMarker(opt.id);
        // 已显示原生位图时必须换成占位图标，之后才能归还显示引用（R-CACHE-1）
        Object icon = !exists || e.shown != null ? host.defaultIcon() : null;
        try {
            if (exists) {
                host.updateMarker(opt, icon);
            } else {
                host.addMarker(opt, icon);
            }
        } catch (RuntimeException ex) {
            events.error(NativeMarkerManager.ERR_APPLY_FAILED, opt.id, null,
                    String.valueOf(ex.getMessage()));
        }
        pipeline.releaseShown(e);
    }

    /** R-GEN-6 第一步：递增代次得到 g、标记待删除、撤销全部登记；Marker 暂时保留 */
    int beginRemoval(String id) {
        int g = points.beginRemoval(id);
        pipeline.revokeAll(points.get(id));
        return g;
    }

    /** R-GEN-6 第二步：代次仍为 g 才删除；否则这个 id 已被重新加入，旧删除作废 */
    boolean finishRemoval(String id, int g) {
        if (!points.isRemovalCurrent(id, g)) {
            return false;
        }
        PointTable.Entry e = points.get(id);
        pipeline.removeMarker(e);
        refs.releaseAll(e);
        points.remove(id);
        return true;
    }

    /** immediate 删除：登记与执行在同一次调用内完成 */
    void removeNative(String id) {
        finishRemoval(id, beginRemoval(id));
    }

    /** native→icon（R-PROTO-4）：释放绘制结果与图片引用，Marker 由调用方改成 icon */
    void releaseNative(String id) {
        PointTable.Entry e = points.get(id);
        pipeline.releaseShown(e);
        refs.releaseAll(e);
        points.remove(id);
    }

    private void computeKeys(PointTable.Entry e) {
        NativeMarkerSpec spec = e.desired.spec;
        e.normalKey = RenderKey.normalKey(spec, densityUnits, registry);
        e.selectedKey = e.desired.selectable
                ? RenderKey.selectedKey(spec, densityUnits, registry) : null;
    }

    /** 两个 role 各自判断是否还需要接收路径（R-GEN-2、R-GEN-5、R-PRI-1） */
    private void reconcileRoles(PointTable.Entry e) {
        e.hidden = shouldHide(e.desired.spec);
        if (e.hidden) {
            // 撤销接收路径并从地图移除；remove() 返回后才归还显示引用（R-CACHE-1）
            pipeline.removeMarker(e);
            return;
        }
        boolean needNormal = (e.shown == null || !e.shown.key.equals(e.normalKey))
                && !e.normalKey.equals(e.failedKey[0]);
        pipeline.reconcile(e, false, needNormal, RenderTask.P1);
        pipeline.reconcile(e, true, needsPrewarm(e) && prewarmAllowed(), RenderTask.P2);
    }

    /** 选中态预热：只针对 selectable 且选中态尚未就绪的点（§8.3 P2） */
    private boolean needsPrewarm(PointTable.Entry e) {
        return e.selectedKey != null && !e.isRemoving() && !e.hidden && !cache.contains(e.selectedKey)
                && !e.selectedKey.equals(e.failedKey[1]);
    }

    /** R-PRI-3：缓存 ≥90%、刷新后发生过淘汰、仍有 P0/P1 排队，任一成立就停止预热 */
    private boolean prewarmAllowed() {
        return !disposed && !cache.nearBudget() && cache.evictCount() == evictsAtRefresh
                && !scheduler.hasQueued(RenderTask.P0) && !scheduler.hasQueued(RenderTask.P1);
    }

    /** 条件变化后重新评估：允许则补登记，不允许则撤回排队中的 P2 */
    private void evaluatePrewarm() {
        if (disposed) {
            return;
        }
        boolean allow = prewarmAllowed();
        for (PointTable.Entry e : points.values()) {
            Waiter w = e.waiting[1];
            if (!allow && w != null && w.task.state == RenderTask.State.QUEUED
                    && w.task.priority == RenderTask.P2) {
                pipeline.reconcile(e, true, false, RenderTask.P2);
            } else if (allow && w == null && needsPrewarm(e)) {
                pipeline.reconcile(e, true, true, RenderTask.P2);
            }
        }
    }

    // ---------- 资源事件（R-RES-7、R-RES-12、R-INIT-2） ----------

    @Override
    public void onReady(ImageEntry e) {
        events.event("marker#imagesResult", imagesResult(e.id, null));
        rekey(e.id);
        scheduler.schedulePump(); // 等待资源的任务可以开始（R-RES-5）
    }

    @Override
    public void onFailed(ImageEntry e) {
        events.event("marker#imagesResult", imagesResult(null, ImageRegistry.failure(e)));
        events.error(ImageRegistry.ERR_DECODE_FAILED, null, e.id, e.failMessage);
        rekey(e.id);
    }

    @Override
    public void onRedecoded(ImageEntry e) {
        scheduler.schedulePump();
    }

    /** 资源解析结果变化：引用它的点重算 key，变化的代次 +1 并重新调度 */
    private void rekey(String imageId) {
        for (String id : refs.markersOf(imageId)) {
            PointTable.Entry p = points.get(id);
            if (p == null || p.isRemoving()) {
                continue;
            }
            String n = p.normalKey;
            String s = p.selectedKey;
            computeKeys(p);
            // pending → ready 时 key 不变，但尺寸刚知道，九宫格超限要在这里判断
            reportCapOverflow(p);
            if (!n.equals(p.normalKey) || (s != null && !s.equals(p.selectedKey))) {
                points.touch(id);
                reconcileRoles(p);
            }
        }
    }

    private static Map<String, Object> imagesResult(String ready, Map<String, Object> failed) {
        Map<String, Object> m = new HashMap<>();
        List<Object> r = new ArrayList<>();
        List<Object> f = new ArrayList<>();
        if (ready != null) {
            r.add(ready);
        }
        if (failed != null) {
            f.add(failed);
        }
        m.put("ready", r);
        m.put("failed", f);
        return m;
    }

    // ---------- 流水线回调 ----------

    @Override
    public void renderFailed(String markerId, String message) {
        if (events != null) {
            events.error(ERR_RENDER_FAILED, markerId, null, message);
        }
    }

    @Override
    public void applyFailed(String markerId, String message) {
        if (events != null) {
            events.error(NativeMarkerManager.ERR_APPLY_FAILED, markerId, null, message);
        }
    }

    @Override
    public void afterChange() {
        if (disposed) {
            if (scheduler.runningCount() == 0) {
                terminate();
            }
            return;
        }
        evaluatePrewarm();
    }

    // ---------- 销毁（§8.6） ----------

    /** 第一阶段：停调度、清应用队列、移除 Marker、归还全部引用；running 任务的输入原样保留 */
    void dispose() {
        if (disposed) {
            return;
        }
        disposed = true;
        pipeline.disposed = true;
        scheduler.dispose();
        for (PointTable.Entry e : points.values()) {
            pipeline.revokeAll(e); // 归还应用项的 pendingRefs
        }
        applier.dispose();
        for (PointTable.Entry e : new ArrayList<>(points.values())) {
            pipeline.removeMarker(e);
            refs.releaseAll(e);
        }
        points.clear();
        cache.evictAllEvictable();
        registry.dispose();
        runner.shutdown(); // 只停止接收新任务，不等待也不中断（R-DISP-3）
        if (scheduler.runningCount() == 0) {
            terminate();
        } else {
            runner.mainDelayed(stuckCheck, stuckCheckMillis);
        }
    }

    /** R-DISP-4：10s 后仍有 running 任务，只记录一次日志，仍不回收其输入 */
    private void checkStuck() {
        int n = scheduler.runningCount();
        if (!terminated && n > 0) {
            stuckTasks = n;
            log.d("销毁后仍有 " + n + " 个绘制任务未归还，输入资源保持不动");
        }
    }

    int stuckTasks() {
        return stuckTasks;
    }

    /** 第二阶段：最后一个 running 任务归还后，注册表与缓存应已全部为空 */
    private void terminate() {
        cache.evictAllEvictable();
        terminated = true;
        runner.cancelMainDelayed(stuckCheck); // 提前归还时撤销 10s 检查
        // 释放对 MarkersController（amap、methodChannel）的引用，Handler 只剩管理器内部对象
        host = null;
        events = null;
        pipeline.detachHost();
    }

    /** 测试：terminate 后不再持有 host 与事件出口 */
    boolean holdsHost() {
        return host != null || pipeline.holdsHost();
    }

    boolean holdsSink() {
        return events != null;
    }

    boolean isTerminated() {
        return terminated;
    }

    /** 测试与诊断：内部组件 */
    RenderPipeline pipeline() {
        return pipeline;
    }

    /** 数据刷新（每次 update/resync 结束）：预热条件重新评估（R-PRI-3） */
    void refreshDone() {
        evictsAtRefresh = cache.evictCount();
        evaluatePrewarm();
    }
}
