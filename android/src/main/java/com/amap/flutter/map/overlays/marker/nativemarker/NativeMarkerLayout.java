package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 两态共用画布（§9.2）：先按锚点对齐再求并集（R-GEO-1），再像素化（R-GEO-2）。
 * 纯计算；绘制时把画布原点平移到 (px, py)，再按各状态的 -a 绘制。
 */
public final class NativeMarkerLayout {
    /** 抵消 1/64 × 密度乘法的浮点噪声，三端夹具使用同一容差 */
    static final double CEIL_EPS = 1e-9;

    public final StateLayout normal;
    /** 未设置选中态时与 normal 为同一对象（R-GEO-3） */
    public final StateLayout selected;
    /** 以地理锚点为原点的并集 U（逻辑像素） */
    public final RectD union;
    public final double density;
    /** 锚点在画布中的整数像素位置 */
    public final int px;
    public final int py;
    /** 画布像素尺寸，均 ≥ 1 */
    public final int width;
    public final int height;

    private NativeMarkerLayout(StateLayout n, StateLayout s, RectD u, double d,
                               int[] pixels) {
        this.normal = n;
        this.selected = s;
        this.union = u;
        this.density = d;
        this.px = pixels[0];
        this.py = pixels[1];
        this.width = pixels[2];
        this.height = pixels[3];
    }

    /**
     * 计算两态布局与共用画布。
     * @param densityUnits 设备密度的 1/1024 单位（与渲染 key 同源）
     */
    public static NativeMarkerLayout compute(NativeMarkerSpec spec, int densityUnits,
                                             TextMeasurer m, ImageResolver r) {
        StateLayout n = StateLayout.compute(spec, spec.normal, m, r);
        StateLayout s = spec.selected == null ? n : StateLayout.compute(spec, spec.selected, m, r);
        RectD u = n.alignedVisible().union(s.alignedVisible());
        double d = Norm.ratio(densityUnits);
        return new NativeMarkerLayout(n, s, u, d, pixelize(u, d));
    }

    /** R-GEO-2：先定锚点像素，再定画布；返回 {px, py, W, H} */
    public static int[] pixelize(RectD u, double d) {
        int px = ceil(-u.left * d);
        int py = ceil(-u.top * d);
        int w = Math.max(1, px + ceil(u.right * d));
        int h = Math.max(1, py + ceil(u.bottom * d));
        return new int[]{px, py, w, h};
    }

    /** D-8：合成位图任一边超过该物理像素数即不绘制 */
    public static final int MAX_CANVAS_PX = 2048;

    public boolean withinLimit() {
        return width <= MAX_CANVAS_PX && height <= MAX_CANVAS_PX;
    }

    /** D-8：超限时抛异常，不裁剪；调度器把它报成 renderFailed */
    public void requireWithinLimit() {
        if (!withinLimit()) {
            throw new IllegalStateException("合成位图 " + width + "x" + height
                    + " 超过上限 " + MAX_CANVAS_PX + " 物理像素");
        }
    }

    /** SDK 锚点 u（两态共用画布，天然相同） */
    public float anchorU() {
        return px / (float) width;
    }

    public float anchorV() {
        return py / (float) height;
    }

    public StateLayout state(boolean selectedRole) {
        return selectedRole ? selected : normal;
    }

    static int ceil(double v) {
        return (int) Math.ceil(v - CEIL_EPS);
    }
}
