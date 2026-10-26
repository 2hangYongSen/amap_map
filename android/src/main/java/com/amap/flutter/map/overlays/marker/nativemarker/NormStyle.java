package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Map;

/**
 * 单个状态的规范化样式（§9.0 NormSpec 的一部分）。长度字段都是 1/64 单位整数。
 * 构造即完成 R-VAL-2～4 的原生防御性校验（R-VAL-10：对规范化后的值执行）。
 */
public final class NormStyle {
    public static final int BG_CIRCLE = 0;
    public static final int BG_RECT = 1;
    public static final int BG_IMAGE = 2;

    public final int bgType;
    public final int diameter;
    public final int fillColor;
    public final int cornerRadius;
    public final Integer borderColor;
    public final int borderWidth;
    public final String imageId;
    /** 图片固定尺寸 [w,h]，可空 */
    public final int[] imageSize;
    /** 九宫格 [l,t,r,b]，可空 */
    public final int[] capInsets;

    public final int fontSize;
    public final int fontWeight;
    public final int textColor;
    /** left / center / right */
    public final String textAlign;
    /** [l,t,r,b] */
    public final int[] padding;
    public final Integer width;
    public final Integer height;
    public final Integer minWidth;
    public final Integer maxWidth;

    public final boolean hasArrow;
    public final int arrowWidth;
    public final int arrowHeight;
    /** 为空时沿用形状填充色 */
    public final Integer arrowColor;

    public final boolean hasShadow;
    public final int shadowColor;
    public final int shadowBlur;
    public final int shadowDx;
    public final int shadowDy;

    NormStyle(Map<?, ?> s) throws InvalidMarkerException {
        Map<?, ?> bg = SpecReader.map(s, "background", true);
        Object type = bg.get("type");
        if ("shape".equals(type)) {
            boolean circle = "circle".equals(bg.get("kind"));
            SpecReader.require(circle || "roundedRect".equals(bg.get("kind")), "background.kind 非法");
            bgType = circle ? BG_CIRCLE : BG_RECT;
            diameter = circle ? SpecReader.length(bg, "diameter") : 0;
            fillColor = SpecReader.color(bg, "fillColor");
            cornerRadius = circle ? 0 : SpecReader.lengthOr(bg, "cornerRadius", 0);
            borderColor = SpecReader.optColor(bg, "borderColor");
            borderWidth = SpecReader.lengthOr(bg, "borderWidth", 0);
            imageId = null;
            imageSize = null;
            capInsets = null;
        } else {
            SpecReader.require("image".equals(type), "background.type 非法: " + type);
            bgType = BG_IMAGE;
            diameter = 0;
            fillColor = 0;
            cornerRadius = 0;
            borderColor = null;
            borderWidth = 0;
            imageId = SpecReader.optString(bg, "imageId");
            SpecReader.require(imageId != null && !imageId.isEmpty(), "background.imageId 不能为空");
            imageSize = SpecReader.optLengths(bg, "size", 2);
            capInsets = SpecReader.optLengths(bg, "capInsets", 4);
        }
        fontSize = SpecReader.lengthOr(s, "fontSize", 12);
        Object w = s.get("fontWeight");
        fontWeight = w == null ? 400 : (int) SpecReader.number(w, "fontWeight");
        Integer tc = SpecReader.optColor(s, "textColor");
        textColor = tc == null ? 0xFF000000 : tc;
        String align = SpecReader.optString(s, "textAlign");
        textAlign = align == null ? "center" : align;
        int[] pad = SpecReader.optLengths(s, "padding", 4);
        padding = pad == null ? new int[4] : pad;
        width = SpecReader.optLength(s, "width");
        height = SpecReader.optLength(s, "height");
        minWidth = SpecReader.optLength(s, "minWidth");
        maxWidth = SpecReader.optLength(s, "maxWidth");

        Map<?, ?> arrow = SpecReader.map(s, "arrow", false);
        hasArrow = arrow != null;
        arrowWidth = hasArrow ? SpecReader.length(arrow, "width") : 0;
        arrowHeight = hasArrow ? SpecReader.length(arrow, "height") : 0;
        arrowColor = hasArrow ? SpecReader.optColor(arrow, "color") : null;

        Map<?, ?> shadow = SpecReader.map(s, "shadow", false);
        hasShadow = shadow != null;
        shadowColor = hasShadow ? SpecReader.color(shadow, "color") : 0;
        shadowBlur = hasShadow ? SpecReader.lengthOr(shadow, "blurRadius", 0) : 0;
        int[] off = hasShadow ? SpecReader.optLengths(shadow, "offset", 2) : null;
        shadowDx = off == null ? 0 : off[0];
        shadowDy = off == null ? 0 : off[1];
        validate();
    }

    public boolean isImage() {
        return bgType == BG_IMAGE;
    }

    /**
     * R-VAL-5 的原生异步部分：资源 ready（尺寸已知）后 capInsets 超出图片逻辑尺寸。
     * 尺寸未知（pending）时无法判断，返回 false；布局与 R-NAT-REJ-2 报错共用这一判断。
     */
    public boolean capOverflow(ImageResolver r) {
        if (!isImage() || capInsets == null || !r.usable(imageId)) {
            return false;
        }
        double[] size = r.logicalSize(imageId);
        return size != null && !NinePatch.fits(capInsets, size[0], size[1]);
    }

    /** R-VAL-2/3/4/8 的原生防御性校验，全部对规范化后的整数执行 */
    private void validate() throws InvalidMarkerException {
        SpecReader.require(fontSize > 0, "fontSize 规范化后必须大于 0");
        SpecReader.require(fontWeight == 400 || fontWeight == 500 || fontWeight == 600
                || fontWeight == 700, "fontWeight 只允许 400/500/600/700");
        SpecReader.require("left".equals(textAlign) || "center".equals(textAlign)
                || "right".equals(textAlign), "textAlign 只允许 left/center/right");
        SpecReader.require(bgType != BG_CIRCLE || diameter > 0, "diameter 规范化后必须大于 0");
        SpecReader.require(bgType != BG_CIRCLE || (width == null && height == null),
                "圆形背景不允许设置 width/height");
        nonNeg("padding", padding);
        nonNeg("size", imageSize);
        nonNeg("capInsets", capInsets);
        nonNeg("尺寸", width, height, minWidth, maxWidth, cornerRadius, borderWidth,
                arrowWidth, arrowHeight, shadowBlur);
        SpecReader.require(minWidth == null || maxWidth == null || minWidth <= maxWidth,
                "minWidth 不能大于 maxWidth");
        SpecReader.require(width == null || ((minWidth == null || width >= minWidth)
                && (maxWidth == null || width <= maxWidth)), "width 必须落在 minWidth 与 maxWidth 之间");
        SpecReader.require(!hasArrow || bgType != BG_IMAGE || arrowColor != null,
                "图片背景下箭头必须指定颜色");
        // D-1：形状背景的箭头与主体是同一条路径，颜色只能为空或等于 fillColor
        SpecReader.require(!hasArrow || bgType == BG_IMAGE || arrowColor == null
                || arrowColor == fillColor, "形状背景的 arrow.color 只能为空或等于 fillColor");
    }

    private static void nonNeg(String what, int[] vs) throws InvalidMarkerException {
        if (vs != null) {
            for (int v : vs) {
                SpecReader.require(v >= 0, what + " 不能为负");
            }
        }
    }

    private static void nonNeg(String what, Integer... vs) throws InvalidMarkerException {
        for (Integer v : vs) {
            SpecReader.require(v == null || v >= 0, what + " 不能为负");
        }
    }

    /** 渲染 key 片段（R-KEY-1/3）：只写规范化后的整数与字符串，字段顺序固定 */
    void appendKey(KeyWriter k) {
        k.i(bgType).i(diameter).i(fillColor).i(cornerRadius).n(borderColor).i(borderWidth)
                .s(imageId).a(imageSize).a(capInsets)
                .i(fontSize).i(fontWeight).i(textColor).s(textAlign).a(padding)
                .n(width).n(height).n(minWidth).n(maxWidth)
                .b(hasArrow).i(arrowWidth).i(arrowHeight).n(arrowColor)
                .b(hasShadow).i(shadowColor).i(shadowBlur).i(shadowDx).i(shadowDy);
    }
}
