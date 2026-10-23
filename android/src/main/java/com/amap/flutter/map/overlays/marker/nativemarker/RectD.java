package com.amap.flutter.map.overlays.marker.nativemarker;

/** 不可变矩形（逻辑像素，x 向右、y 向下）。纯计算，不依赖 android.graphics。 */
public final class RectD {
    public final double left;
    public final double top;
    public final double right;
    public final double bottom;

    public RectD(double left, double top, double right, double bottom) {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }

    public double width() {
        return right - left;
    }

    public double height() {
        return bottom - top;
    }

    public RectD union(RectD o) {
        return new RectD(Math.min(left, o.left), Math.min(top, o.top),
                Math.max(right, o.right), Math.max(bottom, o.bottom));
    }

    /** 左右各扩 dx，上下各扩 dy */
    public RectD expand(double dx, double dy) {
        return new RectD(left - dx, top - dy, right + dx, bottom + dy);
    }

    public RectD offset(double dx, double dy) {
        return new RectD(left + dx, top + dy, right + dx, bottom + dy);
    }

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof RectD)) {
            return false;
        }
        RectD r = (RectD) o;
        return left == r.left && top == r.top && right == r.right && bottom == r.bottom;
    }

    @Override
    public int hashCode() {
        return Double.hashCode(left) * 31 * 31 * 31 + Double.hashCode(top) * 31 * 31
                + Double.hashCode(right) * 31 + Double.hashCode(bottom);
    }

    @Override
    public String toString() {
        return "RectD(" + left + ", " + top + ", " + right + ", " + bottom + ")";
    }
}
