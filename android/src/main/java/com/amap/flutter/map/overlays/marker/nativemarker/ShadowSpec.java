package com.amap.flutter.map.overlays.marker.nativemarker;

/** 单层阴影参数（逻辑像素），交给 DrawSurface 的图片绘制使用 */
public final class ShadowSpec {
    public final int color;
    public final double blur;
    public final double dx;
    public final double dy;

    public ShadowSpec(int color, double blur, double dx, double dy) {
        this.color = color;
        this.blur = blur;
        this.dx = dx;
        this.dy = dy;
    }

    /** 样式没有阴影时返回 null */
    static ShadowSpec of(NormStyle s) {
        return s.hasShadow ? new ShadowSpec(s.shadowColor, Norm.length(s.shadowBlur),
                Norm.length(s.shadowDx), Norm.length(s.shadowDy)) : null;
    }
}
