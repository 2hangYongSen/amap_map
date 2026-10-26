package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 只关心一个探测点的“画布”：按绘制顺序记录覆盖探测点的最后一种颜色（后画覆盖先画）。
 * 填充按路径包围盒判断，图片按切片目标框判断并取 FakeImages.IMAGE_COLOR；文字、阴影不计。
 * 用于 T-RES-10 的“setIcon 位图中心像素”断言，绘制走真实 ShapeRenderer。
 */
final class CenterPixelSurface implements DrawSurface {
    private final double probeX;
    private final double probeY;
    int color = 0;
    /** 是否画了文字（T-RES-6：降级时保留文字） */
    boolean drewText = false;

    CenterPixelSurface(double probeX, double probeY) {
        this.probeX = probeX;
        this.probeY = probeY;
    }

    /** 绘制 job，返回记录了主体中心像素的画布 */
    static CenterPixelSurface paint(PaintJob job) {
        TextMeasurer m = Fixtures.measurer();
        NativeMarkerLayout l = NativeMarkerLayout.compute(job.spec, job.densityUnits, m, job);
        StateLayout st = l.state(job.selected);
        double cx = (st.body.left + st.body.right) / 2 - st.anchorX;
        double cy = (st.body.top + st.body.bottom) / 2 - st.anchorY;
        CenterPixelSurface s = new CenterPixelSurface(cx, cy);
        ShapeRenderer.render(job.spec, l, job.selected, m, job, s, job);
        return s;
    }

    private boolean covers(double l, double t, double r, double b) {
        return probeX >= l && probeX <= r && probeY >= t && probeY <= b;
    }

    private void fillPath(Outline p, int c) {
        final double[] box = {Double.MAX_VALUE, Double.MAX_VALUE, -Double.MAX_VALUE, -Double.MAX_VALUE};
        p.accept(new Outline.Visitor() {
            private void pt(float x, float y) {
                box[0] = Math.min(box[0], x);
                box[1] = Math.min(box[1], y);
                box[2] = Math.max(box[2], x);
                box[3] = Math.max(box[3], y);
            }
            @Override public void move(float x, float y) { pt(x, y); }
            @Override public void line(float x, float y) { pt(x, y); }
            @Override public void cubic(float a, float b, float c2, float d, float e, float f) { pt(e, f); }
            @Override public void close() { }
        });
        if (covers(box[0], box[1], box[2], box[3])) {
            color = c;
        }
    }

    @Override public void setOrigin(int px, int py) { }
    @Override public void fill(Outline path, int c) { fillPath(path, c); }
    @Override public void fillWithShadow(Outline path, int c, int sc, double b, double dx, double dy) {
        fillPath(path, c);
    }
    @Override public void stroke(Outline path, int c, double width) { }
    @Override public void text(String t, double x, double cy, double f, int w, int c) {
        drewText = true;
    }

    @Override
    public void image(DecodedImage img, double[][] slices) {
        for (double[] s : slices) {
            if (covers(s[4], s[5], s[6], s[7])) {
                color = FakeImages.IMAGE_COLOR;
            }
        }
    }

    @Override
    public void imageShadow(DecodedImage img, double[][] slices, RectD b, ShadowSpec s) { }
}
