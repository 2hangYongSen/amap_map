package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 渲染 key（§9.4）：由 NormSpec 规范化序列化后哈希（R-KEY-3）。
 * 不含业务 ID、经纬度、zIndex、alpha、visible（R-KEY-2）。
 */
public final class RenderKey {
    /** 渲染模式版本号，绘制算法变化时递增 */
    public static final String VERSION = "v1";
    public static final String ROLE_NORMAL = "normal";
    public static final String ROLE_SELECTED = "selected";

    private RenderKey() {
    }

    public static String normalKey(NativeMarkerSpec spec, int densityUnits, ImageResolver r) {
        return of(spec, densityUnits, r, ROLE_NORMAL);
    }

    public static String selectedKey(NativeMarkerSpec spec, int densityUnits, ImageResolver r) {
        return of(spec, densityUnits, r, ROLE_SELECTED);
    }

    public static String of(NativeMarkerSpec spec, int densityUnits, ImageResolver r, String role) {
        return writer(spec, densityUnits, r, role).hash();
    }

    /** 未哈希的规范串，供测试断言 */
    static KeyWriter writer(NativeMarkerSpec spec, int densityUnits, ImageResolver r, String role) {
        KeyWriter k = new KeyWriter().s(VERSION);
        // 两态样式同时进入两个 key：它们共同决定画布 U 与绘制偏移
        spec.appendKey(k);
        k.tag("density").i(densityUnits);
        // 资源 ID + 解析结果（R-RES-12）：降级与正常位图不会互相命中
        k.tag("images");
        for (String id : spec.imageIds()) {
            k.s(id).s(r.usable(id) ? "ready" : "fallback");
        }
        k.tag("role").s(role);
        return k;
    }
}
