package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/** 完整渲染模式的测试装配：管理器 + 假地图 + 可控事件循环 */
final class RenderHarness {
    final FakeRender.Loop loop = new FakeRender.Loop();
    final FakeRender.Painter painter = new FakeRender.Painter();
    final FakeRender.Icons icons = new FakeRender.Icons();
    final FakeImages.Decoder decoder = new FakeImages.Decoder();
    final FakeMarkerHost host = new FakeMarkerHost();
    final List<String> emitted = new ArrayList<>();
    final List<String> logs = new ArrayList<>();
    final List<Map<String, Object>> emittedArgs = new ArrayList<>();
    final NativeMarkerManager manager;
    private int syncId = 0;

    RenderHarness() {
        this(1);
    }

    RenderHarness(int maxRunning) {
        this(maxRunning, RenderCache.DEFAULT_BUDGET);
    }

    RenderHarness(int maxRunning, long cacheBudget) {
        RenderDeps d = new RenderDeps(decoder, loop, painter, icons, loop, 2880); // 密度 2.8125
        d.maxRunning = maxRunning;
        d.log = logs::add;
        d.cacheBudget = cacheBudget;
        manager = new NativeMarkerManager(host, (m, a) -> {
            emitted.add(m);
            emittedArgs.add(a);
        }, d);
    }

    NativeRenderer r() {
        return manager.renderer();
    }

    PointTable.Entry point(String id) {
        return manager.points().get(id);
    }

    @SafeVarargs
    final Map<String, Object> add(Map<String, Object>... ms) {
        return manager.update(Payloads.add(++syncId, ms));
    }

    @SafeVarargs
    final Map<String, Object> change(Map<String, Object>... ms) {
        return manager.update(Payloads.update(++syncId, null, ms));
    }

    Map<String, Object> remove(String... ids) {
        return manager.update(Payloads.update(++syncId, new ArrayList<Object>(Arrays.asList(
                (Object[]) ids))));
    }

    /** 注册资源（imagesToAdd） */
    @SafeVarargs
    final Map<String, Object> images(Map<String, Object>... imgs) {
        Map<String, Object> u = Payloads.update(++syncId, null);
        u.put("imagesToAdd", new ArrayList<Object>(Arrays.asList((Object[]) imgs)));
        return manager.update(u);
    }

    /** 某点当前地图上的位置 */
    double lat(String id) {
        return host.markers.get(id).options.latitude;
    }

    Object iconOf(String id) {
        return host.markers.get(id).icon;
    }
}
