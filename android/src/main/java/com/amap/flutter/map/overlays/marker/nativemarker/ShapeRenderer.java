package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.concurrent.CancellationException;

/**
 * 形状点位的绘制算法（§9.3）：只读 NormSpec 与布局，产出对 DrawSurface 的调用序列。
 * 不依赖 android.*，同样输入必然得到同样调用序列（T-KEY-4）。
 */
public final class ShapeRenderer {
    /** R-RES-6 默认背景：白色、圆角 4、1 像素 0x1F000000 描边 */
    static final int FALLBACK_FILL = 0xFFFFFFFF;
    static final int FALLBACK_BORDER = 0x1F000000;
    static final double FALLBACK_RADIUS = 4;
    /** D-2：描边 1 物理像素，换算为逻辑像素即 1/density */
    static double fallbackBorderWidth(double density) {
        return 1 / density;
    }

    private ShapeRenderer() {
    }

    /** 纯形状点位（无图片、无图标），测试用 */
    public static void render(NativeMarkerSpec spec, NativeMarkerLayout layout, boolean selected,
                              TextMeasurer m, DrawSurface s, Cancelable c) {
        render(spec, layout, selected, m, null, s, c);
    }

    /** images 提供解码结果；图片背景（非降级）或显示图标时必须非空 */
    public static void render(NativeMarkerSpec spec, NativeMarkerLayout layout, boolean selected,
                              TextMeasurer m, ImageSet images, DrawSurface s, Cancelable c) {
        layout.requireWithinLimit(); // D-8
        StateLayout st = layout.state(selected);
        NormStyle style = selected ? spec.selectedOrNormal() : spec.normal;
        // 状态内锚点对齐到画布原点：状态局部坐标 + (-anchor)（R-GEO-1）
        double ox = -st.anchorX;
        double oy = -st.anchorY;
        s.setOrigin(layout.px, layout.py);
        if (style.isImage() && !st.fallbackBackground) {
            ImageDrawing.background(style, st, ox, oy, layout.density, images, s, c);
        } else {
            drawBackground(style, st, ox, oy, layout.density, s, c);
        }
        check(c);
        drawContent(spec, style, st, ox, oy, m, images, s);
    }

    private static void drawBackground(NormStyle style, StateLayout st, double ox, double oy,
                                       double density, DrawSurface s, Cancelable c) {
        boolean fallback = style.isImage();
        int fill = fallback ? FALLBACK_FILL : style.fillColor;
        Integer borderColor = fallback ? Integer.valueOf(FALLBACK_BORDER) : style.borderColor;
        double bw = fallback ? fallbackBorderWidth(density) : Norm.length(style.borderWidth);
        double w = st.body.width();
        double h = st.body.height();
        double r = style.bgType == NormStyle.BG_CIRCLE ? w / 2
                : OutlineBuilder.radius(w, h, fallback ? FALLBACK_RADIUS
                : Norm.length(style.cornerRadius));
        // 描边居中：路径向内缩半个线宽，描边不超出可见范围
        double inset = borderColor != null && bw > 0 ? bw / 2 : 0;
        RectD body = st.body.offset(ox, oy).expand(-inset, -inset);
        double rr = Math.max(0, r - inset);
        double tipX = st.arrowTipX + ox;
        double tipY = Math.max(body.bottom, st.arrowTipY + oy - inset);
        double arrowW = style.hasArrow ? Norm.length(style.arrowWidth) : 0;

        // 箭头始终与主体合成一条连续路径（D-1：形状背景的箭头颜色只能等于填充色）；
        // 降级背景同样合并，图片背景自带箭头三角形留给 S11
        Outline path = style.hasArrow
                ? OutlineBuilder.withArrow(body, rr, tipX, tipY, arrowW)
                : OutlineBuilder.body(body, rr);
        check(c);
        if (style.hasShadow) {
            s.fillWithShadow(path, fill, style.shadowColor, Norm.length(style.shadowBlur),
                    Norm.length(style.shadowDx), Norm.length(style.shadowDy));
        } else {
            s.fill(path, fill);
        }
        if (inset > 0) {
            check(c);
            s.stroke(path, borderColor, bw);
        }
    }

    /**
     * 内容 = 图标 + 间距 + 文字，整体在内容区内按 textAlign 水平对齐、垂直居中；
     * 文字宽度用与布局相同的测量器（R-NORM-4）。
     */
    private static void drawContent(NativeMarkerSpec spec, NormStyle style, StateLayout st,
                                    double ox, double oy, TextMeasurer m, ImageSet images,
                                    DrawSurface s) {
        boolean hasText = !st.displayText.isEmpty();
        if (!hasText && !st.showIcon) {
            return;
        }
        double padL = Norm.length(style.padding[0]);
        double padT = Norm.length(style.padding[1]);
        double padR = Norm.length(style.padding[2]);
        double padB = Norm.length(style.padding[3]);
        double font = Norm.length(style.fontSize);
        double avail = st.body.width() - padL - padR;
        double tw = hasText ? m.width(st.displayText, font, style.fontWeight) : 0;
        double iconW = st.showIcon ? st.iconWidth : 0;
        double gap = st.showIcon && hasText ? Norm.length(spec.iconSpacing) : 0;
        double cw = iconW + gap + tw;
        double x = st.body.left + ox + padL;
        if ("center".equals(style.textAlign)) {
            x += (avail - cw) / 2;
        } else if ("right".equals(style.textAlign)) {
            x += avail - cw;
        }
        double centerY = st.body.top + oy + padT + (st.body.height() - padT - padB) / 2;
        if (st.showIcon) {
            // 图标固定在文字前方，与文字共用垂直中线
            DecodedImage icon = images == null ? null : images.image(spec.iconId);
            if (icon == null) {
                throw new IllegalStateException("图标资源不可用: " + spec.iconId);
            }
            double top = centerY - st.iconHeight / 2;
            s.image(icon, NinePatch.whole(icon.width(), icon.height(),
                    new RectD(x, top, x + iconW, top + st.iconHeight)));
        }
        if (hasText) {
            s.text(st.displayText, x + iconW + gap, centerY, font, style.fontWeight,
                    style.textColor);
        }
    }

    static void check(Cancelable c) {
        if (c != null && c.isCancelled()) {
            throw new CancellationException("绘制已取消");
        }
    }
}
