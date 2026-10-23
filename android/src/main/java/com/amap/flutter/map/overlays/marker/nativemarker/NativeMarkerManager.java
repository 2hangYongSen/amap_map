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
        this.events = new NativeEventLog(sink);
        this.renderer = deps == null ? null : new NativeRenderer(points, host, events, deps);
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
        List<ImageSource> images = parseImagesOrNull(params, "imagesToAdd");
        if (images == null) {
            events.error(ERR_INVALID_CONFIG, null, null, "创建参数 imagesToAdd 结构错误");
        }
        registerImages(images); // 初始资源先于初始点位
        Object list = params.get("markersToAdd");
        if (list instanceof List) {
            for (Object raw : (List<?>) list) {
                String id = FullMarkerOptions.readId(raw);
                if (id != null && !applyOne(raw, id)) {
                    initialRejected.add(id);
                }
            }
        }
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
        Map<String, Object> selection = new HashMap<>();
        selection.put("selectedId", null);
        selection.put("revision", 0);
        Map<String, Object> r = new HashMap<>();
        r.put("protocolVersion", PROTOCOL_V2);
        r.put("syncId", lastSyncId);
        r.put("rejectedMarkerIds", new ArrayList<>(initialRejected));
        r.put("images", images);
        r.put("selection", selection);
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
        Object removes = m.get("markerIdsToRemove");
        if (removes instanceof List) {
            for (Object id : (List<?>) removes) {
                if (id instanceof String) {
                    removeOne((String) id);
                }
            }
        }
        applyList(m.get("markersToAdd"), rejected);
        applyList(m.get("markersToChange"), rejected);
        if (renderer != null) {
            renderer.releaseImages(releases);
        }
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
        applyList(list, rejected);
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

    /** 应用单个完整对象；被拒绝时原生状态保持不变并返回 false（R-NAT-REJ-1） */
    private boolean applyOne(Object raw, String id) {
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

    private void removeOne(String id) {
        if (renderer != null && points.get(id) != null) {
            renderer.removeNative(id); // 代次校验 + remove() 后归还引用（R-GEN-6）
            return;
        }
        points.remove(id);
        host.removeMarker(id);
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
