package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * R-NORM-2 舍入：长度按 1/64、比例按 1/1024，远离零的四舍五入。
 * 与 Dart normalize.dart、共享夹具 normalization 部分一致（T-NORM-1）。
 */
public final class Norm {
    public static final int LENGTH_SCALE = 64;
    public static final int RATIO_SCALE = 1024;

    private Norm() {
    }

    /** 长度 → 整数单位（1/64 逻辑像素） */
    public static int lengthUnits(double v) throws InvalidMarkerException {
        return toUnits(v, LENGTH_SCALE);
    }

    /** 锚点比例 / 像素比 / 密度 → 整数单位（1/1024） */
    public static int ratioUnits(double v) throws InvalidMarkerException {
        return toUnits(v, RATIO_SCALE);
    }

    /** 整数单位还原为长度（1/64 是二进制精确值，无误差） */
    public static double length(int units) {
        return units / (double) LENGTH_SCALE;
    }

    public static double ratio(int units) {
        return units / (double) RATIO_SCALE;
    }

    /**
     * 远离零的四舍五入。不用 Math.round（负数一半时朝 +∞）；
     * 也不用 floor(x + 0.5)（0.49999999999999994 会被错误进位）。
     */
    static long roundHalfAwayFromZero(double x) {
        double a = Math.abs(x);
        double f = Math.floor(a);
        // a - f 对 double 是精确减法
        long r = (long) f + (a - f >= 0.5 ? 1 : 0);
        return x < 0 ? -r : r;
    }

    private static int toUnits(double v, int scale) throws InvalidMarkerException {
        double scaled = v * scale;
        if (Double.isNaN(v) || Double.isInfinite(v) || Double.isInfinite(scaled)) {
            throw new InvalidMarkerException("数值必须有限: " + v);
        }
        long r = roundHalfAwayFromZero(scaled);
        // 超出 int 的长度已远超任何可绘制范围，按非法配置处理
        if (r > Integer.MAX_VALUE || r < Integer.MIN_VALUE) {
            throw new InvalidMarkerException("数值过大，无法规范化: " + v);
        }
        return (int) r;
    }
}
