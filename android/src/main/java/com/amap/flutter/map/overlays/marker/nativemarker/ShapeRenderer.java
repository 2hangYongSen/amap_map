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
    static final double FALLBACK_BORDER_WIDTH = 1;

    private ShapeRenderer() {
    }

    public static void render(NativeMarkerSpec spec, NativeMarkerLayout layout, boolean selected,
                              TextMeasurer m, DrawSurface s, Cancelable c) {
        StateLayout st = layout.state(selected);
        NormStyle style = selected ? spec.selectedOrNormal() : spec.normal;
        if (style.isImage() && !st.fallbackBackground) {
            throw new IllegalStateException("图片背景绘制在 S11 实现");
        }
        if (st.showIcon) {
            throw new IllegalStateException("图标绘制在 S11 实现");
        }
        // 状态内锚点对齐到画布原点：状态局部坐标 + (-anchor)（R-GEO-1）
        double ox = -st.anchorX;
        double oy = -st.anchorY;
        s.setOrigin(layout.px, layout.py);
        drawBackground(style, st, ox, oy, s, c);
        check(c);
        if (!st.displayText.isEmpty()) {
            drawText(style, st, ox, oy, m, s);
        }
    }

    private static void drawBackground(NormStyle style, StateLayout st, double ox, double oy,
                                       DrawSurface s, Cancelable c) {
        boolean fallback = style.isImage();
        int fill = fallback ? FALLBACK_FILL : style.fillColor;
        Integer borderColor = fallback ? Integer.valueOf(FALLBACK_BORDER) : style.borderColor;
        double bw = fallback ? FALLBACK_BORDER_WIDTH : Norm.length(style.borderWidth);
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
        Integer arrowColor = style.hasArrow ? style.arrowColor : null;
        boolean sameColor = arrowColor == null || arrowColor == fill;
        double arrowW = style.hasArrow ? Norm.length(style.arrowWidth) : 0;

        // 同色箭头与主体合成一条连续路径；异色时箭头单独画三角形（§9.3）
        Outline path = style.hasArrow && sameColor
                ? OutlineBuilder.withArrow(body, rr, tipX, tipY, arrowW)
                : OutlineBuilder.body(body, rr);
        check(c);
        if (style.hasShadow) {
            s.fillWithShadow(path, fill, style.shadowColor, Norm.length(style.shadowBlur),
                    Norm.length(style.shadowDx), Norm.length(style.shadowDy));
        } else {
            s.fill(path, fill);
        }
        if (style.hasArrow && !sameColor) {
            s.fill(OutlineBuilder.triangle(tipX, tipY, body.bottom, arrowW), arrowColor);
        }
        if (inset > 0) {
            check(c);
            s.stroke(path, borderColor, bw);
        }
    }

    /** 文字在内容区垂直居中，水平按 textAlign 对齐；宽度用与布局相同的测量器（R-NORM-4） */
    private static void drawText(NormStyle style, StateLayout st, double ox, double oy,
                                 TextMeasurer m, DrawSurface s) {
        double padL = Norm.length(style.padding[0]);
        double padT = Norm.length(style.padding[1]);
        double padR = Norm.length(style.padding[2]);
        double padB = Norm.length(style.padding[3]);
        double font = Norm.length(style.fontSize);
        double avail = st.body.width() - padL - padR;
        double tw = m.width(st.displayText, font, style.fontWeight);
        double x = st.body.left + ox + padL;
        if ("center".equals(style.textAlign)) {
            x += (avail - tw) / 2;
        } else if ("right".equals(style.textAlign)) {
            x += avail - tw;
        }
        double centerY = st.body.top + oy + padT + (st.body.height() - padT - padB) / 2;
        s.text(st.displayText, x, centerY, font, style.fontWeight, style.textColor);
    }

    private static void check(Cancelable c) {
        if (c != null && c.isCancelled()) {
            throw new CancellationException("绘制已取消");
        }
    }
}
