package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 单个状态的布局结果（§9.1 layoutState）。坐标以该状态自己的 visibleRect 左上角为原点。
 * 纯计算，只读 NormSpec 与测量器。
 */
public final class StateLayout {
    /** 主体框 */
    public final RectD body;
    /** 可见范围（主体 + 箭头 + 阴影扩边） */
    public final RectD visible;
    /** 状态内锚点 a */
    public final double anchorX;
    public final double anchorY;
    public final boolean hasArrow;
    /** 箭头尖端；底边两点为 (tipX ± arrowW/2, body.bottom) */
    public final double arrowTipX;
    public final double arrowTipY;
    /** 省略后的显示文字，空串表示不显示文字 */
    public final String displayText;
    public final boolean showIcon;
    public final double iconWidth;
    public final double iconHeight;
    /** 图片背景不可用，按 R-RES-6 用默认背景绘制 */
    public final boolean fallbackBackground;

    private StateLayout(RectD body, RectD visible, double ax, double ay, boolean hasArrow,
                        double tipX, double tipY, String text, boolean showIcon,
                        double iconW, double iconH, boolean fallback) {
        this.body = body;
        this.visible = visible;
        this.anchorX = ax;
        this.anchorY = ay;
        this.hasArrow = hasArrow;
        this.arrowTipX = tipX;
        this.arrowTipY = tipY;
        this.displayText = text;
        this.showIcon = showIcon;
        this.iconWidth = iconW;
        this.iconHeight = iconH;
        this.fallbackBackground = fallback;
    }

    /** 按 §9.1 计算一个状态 */
    static StateLayout compute(NativeMarkerSpec spec, NormStyle s, TextMeasurer m, ImageResolver r) {
        double font = Norm.length(s.fontSize);
        double[] pad = lengths(s.padding);
        // 1. 内容尺寸：图标（可用时）+ 间距 + 单行文字
        boolean showIcon = spec.iconId != null && r.usable(spec.iconId);
        double iconW = 0;
        double iconH = 0;
        if (showIcon) {
            double[] sz = spec.iconSize != null ? lengths(spec.iconSize) : r.logicalSize(spec.iconId);
            iconW = sz == null ? 0 : sz[0];
            iconH = sz == null ? 0 : sz[1];
        }
        boolean hasText = spec.text != null;
        double gap = showIcon && hasText ? Norm.length(spec.iconSpacing) : 0;
        double textW = hasText ? m.width(spec.text, font, s.fontWeight) : 0;
        double textH = hasText ? m.lineHeight(font, s.fontWeight) : 0;
        double contentW = iconW + gap + textW;
        double contentH = Math.max(iconH, textH);

        // 2. 主体尺寸
        boolean fallback = s.isImage() && !r.usable(s.imageId);
        double bw;
        double bh;
        if (s.bgType == NormStyle.BG_CIRCLE) {
            bw = bh = Norm.length(s.diameter);
        } else if (s.isImage() && s.imageSize != null) {
            // 固定尺寸；降级时也保持尺寸，避免布局跳动
            bw = Norm.length(s.imageSize[0]);
            bh = Norm.length(s.imageSize[1]);
        } else if (s.isImage() && s.capInsets == null && !fallback) {
            double[] sz = r.logicalSize(s.imageId);
            bw = sz == null ? 0 : sz[0];
            bh = sz == null ? 0 : sz[1];
        } else {
            // 圆角矩形规则（含九宫格与降级默认背景）
            bw = s.width != null ? Norm.length(s.width)
                    : clamp(contentW + pad[0] + pad[2], s.minWidth, s.maxWidth);
            bh = s.height != null ? Norm.length(s.height) : contentH + pad[1] + pad[3];
        }
        // R-ELL-1：可用文字宽
        double avail = bw - pad[0] - pad[2] - (iconW + gap);
        String text = hasText ? Ellipsizer.ellipsize(spec.text, avail, m, font, s.fontWeight) : "";

        // 3. 箭头：主体底部中点下方
        RectD body = new RectD(0, 0, bw, bh);
        double tipX = bw / 2;
        double tipY = bh + (s.hasArrow ? Norm.length(s.arrowHeight) : 0);
        RectD visible = body;
        if (s.hasArrow) {
            double half = Norm.length(s.arrowWidth) / 2;
            visible = visible.union(new RectD(tipX - half, bh, tipX + half, tipY));
        }
        // 4. 阴影扩边：只扩大可见范围，不移动主体
        if (s.hasShadow) {
            double blur = Norm.length(s.shadowBlur);
            visible = visible.expand(blur + Math.abs(Norm.length(s.shadowDx)),
                    blur + Math.abs(Norm.length(s.shadowDy)));
        }
        // 5. 状态内锚点
        double ax;
        double ay;
        if (spec.anchorType == NativeMarkerSpec.ANCHOR_CUSTOM) {
            ax = bw * Norm.ratio(spec.anchorDx);
            ay = bh * Norm.ratio(spec.anchorDy);
        } else if (spec.anchorType == NativeMarkerSpec.ANCHOR_ARROW_TIP) {
            // 无箭头时 tipY == bh，即主体底边中点（R-ANC-2）
            ax = tipX;
            ay = tipY;
        } else {
            ax = bw / 2;
            ay = bh / 2;
        }
        // 6. 平移到 visibleRect 左上角为原点
        double ox = -visible.left;
        double oy = -visible.top;
        return new StateLayout(body.offset(ox, oy), visible.offset(ox, oy), ax + ox, ay + oy,
                s.hasArrow, tipX + ox, tipY + oy, text, showIcon, iconW, iconH, fallback);
    }

    /** 平移 -a 后的可见范围（以地理锚点为原点，R-GEO-1） */
    RectD alignedVisible() {
        return visible.offset(-anchorX, -anchorY);
    }

    private static double clamp(double v, Integer min, Integer max) {
        if (min != null) {
            v = Math.max(v, Norm.length(min));
        }
        if (max != null) {
            v = Math.min(v, Norm.length(max));
        }
        return v;
    }

    private static double[] lengths(int[] units) {
        double[] out = new double[units.length];
        for (int i = 0; i < units.length; i++) {
            out[i] = Norm.length(units[i]);
        }
        return out;
    }
}
