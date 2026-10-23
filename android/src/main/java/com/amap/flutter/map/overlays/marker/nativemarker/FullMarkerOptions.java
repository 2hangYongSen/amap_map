package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.List;
import java.util.Map;

/**
 * 新协议点位的完整期望状态（R-PROTO-2）。
 * 缺失或显式 null 的字段一律取 Dart Marker 的默认值，不沿用旧值。
 * 纯 Java，不依赖 SDK，便于 JVM 单测。
 */
public final class FullMarkerOptions {
    public static final String MODE_ICON = "icon";
    public static final String MODE_NATIVE = "native";

    public final String id;
    public final String renderMode;
    public final double latitude;
    public final double longitude;
    public final float alpha;
    public final float anchorU;
    public final float anchorV;
    public final boolean clickable;
    public final boolean draggable;
    public final boolean infoWindowEnable;
    public final String title;
    public final String snippet;
    /** 已按旧逻辑换算：abs(360 - rotation) */
    public final float rotation;
    public final boolean visible;
    public final float zIndex;
    /** icon 模式的原始图标描述，native 模式为 null */
    public final Object icon;
    /** native 模式的原始 presentation，icon 模式为 null；只供调试，渲染一律读 spec */
    public final Map<?, ?> nativePresentation;
    /** native 模式的规范化规格（R-NORM-1），icon 模式为 null */
    public final NativeMarkerSpec spec;
    public final boolean selectable;
    public final Float selectedZIndex;

    private FullMarkerOptions(Map<?, ?> m, String id, String mode, List<?> pos,
                              NativeMarkerSpec spec) {
        this.id = id;
        this.spec = spec;
        this.renderMode = mode;
        this.latitude = ((Number) pos.get(0)).doubleValue();
        this.longitude = ((Number) pos.get(1)).doubleValue();
        this.alpha = floatOr(m.get("alpha"), 1f);
        List<?> anchor = m.get("anchor") instanceof List ? (List<?>) m.get("anchor") : null;
        this.anchorU = anchor != null ? floatOr(anchor.get(0), 0.5f) : 0.5f;
        this.anchorV = anchor != null ? floatOr(anchor.get(1), 1f) : 1f;
        this.clickable = boolOr(m.get("clickable"), true);
        this.draggable = boolOr(m.get("draggable"), false);
        this.infoWindowEnable = boolOr(m.get("infoWindowEnable"), true);
        Map<?, ?> info = m.get("infoWindow") instanceof Map ? (Map<?, ?>) m.get("infoWindow") : null;
        this.title = info != null ? (String) info.get("title") : null;
        this.snippet = info != null ? (String) info.get("snippet") : null;
        this.rotation = Math.abs(360 - floatOr(m.get("rotation"), 0f));
        this.visible = boolOr(m.get("visible"), true);
        this.zIndex = floatOr(m.get("zIndex"), 0f);
        this.icon = m.get("icon");
        this.nativePresentation = (Map<?, ?>) m.get("nativePresentation");
        this.selectable = boolOr(m.get("selectable"), false);
        Object sz = m.get("selectedZIndex");
        this.selectedZIndex = sz == null ? null : ((Number) sz).floatValue();
    }

    /** 读取点位 id；没有合法 id 时返回 null（无法回报拒绝，按结构错误处理） */
    public static String readId(Object raw) {
        if (!(raw instanceof Map)) {
            return null;
        }
        Object id = ((Map<?, ?>) raw).get("id");
        return id instanceof String && !((String) id).isEmpty() ? (String) id : null;
    }

    /** 防御性校验并解析（R-PROTO-1、§6.6）；失败抛 InvalidMarkerException */
    public static FullMarkerOptions parse(Object raw) throws InvalidMarkerException {
        String id = readId(raw);
        if (id == null) {
            throw new InvalidMarkerException("点位缺少 id");
        }
        Map<?, ?> m = (Map<?, ?>) raw;
        Object mode = m.get("renderMode");
        if (!MODE_ICON.equals(mode) && !MODE_NATIVE.equals(mode)) {
            throw new InvalidMarkerException("renderMode 缺失或非法: " + mode);
        }
        boolean isNative = MODE_NATIVE.equals(mode);
        // 两种模式互斥：icon 必须带 icon，native 必须带 presentation
        if (isNative && !(m.get("nativePresentation") instanceof Map)) {
            throw new InvalidMarkerException("native 模式缺少 nativePresentation");
        }
        if (isNative && m.get("icon") != null) {
            throw new InvalidMarkerException("native 模式的 icon 必须为 null");
        }
        if (!isNative && !(m.get("icon") instanceof List)) {
            throw new InvalidMarkerException("icon 模式缺少 icon");
        }
        if (!isNative && m.get("nativePresentation") != null) {
            throw new InvalidMarkerException("icon 模式的 nativePresentation 必须为 null");
        }
        Object pos = m.get("position");
        if (!(pos instanceof List) || ((List<?>) pos).size() < 2) {
            throw new InvalidMarkerException("position 非法");
        }
        // native 点位先生成 NormSpec，非法配置在这里同步拒绝（R-NAT-REJ-1）
        NativeMarkerSpec spec = isNative
                ? NativeMarkerSpec.parse((Map<?, ?>) m.get("nativePresentation")) : null;
        try {
            return new FullMarkerOptions(m, id, (String) mode, (List<?>) pos, spec);
        } catch (ClassCastException | IndexOutOfBoundsException e) {
            throw new InvalidMarkerException("字段类型错误: " + e.getMessage());
        }
    }

    public boolean isNative() {
        return MODE_NATIVE.equals(renderMode);
    }

    private static float floatOr(Object o, float def) {
        return o == null ? def : ((Number) o).floatValue();
    }

    private static boolean boolOr(Object o, boolean def) {
        return o == null ? def : (Boolean) o;
    }
}
