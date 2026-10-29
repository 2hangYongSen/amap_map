package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.List;

/**
 * 接收路径的核心（§8.2）：ensure 唯一入口、先接续后撤销（R-GEN-2）、结果逐个校验（R-GEN-3）、
 * 应用时读最新快照（R-GEN-4）、引用计数时机（R-CACHE-1）。主线程访问。
 */
final class RenderPipeline implements RenderScheduler.Callback, FrameApplier.Sink {
    interface Listener {
        void renderFailed(String markerId, String message);

        void applyFailed(String markerId, String message);

        /** 任务结束：重新评估预热、检查是否已终止 */
        void afterChange();

        /** 一个应用项处理完（成功或失败）：替换过渡据此判断是否可以删除旧点（R-DEL-2） */
        void applied();
    }

    private final PointTable points;
    private final RenderCache cache;
    private final RenderScheduler scheduler;
    private final FrameApplier applier;
    /** 销毁最终完成时置空（R-DISP-3），之后不会再有 SDK 调用 */
    private MarkerHost host;
    private final IconFactory icons;
    private Listener listener;
    private final SelectionState selection;
    boolean disposed = false;
    /** 诊断计数（R-TIME-4）：完成的绘制次数、ensure 时缓存命中 / 未命中次数 */
    long draws = 0;
    long cacheHits = 0;
    long cacheMisses = 0;

    RenderPipeline(PointTable points, RenderCache cache, RenderScheduler scheduler,
                   FrameApplier applier, MarkerHost host, IconFactory icons,
                   SelectionState selection) {
        this.selection = selection;
        this.points = points;
        this.cache = cache;
        this.scheduler = scheduler;
        this.applier = applier;
        this.host = host;
        this.icons = icons;
        scheduler.setCallback(this);
        applier.setSink(this);
    }

    void setListener(Listener l) {
        this.listener = l;
    }

    void detachHost() {
        host = null;
    }

    boolean holdsHost() {
        return host != null;
    }

    /** R-GEN-2：need 为真时先为当前代次登记新路径，再撤销旧路径（旧 waiter / 旧应用项） */
    void reconcile(PointTable.Entry e, boolean sel, boolean need, int priority) {
        int r = PointTable.Entry.role(sel);
        Waiter oldW = e.waiting[r];
        ApplyItem oldA = e.applying[r];
        e.waiting[r] = null;
        e.applying[r] = null;
        if (need) {
            ensure(e, sel, priority);
        }
        revoke(oldW, oldA);
    }

    /** “需要 key K”的唯一入口：缓存命中 → 应用项；已有任务 → 加 waiter；否则新建任务 */
    private void ensure(PointTable.Entry e, boolean sel, int priority) {
        String key = sel ? e.selectedKey : e.normalKey;
        RenderCache.Entry c = cache.get(key);
        if (c != null) {
            cacheHits++;
        } else {
            cacheMisses++;
        }
        if (c != null) {
            if (appliesRole(e, sel)) {
                enqueueApply(e, sel, c);
            }
            return; // 未选中点的预热：命中缓存即完成
        }
        RenderTask t = scheduler.find(key);
        e.waiting[PointTable.Entry.role(sel)] = t != null
                ? scheduler.addWaiter(t, e.id, e.generation, sel, priority)
                : scheduler.create(key, e.desired.spec, sel, priority, e.id, e.generation);
    }

    /** 当前应显示选中外观：可选中（有 selectedKey）、未待删除、且是 selectedId（§11） */
    boolean wantsSelected(PointTable.Entry e) {
        return e.selectedKey != null && !e.isRemoving() && e.id.equals(selection.selectedId());
    }

    /** 普通态结果总要应用（显示或转为备用）；选中态结果只在仍应选中时应用，否则只进缓存 */
    private boolean appliesRole(PointTable.Entry e, boolean sel) {
        return !sel || wantsSelected(e);
    }

    private void enqueueApply(PointTable.Entry e, boolean sel, RenderCache.Entry c) {
        cache.addPending(c);
        // 选中态项与“从选中态恢复普通态”的项优先应用（§8.4）
        ApplyItem it = new ApplyItem(e, e.generation, sel, c, !host.hasMarker(e.id),
                sel || e.shownSelected);
        e.applying[PointTable.Entry.role(sel)] = it;
        applier.enqueue(it);
    }

    void revokeAll(PointTable.Entry e) {
        for (int r = 0; r < 2; r++) {
            revoke(e.waiting[r], e.applying[r]);
            e.waiting[r] = null;
            e.applying[r] = null;
        }
    }

    private void revoke(Waiter w, ApplyItem a) {
        if (w != null) {
            scheduler.removeWaiter(w);
        }
        if (a != null) {
            drop(a);
        }
    }

    private void drop(ApplyItem a) {
        if (!a.dropped) {
            a.dropped = true;
            cache.dropPending(a.icon);
        }
    }

    /** R-GEN-3：写缓存，再逐个校验 waiter；不通过的只丢这条登记，不丢位图 */
    @Override
    public void onTaskDone(RenderTask t, MarkerPainter.Result result, Throwable error) {
        if (disposed) {
            if (result != null) {
                icons.discard(result.bitmap); // 迟到输出从未交给 SDK（R-DISP-2）
            }
            listener.afterChange();
            return;
        }
        RenderCache.Entry c = null;
        if (result != null) {
            draws++;
            try {
                // fromBitmap 在 toDescriptor 内部，失败时它已在 finally 中回收合成位图
                c = cache.put(t.key, result.bitmap, result.anchorU, result.anchorV);
            } catch (RuntimeException | Error ex) {
                error = ex; // 不写缓存，下面按绘制失败记 failedKey 并报 renderFailed
            }
        }
        for (Waiter w : new ArrayList<>(t.waiters)) {
            PointTable.Entry e = points.get(w.markerId);
            int r = PointTable.Entry.role(w.selected);
            if (e == null || e.waiting[r] != w) {
                continue; // 已被撤销或替换（理论上撤销时已移出 waiters）
            }
            e.waiting[r] = null;
            if (!e.isValid(w.generation, w.selected, t.key)) {
                continue;
            }
            if (c == null) {
                // 绘制失败：保持原显示，报错一次；key 变化前不自动重试（§6.6）
                e.failedKey[r] = t.key;
                listener.renderFailed(e.id, String.valueOf(error == null ? "绘制结果为空"
                        : error.getMessage()));
            } else if (appliesRole(e, w.selected)) {
                enqueueApply(e, w.selected, c);
            }
        }
        t.waiters.clear();
        if (c != null) {
            cache.enforceBudget();
        }
        listener.afterChange();
    }

    /** 帧回调中应用一项：再校验一次代次与 key，读最新快照（R-GEN-3/4） */
    @Override
    public void apply(ApplyItem it) {
        PointTable.Entry e = it.point;
        int r = PointTable.Entry.role(it.selected);
        e.applying[r] = null;
        cache.dropPending(it.icon);
        it.dropped = true;
        if (points.get(e.id) == e && e.isValid(it.generation, it.selected, it.icon.key)) {
            applyValid(e, it);
        }
        listener.applied();
    }

    /**
     * 一批新增项：校验同 apply；需要新建 Marker 的普通态一次 addNativeMarkers，
     * 其余（已有 Marker、选中相关、备用）逐个走 applyValid。完成通知整批只发一次。
     */
    @Override
    public void applyAdds(List<ApplyItem> items) {
        List<ApplyItem> batch = new ArrayList<>(items.size());
        for (ApplyItem it : items) {
            PointTable.Entry e = it.point;
            e.applying[PointTable.Entry.role(it.selected)] = null;
            cache.dropPending(it.icon);
            it.dropped = true;
            if (points.get(e.id) != e || !e.isValid(it.generation, it.selected, it.icon.key)) {
                continue;
            }
            if (it.selected || wantsSelected(e) || host.hasMarker(e.id)) {
                applyValid(e, it); // 少见情况：保持逐个处理的原有分支
            } else {
                batch.add(it);
            }
        }
        if (!batch.isEmpty()) {
            addBatch(batch);
        }
        listener.applied();
    }

    /** 按当前 selectedId 与 role 决定显示、保留或丢弃（R-CACHE-6 末条） */
    private void applyValid(PointTable.Entry e, ApplyItem it) {
        boolean sel = wantsSelected(e);
        if (it.selected && !sel) {
            return; // 选择已变化：迟到的选中态只留在缓存（T-SEL-1）
        }
        if (!it.selected && sel && e.shownSelected) {
            retain(e, it.icon); // 备用普通态：只登记保留，不覆盖选中外观
            return;
        }
        RenderCache.Entry old = e.shown;
        boolean oldSelected = e.shownSelected;
        cache.addDisplay(it.icon); // 先登记新显示，失败再撤回
        try {
            if (host.hasMarker(e.id)) {
                host.updateNativeMarker(e.desired, it.icon.icon(), it.selected);
            } else {
                host.addNativeMarker(e.desired, it.icon.icon(), it.selected);
            }
        } catch (RuntimeException ex) {
            cache.dropDisplay(it.icon);
            e.failedKey[PointTable.Entry.role(it.selected)] = it.icon.key;
            listener.applyFailed(e.id, String.valueOf(ex.getMessage()));
            return;
        }
        e.shown = it.icon;
        e.shownSelected = it.selected;
        if (it.selected) {
            keepNormalBackup(e, old, oldSelected);
        } else {
            releaseRetained(e); // 普通态已取得显示引用，再归还备用，引用转移无空档
        }
        // R-CACHE-1：旧条目在 setIcon(new) 返回之后才减 1
        if (old != null) {
            cache.dropDisplay(old);
        }
        cache.enforceBudget();
    }

    /** 批量新建普通态 Marker；引用规则与 applyValid 相同，SDK 抛异常按整批失败 */
    private void addBatch(List<ApplyItem> batch) {
        List<FullMarkerOptions> opts = new ArrayList<>(batch.size());
        List<NativeIcon> nis = new ArrayList<>(batch.size());
        List<Boolean> sels = new ArrayList<>(batch.size());
        for (ApplyItem it : batch) {
            cache.addDisplay(it.icon); // 先登记新显示，失败再撤回
            opts.add(it.point.desired);
            nis.add(it.icon.icon());
            sels.add(false);
        }
        try {
            host.addNativeMarkers(opts, nis, sels);
        } catch (RuntimeException ex) {
            for (ApplyItem it : batch) {
                cache.dropDisplay(it.icon);
                it.point.failedKey[0] = it.icon.key;
                listener.applyFailed(it.point.id, String.valueOf(ex.getMessage()));
            }
            return;
        }
        for (ApplyItem it : batch) {
            PointTable.Entry e = it.point;
            RenderCache.Entry old = e.shown;
            e.shown = it.icon;
            e.shownSelected = false;
            releaseRetained(e);
            if (old != null) {
                cache.dropDisplay(old); // R-CACHE-1：新图标交给 SDK 之后才归还旧的
            }
        }
        cache.enforceBudget();
    }

    /** 切到选中态后：备用必须对应当前 normalKey，取自旧普通态显示或已就绪缓存 */
    private void keepNormalBackup(PointTable.Entry e, RenderCache.Entry old, boolean oldSelected) {
        if (e.retainedNormal != null && e.retainedNormal.key.equals(e.normalKey)) {
            return;
        }
        RenderCache.Entry c = old != null && !oldSelected && old.key.equals(e.normalKey)
                ? old : cache.get(e.normalKey);
        if (c != null) {
            retain(e, c);
        } else {
            releaseRetained(e); // 普通态还没就绪：接收路径照常保留，就绪后再取得备用
        }
    }

    /** 取得备用引用（同一条目不重复取）；旧备用随后归还 */
    private void retain(PointTable.Entry e, RenderCache.Entry c) {
        if (e.retainedNormal == c) {
            return;
        }
        cache.addRetained(c);
        releaseRetained(e);
        e.retainedNormal = c;
    }

    /** 归还备用引用（删除、native→icon、销毁、恢复普通态、normalKey 失效） */
    void releaseRetained(PointTable.Entry e) {
        if (e.retainedNormal != null) {
            cache.dropRetained(e.retainedNormal);
            e.retainedNormal = null;
        }
    }

    /** normalKey 变化后备用失效：立即撤销（R-CACHE-6） */
    void dropStaleRetained(PointTable.Entry e) {
        if (e.retainedNormal != null && !e.retainedNormal.key.equals(e.normalKey)) {
            releaseRetained(e);
        }
    }

    /** 点位删除：remove() 返回之后才归还显示引用（R-CACHE-1） */
    void removeMarker(PointTable.Entry e) {
        revokeAll(e);
        host.removeMarker(e.id);
        releaseShown(e);
    }

    /** native→icon：放弃原生显示引用与备用，Marker 本身由调用方改成 icon */
    void releaseShown(PointTable.Entry e) {
        revokeAll(e);
        if (e.shown != null) {
            cache.dropDisplay(e.shown);
            e.shown = null;
        }
        e.shownSelected = false;
        releaseRetained(e);
    }
}
