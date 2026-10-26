package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 形状轮廓（§9.3）：圆角矩形与箭头合成一条顺时针闭合路径，一次填充、描边、投影，
 * 接缝处不会出现透明缝。纯计算，坐标为状态局部的逻辑像素。
 */
public final class OutlineBuilder {
    private static final double HALF_PI = Math.PI / 2;

    private OutlineBuilder() {
    }

    /** 圆角半径：圆形取短边一半，圆角矩形取配置值但不超过短边一半 */
    public static double radius(double w, double h, double cornerRadius) {
        return Math.max(0, Math.min(cornerRadius, Math.min(w, h) / 2));
    }

    /**
     * 带箭头的连续轮廓。箭头底边端点落在主体底部边界上（直边或圆角弧上），尖端在 (tipX, tipY)。
     * arrowW / arrowH 任一为 0 或 tipY 不在主体下方时，退化为纯主体轮廓。
     */
    public static Outline withArrow(RectD body, double r, double tipX, double tipY, double arrowW) {
        double w = body.width();
        double h = body.height();
        double half = arrowW / 2;
        if (half <= 0 || tipY <= body.bottom) {
            return body(body, r);
        }
        double x0 = body.left;
        double y0 = body.top;
        Outline o = new Outline();
        o.moveTo(x0 + r, y0);
        o.lineTo(x0 + w - r, y0);
        arc(o, x0 + w - r, y0 + r, r, 3 * HALF_PI, 4 * HALF_PI); // 右上角
        o.lineTo(x0 + w, y0 + h - r);
        // 右下角弧：画到箭头右侧底边点；底边点在直边上时画满整段弧再走直边
        double xr = Math.min(tipX + half, x0 + w);
        boolean rightOnArc = xr > x0 + w - r;
        double tr = rightOnArc ? Math.acos(clamp((xr - (x0 + w - r)) / r)) : HALF_PI;
        arc(o, x0 + w - r, y0 + h - r, r, 0, tr);
        if (!rightOnArc) {
            o.lineTo(xr, y0 + h);
        }
        o.lineTo(tipX, tipY);
        // 左侧底边点
        double xl = Math.max(tipX - half, x0);
        boolean leftOnArc = xl < x0 + r;
        double tl = leftOnArc ? Math.acos(clamp((xl - (x0 + r)) / r)) : HALF_PI;
        if (!leftOnArc) {
            o.lineTo(xl, y0 + h);
            o.lineTo(x0 + r, y0 + h);
        } else {
            o.lineTo(x0 + r + r * Math.cos(tl), y0 + h - r + r * Math.sin(tl));
        }
        arc(o, x0 + r, y0 + h - r, r, tl, 2 * HALF_PI); // 左下角
        o.lineTo(x0, y0 + r);
        arc(o, x0 + r, y0 + r, r, 2 * HALF_PI, 3 * HALF_PI); // 左上角
        return o.close();
    }

    /** 不含箭头的圆角矩形（圆形即 r = 半径） */
    public static Outline body(RectD b, double r) {
        double w = b.width();
        double h = b.height();
        Outline o = new Outline();
        o.moveTo(b.left + r, b.top);
        o.lineTo(b.left + w - r, b.top);
        arc(o, b.left + w - r, b.top + r, r, 3 * HALF_PI, 4 * HALF_PI);
        o.lineTo(b.left + w, b.top + h - r);
        arc(o, b.left + w - r, b.top + h - r, r, 0, HALF_PI);
        o.lineTo(b.left + r, b.top + h);
        arc(o, b.left + r, b.top + h - r, r, HALF_PI, 2 * HALF_PI);
        o.lineTo(b.left, b.top + r);
        arc(o, b.left + r, b.top + r, r, 2 * HALF_PI, 3 * HALF_PI);
        return o.close();
    }

    /** 单独的箭头三角形（图片背景或箭头异色时使用）；底边在 y = baseY */
    public static Outline triangle(double tipX, double tipY, double baseY, double arrowW) {
        double half = arrowW / 2;
        return new Outline().moveTo(tipX - half, baseY).lineTo(tipX + half, baseY)
                .lineTo(tipX, tipY).close();
    }

    /**
     * 从角度 a0 到 a1（弧度，屏幕坐标系顺时针为正）追加圆弧，每段不超过 90°，用三次贝塞尔近似。
     * 起点必须与当前点重合，所以这里只发出曲线，不再 lineTo。
     */
    private static void arc(Outline o, double cx, double cy, double r, double a0, double a1) {
        if (r <= 0 || a1 - a0 <= 1e-9) {
            return;
        }
        int n = (int) Math.ceil((a1 - a0) / HALF_PI - 1e-9);
        double step = (a1 - a0) / n;
        double k = 4.0 / 3.0 * Math.tan(step / 4);
        for (int i = 0; i < n; i++) {
            double s = a0 + i * step;
            double e = s + step;
            o.cubicTo(cx + r * (Math.cos(s) - k * Math.sin(s)), cy + r * (Math.sin(s) + k * Math.cos(s)),
                    cx + r * (Math.cos(e) + k * Math.sin(e)), cy + r * (Math.sin(e) - k * Math.cos(e)),
                    cx + r * Math.cos(e), cy + r * Math.sin(e));
        }
    }

    private static double clamp(double v) {
        return Math.max(-1, Math.min(1, v));
    }
}
