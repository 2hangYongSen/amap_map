package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 每张地图一个：新协议状态、点位表与事件出口（§4、§6）。
 * S5 为协议桩：native 点位只登记期望快照并显示占位图标，不绘制。
 * 全部方法在主线程调用。
 */
public final class NativeMarkerManager {
    public static final int PROTOCOL_V2 = 2;
    public static final String ERR_INVALID_CONFIG = "invalidConfig";
    public static final String ERR_APPLY_FAILED = "applyFailed";

    private final MarkerHost host;
    private final PointTable points = new PointTable();
    private final NativeEventLog events;
    /** 原有事件（marker#onTap）直接发送，不受新协议开关影响 */
    private final MarkerEventSink sink;
    /** 完整渲染模式；为 null 时保持 S5 协议桩（native 点显示占位图标） */
    private final NativeRenderer renderer;
    private boolean v2 = false;
    private boolean disposed = false;
    private int lastSyncId = 0;
    /** 创建参数为新协议时的初始拒绝列表（R-INIT-3） */
    private final List<String> initialRejected = new ArrayList<>();

    public NativeMarkerManager(MarkerHost host, MarkerEventSink sink) {
        this(host, sink, null);
    }

    public NativeMarkerManager(MarkerHost host, MarkerEventSink sink, RenderDeps deps) {
        this.host = host;
        this.sink = sink;
        this.events = new NativeEventLog(sink);
        this.renderer = deps == null ? null
                : new NativeRenderer(points, host, events, deps, selection);
        this.transition = new ReplaceTransition(new TransitionOps(),
                deps == null ? null : deps.runner);
        if (renderer != null) {
            renderer.setTransition(transition);
        }
    }

    /** 原生单选（§11） */
    private final SelectionState selection = new SelectionState();
    /** 集合替换过渡（§12） */
    private final ReplaceTransition transition;
    /** icon 模式点位中 selectable 的 id（native 点读期望快照） */
    private final Set<String> selectableIcons = new HashSet<>();

    public SelectionState selection() {
        return selection;
    }

    /** 测试与诊断：替换过渡 */
    ReplaceTransition transition() {
        return transition;
    }

    /** 测试与诊断：完整模式的内部组件，协议桩模式为 null */
    NativeRenderer renderer() {
        return renderer;
    }

    /** 载荷是否为新协议；不带 protocolVersion 的请求走旧逻辑（R-PROTO-3） */
    public static boolean isV2Payload(Object args) {
        if (!(args instanceof Map)) {
            return false;
        }
        Object v = ((Map<?, ?>) args).get("protocolVersion");
        return v instanceof Number && ((Number) v).intValue() >= PROTOCOL_V2;
    }

    public boolean isV2() {
        return v2;
    }

    public boolean isDisposed() {
        return disposed;
    }

    public PointTable points() {
        return points;
    }

    /** 创建参数为新协议：登记初始点位，拒绝结果留给 attach 返回（R-SYNC-4） */
    public void applyCreation(Map<?, ?> params) {
        if (disposed) {
            return;
        }
        v2 = true;
        applyOptions(params); // 创建参数顶层带 markerSelection、markerTransition（§6.1）
        List<ImageSource> images = parseImagesOrNull(params, "imagesToAdd");
        if (images == null) {
            events.error(ERR_INVALID_CONFIG, null, null, "创建参数 imagesToAdd 结构错误");
        }
        registerImages(images); // 初始资源先于初始点位
        transition.beginUpdate();
        Object list = params.get("markersToAdd");
        if (list instanceof List) {
            for (Object raw : (List<?>) list) {
                String id = FullMarkerOptions.readId(raw);
                if (id != null && !applyOne(raw, id)) {
                    initialRejected.add(id);
                }
            }
        }
        transition.endUpdate(); // 初始没有删除，只清掉等待登记
        refreshDone();
    }

    /**
     * markers#attach：幂等启用新协议并返回当前状态快照（R-INIT-3）。
     * 生成快照与打开事件开关在同一次调用内完成（R-INIT-4）。
     */
    public Map<String, Object> attach() {
        v2 = true;
        Map<String, Object> images;
        if (renderer != null) {
            images = renderer.registry.snapshot(); // 握手前的资源结果只在这里交付（R-INIT-2/3）
        } else {
            images = new HashMap<>();
            images.put("ready", new ArrayList<>());
            images.put("failed", new ArrayList<>());
            images.put("pending", new ArrayList<>());
        }
        Map<String, Object> r = new HashMap<>();
        r.put("protocolVersion", PROTOCOL_V2);
        r.put("syncId", lastSyncId);
        r.put("rejectedMarkerIds", new ArrayList<>(initialRejected));
        r.put("images", images);
        r.put("selection", selection.snapshot());
        r.put("lastEventSeq", events.lastEventSeq());
        r.put("errors", events.errorsSnapshot());
        r.put("errorsDropped", events.errorsDropped());
        events.open();
        return r;
    }

    /** 新协议 markers#update（§6.2、§6.5）；结构错误时整体不修改，accepted=false */
    public Map<String, Object> update(Object args) {
        int syncId = readSyncId(args);
        List<ImageSource> images = disposed ? null : parseImagesOrNull(args, "imagesToAdd");
        List<String> releases = disposed ? null : stringsOrNull(args, "imageIdsToRelease");
        if (images == null || releases == null
                || !isValidStructure(args, "markersToAdd", "markersToChange")) {
            return result(syncId, false, new ArrayList<String>());
        }
        v2 = true;
        initialRejected.clear();
        Map<?, ?> m = (Map<?, ?>) args;
        List<String> rejected = new ArrayList<>();
        // 顺序：登记资源 → 删除 → 新增 → 修改 → 释放资源（§6.2）
        registerImages(images);
        transition.beginUpdate();
        Object removes = m.get("markerIdsToRemove");
        if (removes instanceof List) {
            for (Object id : (List<?>) removes) {
                if (id instanceof String) {
                    removeOrDefer((String) id, syncId);
                }
            }
        }
        applyList(m.get("markersToAdd"), rejected);
        applyList(m.get("markersToChange"), rejected);
        if (renderer != null) {
            renderer.releaseImages(releases);
        }
        transition.endUpdate(); // 没有需要等待的新点即显式删除，立即执行（R-DEL-1）
        refreshDone();
        lastSyncId = syncId;
        return result(syncId, true, rejected);
    }

    /** markers#resync：以快照为唯一期望状态，多余点位全部删除（R-RES-9） */
    public Map<String, Object> resync(Object args) {
        int syncId = readSyncId(args);
        List<ImageSource> images = disposed ? null : parseImagesOrNull(args, "images");
        if (images == null || !isValidStructure(args, "markers")) {
            return result(syncId, false, new ArrayList<String>());
        }
        v2 = true;
        initialRejected.clear();
        registerImages(images);
        Object list = ((Map<?, ?>) args).get("markers");
        Set<String> keep = new HashSet<>();
        for (Object raw : (List<?>) list) {
            keep.add(FullMarkerOptions.readId(raw));
        }
        for (String id : snapshotIds(host.markerIds())) {
            if (!keep.contains(id)) {
                removeOne(id);
            }
        }
        for (String id : points.ids()) {
            if (!keep.contains(id)) {
                removeOne(id);
            }
        }
        List<String> rejected = new ArrayList<>();
        applyList(list, rejected); // 快照中重新出现的待删除点在这里作废
        // 其余待删除立即执行；Dart 在 resync 返回时清空过渡条目
        transition.flush();
        if (renderer != null) {
            Set<String> keepImages = new HashSet<>();
            for (ImageSource s : images) {
                keepImages.add(s.id);
            }
            renderer.releaseImagesExcept(keepImages); // R-RES-9
        }
        refreshDone();
        lastSyncId = syncId;
        return result(syncId, true, rejected);
    }

    /**
     * 第一阶段销毁（§8.6）：关闭事件、移除全部 Marker、清空点位表。
     * 必须在 mapView.onDestroy() 之前调用（R-DISP-2）。幂等。
     */
    public void dispose() {
        if (disposed) {
            return;
        }
        disposed = true;
        events.close();
        transition.dispose(); // 撤销超时计时；Marker 由下面统一移除
        selectableIcons.clear();
        if (renderer != null) {
            renderer.dispose(); // 先按引用规则移除 native 点（§8.6）
        }
        for (String id : snapshotIds(host.markerIds())) {
            host.removeMarker(id);
        }
        points.clear();
        initialRejected.clear();
    }

    /** 两阶段销毁是否最终完成（最后一个 running 任务归还后） */
    public boolean isTerminated() {
        return disposed && (renderer == null || renderer.isTerminated());
    }

    private void applyList(Object list, List<String> rejected) {
        if (!(list instanceof List)) {
            return;
        }
        for (Object raw : (List<?>) list) {
            String id = FullMarkerOptions.readId(raw);
            if (!applyOne(raw, id)) {
                rejected.add(id);
            }
        }
    }

    /** 应用单个对象，再处理过渡等待与 R-SEL-7；拒绝时状态不变 */
    private boolean applyOne(Object raw, String id) {
        boolean wasSelectable = isSelectable(id);
        if (!applyRaw(raw, id)) {
            return false;
        }
        transition.revive(id); // 待删除的 id 重新出现：旧删除作废（R-DEL-4）
        if (transition.enabled() && renderer != null && renderer.needsWait(id)) {
            transition.waitFor(id);
        }
        // R-SEL-7：选中点由可选中改为不可选中才取消（API 选中的非 selectable 点不受影响）
        if (id.equals(selection.selectedId()) && wasSelectable && !isSelectable(id)) {
            commit(selection.set(null, SelectionState.INVALIDATED));
        }
        return true;
    }

    /** 点位当前是否可选中：native 读期望快照，icon 读登记表 */
    private boolean isSelectable(String id) {
        PointTable.Entry e = points.get(id);
        return e != null ? e.desired != null && e.desired.selectable : selectableIcons.contains(id);
    }

    /** R-SEL-1：先发事件，再按新选择重新调度外观（事件不等外观） */
    private void commit(SelectionState.Change c) {
        if (c == null) {
            return;
        }
        events.event("marker#selectionChanged", c.toMap());
        if (renderer != null) {
            renderer.selectionChanged(c.previousId, c.selectedId);
        }
    }

    private boolean applyRaw(Object raw, String id) {
        FullMarkerOptions opt;
        Object icon = null;
        try {
            opt = FullMarkerOptions.parse(raw);
            if (!opt.isNative()) {
                icon = host.decodeIcon(opt.icon); // 先解码，失败则整点拒绝
            }
        } catch (InvalidMarkerException | RuntimeException e) {
            events.error(ERR_INVALID_CONFIG, id, null, String.valueOf(e.getMessage()));
            return false;
        }
        boolean exists = host.hasMarker(id);
        if (!opt.isNative() && opt.selectable) {
            selectableIcons.add(id);
        } else {
            selectableIcons.remove(id);
        }
        if (renderer != null) {
            return applyFullMode(opt, icon, exists);
        }
        if (opt.isNative()) {
            points.put(opt);
            // icon→native：绘制完成前保留旧图标（R-PROTO-4）；新增先用占位图标
            icon = exists ? null : host.defaultIcon();
        } else {
            // native→icon：清除原生状态，S9 起同时撤销任务与缓存引用
            points.remove(id);
        }
        try {
            if (exists) {
                host.updateMarker(opt, icon);
            } else {
                host.addMarker(opt, icon);
            }
        } catch (RuntimeException e) {
            events.error(ERR_APPLY_FAILED, id, null, String.valueOf(e.getMessage()));
        }
        return true;
    }

    /** 完整模式：native 交给渲染器（新增点在位图就绪前不 addMarker，R-RES-5） */
    private boolean applyFullMode(FullMarkerOptions opt, Object icon, boolean exists) {
        if (opt.isNative()) {
            renderer.applyNative(opt);
            return true;
        }
        try {
            if (exists) {
                host.updateMarker(opt, icon);
            } else {
                host.addMarker(opt, icon);
            }
        } catch (RuntimeException e) {
            events.error(ERR_APPLY_FAILED, opt.id, null, String.valueOf(e.getMessage()));
        }
        // native→icon：setIcon(icon) 返回之后才归还原生显示引用（R-CACHE-1、R-PROTO-4）
        if (points.get(opt.id) != null) {
            renderer.releaseNative(opt.id);
        }
        return true;
    }

    /** immediate 删除；选中点被删除时选择保留、不发事件（R-SEL-6） */
    private void removeOne(String id) {
        transition.revive(id);
        selectableIcons.remove(id);
        if (renderer != null && points.get(id) != null) {
            renderer.removeNative(id); // 代次校验 + remove() 后归还引用（R-GEN-6）
            return;
        }
        points.remove(id);
        host.removeMarker(id);
    }

    /** replaceWhenReady：登记待删除(g)，Marker 保持可见、可点击（R-DEL-3） */
    private void removeOrDefer(String id, int syncId) {
        // 地图上还没有 Marker（新点仍在绘制）时没有可见内容需要保留，直接删除
        if (!transition.enabled() || !host.hasMarker(id)) {
            removeOne(id);
            return;
        }
        Integer g = renderer != null && points.get(id) != null ? renderer.beginRemoval(id) : null;
        transition.defer(id, g, syncId);
    }

    /** 替换过渡的 SDK 出口 */
    private final class TransitionOps implements ReplaceTransition.Ops {
        @Override
        public boolean remove(String id, Integer g) {
            if (g != null) {
                return renderer.finishRemoval(id, g); // 代次不符即作废（R-GEN-6）
            }
            if (renderer != null && points.get(id) != null) {
                return false; // 已作为 native 点重新加入
            }
            boolean had = host.hasMarker(id);
            selectableIcons.remove(id);
            points.remove(id);
            host.removeMarker(id);
            return had;
        }

        @Override
        public boolean settled(String id) {
            return renderer == null || renderer.settled(id);
        }

        @Override
        public void emit(String method, Map<String, Object> args) {
            events.event(method, args);
        }
    }

    // ---------- 选择（§11）与选项 ----------

    /** markers#setSelected：返回提交后的 revision；id 相同不发事件（R-SEL-4） */
    public Map<String, Object> setSelected(Object args) {
        Object id = args instanceof Map ? ((Map<?, ?>) args).get("markerId") : null;
        v2 = true;
        if (!disposed) {
            commit(selection.set(id instanceof String ? (String) id : null, SelectionState.API));
        }
        Map<String, Object> r = new HashMap<>();
        r.put("revision", selection.revision());
        return r;
    }

    /**
     * 点位点击（R-SEL-2/3）：先提交选择并发 selectionChanged，再发原有的 marker#onTap。
     * onTap 与 1.0.15 相同，旧协议也照常发送；过渡中的待删除点同样可点（R-DEL-3）
     */
    public void onMarkerTap(String id) {
        if (disposed) {
            return;
        }
        if (v2) {
            commit(selection.onMarkerTap(id, isSelectable(id)));
        }
        Map<String, Object> data = new HashMap<>(1);
        data.put("markerId", id);
        sink.emit("marker#onTap", data);
    }

    /** 地图空白处单击（R-SEL-2）；点击点位时 SDK 不会再回调这里（E-A4） */
    public void onMapTap() {
        if (v2 && !disposed) {
            commit(selection.onMapTap());
        }
    }

    /** map#update.options 与创建参数中的 markerSelection、markerTransition；键缺失不改 */
    public void applyOptions(Map<?, ?> options) {
        if (options == null || disposed) {
            return;
        }
        if (options.containsKey("markerSelection")) {
            selection.configure(options.get("markerSelection"));
        }
        if (options.containsKey("markerTransition")) {
            transition.configure(options.get("markerTransition"));
        }
    }

    private void registerImages(List<ImageSource> images) {
        if (renderer != null && images != null) {
            renderer.registerImages(images);
        }
    }

    private void refreshDone() {
        if (renderer != null) {
            renderer.refreshDone();
        }
    }

    private static boolean isValidStructure(Object args, String... listKeys) {
        if (!(args instanceof Map)) {
            return false;
        }
        Map<?, ?> m = (Map<?, ?>) args;
        for (String key : listKeys) {
            Object v = m.get(key);
            if (v != null && !(v instanceof List)) {
                return false;
            }
            // 每个点位必须带可回报的 id，否则无法逐点拒绝
            if (v != null) {
                for (Object raw : (List<?>) v) {
                    if (FullMarkerOptions.readId(raw) == null) {
                        return false;
                    }
                }
            }
        }
        Object removes = m.get("markerIdsToRemove");
        return removes == null || removes instanceof List;
    }

    /** 资源列表：缺省为空；结构错误返回 null（整个请求 accepted=false） */
    private static List<ImageSource> parseImagesOrNull(Object args, String key) {
        Object v = args instanceof Map ? ((Map<?, ?>) args).get(key) : null;
        List<ImageSource> out = new ArrayList<>();
        if (v == null) {
            return out;
        }
        if (!(v instanceof List)) {
            return null;
        }
        try {
            for (Object raw : (List<?>) v) {
                out.add(ImageSource.parse(raw));
            }
        } catch (InvalidMarkerException e) {
            return null;
        }
        return out;
    }

    private static List<String> stringsOrNull(Object args, String key) {
        Object v = args instanceof Map ? ((Map<?, ?>) args).get(key) : null;
        List<String> out = new ArrayList<>();
        if (v == null) {
            return out;
        }
        if (!(v instanceof List)) {
            return null;
        }
        for (Object o : (List<?>) v) {
            if (o instanceof String) {
                out.add((String) o);
            }
        }
        return out;
    }

    private static int readSyncId(Object args) {
        Object v = args instanceof Map ? ((Map<?, ?>) args).get("syncId") : null;
        return v instanceof Number ? ((Number) v).intValue() : 0;
    }

    private static Map<String, Object> baseResult(int syncId, boolean accepted,
                                                  List<String> rejected) {
        Map<String, Object> r = new HashMap<>();
        r.put("syncId", syncId);
        r.put("accepted", accepted);
        r.put("rejectedMarkerIds", rejected);
        r.put("imagesPending", new ArrayList<String>());
        return r;
    }

    /** 返回值带上当前仍为 pending 的资源（§6.5） */
    private Map<String, Object> result(int syncId, boolean accepted, List<String> rejected) {
        Map<String, Object> r = baseResult(syncId, accepted, rejected);
        if (renderer != null && accepted) {
            r.put("imagesPending", renderer.registry.pendingIds());
        }
        return r;
    }

    private static List<String> snapshotIds(Iterable<String> ids) {
        List<String> copy = new ArrayList<>();
        for (String id : ids) {
            copy.add(id);
        }
        return copy;
    }
}
