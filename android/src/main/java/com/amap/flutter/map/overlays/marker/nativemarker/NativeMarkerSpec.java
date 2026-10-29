package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Map;
import java.util.TreeSet;

/**
 * 规范化规格 NormSpec（§9.0 R-NORM-1）：原生收到 presentation 后只生成一次，
 * 之后校验、渲染 key、布局、绘制都只读它，不再读原始浮点值。不可变。
 */
public final class NativeMarkerSpec {
    public static final int ANCHOR_BODY_CENTER = 0;
    public static final int ANCHOR_ARROW_TIP = 1;
    public static final int ANCHOR_CUSTOM = 2;

    /** 空串视为无文字 */
    public final String text;
    public final String iconId;
    /** [w,h] 1/64 单位，可空（用图片逻辑尺寸） */
    public final int[] iconSize;
    public final int iconSpacing;
    public final NormStyle normal;
    /** 为空表示选中态沿用普通态（R-GEO-3） */
    public final NormStyle selected;
    public final int anchorType;
    /** custom 锚点（1/1024 单位）；其他类型恒为 0，避免无效字段影响 key */
    public final int anchorDx;
    public final int anchorDy;

    private NativeMarkerSpec(Map<?, ?> p) throws InvalidMarkerException {
        Map<?, ?> c = SpecReader.map(p, "content", true);
        String t = SpecReader.optString(c, "text");
        text = t == null || t.isEmpty() ? null : t;
        iconId = SpecReader.optString(c, "iconId");
        iconSize = SpecReader.optLengths(c, "iconSize", 2);
        iconSpacing = SpecReader.lengthOr(c, "iconSpacing", 4);
        normal = new NormStyle(SpecReader.map(p, "style", true));
        Map<?, ?> sel = SpecReader.map(p, "selectedStyle", false);
        selected = sel == null ? null : new NormStyle(sel);
        Object type = p.get("anchorType");
        if (type == null || "bodyCenter".equals(type)) {
            anchorType = ANCHOR_BODY_CENTER;
        } else if ("arrowTip".equals(type)) {
            anchorType = ANCHOR_ARROW_TIP;
        } else {
            SpecReader.require("custom".equals(type), "anchorType 非法: " + type);
            anchorType = ANCHOR_CUSTOM;
        }
        int[] a = readAnchor(p);
        anchorDx = a[0];
        anchorDy = a[1];
        validate();
    }

    /** 解析并校验；非法时抛 InvalidMarkerException（R-NAT-REJ-1 同步拒绝） */
    public static NativeMarkerSpec parse(Map<?, ?> presentation) throws InvalidMarkerException {
        if (presentation == null) {
            throw new InvalidMarkerException("nativePresentation 不能为空");
        }
        try {
            return new NativeMarkerSpec(presentation);
        } catch (ClassCastException e) {
            throw new InvalidMarkerException("presentation 字段类型错误: " + e.getMessage());
        }
    }

    /** 纯形状点位：无图标、两态都不是图片背景（D-6：S11 之前只有它走完整绘制） */
    public boolean isPureShape() {
        return iconId == null && !normal.isImage() && (selected == null || !selected.isImage());
    }

    /** 选中态有效样式 */
    public NormStyle selectedOrNormal() {
        return selected != null ? selected : normal;
    }

    /** 引用的全部图片资源 id（图标 + 两态背景），有序，供 key 与反向索引使用 */
    public TreeSet<String> imageIds() {
        TreeSet<String> ids = new TreeSet<>();
        if (iconId != null) {
            ids.add(iconId);
        }
        if (normal.isImage()) {
            ids.add(normal.imageId);
        }
        if (selected != null && selected.isImage()) {
            ids.add(selected.imageId);
        }
        return ids;
    }

    /** 规范化序列化（R-KEY-3），不含资源解析结果与 role */
    void appendKey(KeyWriter k) {
        k.tag("content").s(text).s(iconId).a(iconSize).i(iconSpacing);
        k.tag("normal");
        normal.appendKey(k);
        k.tag("selected");
        if (selected == null) {
            k.s("=normal");
        } else {
            selected.appendKey(k);
        }
        k.tag("anchor").i(anchorType).i(anchorDx).i(anchorDy);
    }

    private int[] readAnchor(Map<?, ?> p) throws InvalidMarkerException {
        int[] out = new int[2];
        if (anchorType != ANCHOR_CUSTOM) {
            return out;
        }
        Object raw = p.get("anchor");
        SpecReader.require(raw instanceof java.util.List && ((java.util.List<?>) raw).size() == 2,
                "custom 锚点必须提供 anchor");
        for (int i = 0; i < 2; i++) {
            out[i] = Norm.ratioUnits(SpecReader.number(((java.util.List<?>) raw).get(i), "anchor"));
        }
        return out;
    }

    /** R-VAL-6/8 与内容字段的防御性校验 */
    private void validate() throws InvalidMarkerException {
        SpecReader.require(text != null || iconId != null, "text 与 iconId 至少提供一个");
        // D-4：只支持单行文字
        SpecReader.require(text == null || (text.indexOf('\n') < 0 && text.indexOf('\r') < 0),
                "text 不能包含换行符");
        SpecReader.require(iconSpacing >= 0, "iconSpacing 不能为负");
        if (iconSize != null) {
            SpecReader.require(iconSize[0] >= 0 && iconSize[1] >= 0, "iconSize 不能为负");
        }
        if (anchorType == ANCHOR_CUSTOM) {
            for (int v : new int[]{anchorDx, anchorDy}) {
                SpecReader.require(v >= 0 && v <= Norm.RATIO_SCALE, "anchor 取值必须在 0 到 1 之间");
            }
        }
        // R-ANC-1：只要求普通态有箭头
        SpecReader.require(anchorType != ANCHOR_ARROW_TIP || normal.hasArrow,
                "arrowTip 锚点要求普通态设置箭头");
    }
}
