package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Arrays;

/**
 * 与平台无关的路径数据（像素坐标）。由 OutlineBuilder 生成，AndroidSurface 转成 android.graphics.Path。
 * 只含 move / line / cubic / close 四种操作。
 */
public final class Outline {
    /** 逐段回放 */
    public interface Visitor {
        void move(float x, float y);

        void line(float x, float y);

        void cubic(float x1, float y1, float x2, float y2, float x3, float y3);

        void close();
    }

    private static final int MOVE = 0;
    private static final int LINE = 1;
    private static final int CUBIC = 2;
    private static final int CLOSE = 3;

    private int[] ops = new int[16];
    private float[] pts = new float[64];
    private int opCount = 0;
    private int ptCount = 0;

    Outline moveTo(double x, double y) {
        return add(MOVE, x, y);
    }

    Outline lineTo(double x, double y) {
        return add(LINE, x, y);
    }

    Outline cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
        return add(CUBIC, x1, y1, x2, y2, x3, y3);
    }

    Outline close() {
        return add(CLOSE);
    }

    private Outline add(int op, double... xy) {
        if (opCount == ops.length) {
            ops = Arrays.copyOf(ops, opCount * 2);
        }
        if (ptCount + xy.length > pts.length) {
            pts = Arrays.copyOf(pts, Math.max(pts.length * 2, ptCount + xy.length));
        }
        ops[opCount++] = op;
        for (double v : xy) {
            pts[ptCount++] = (float) v;
        }
        return this;
    }

    public void accept(Visitor v) {
        int p = 0;
        for (int i = 0; i < opCount; i++) {
            switch (ops[i]) {
                case MOVE:
                    v.move(pts[p], pts[p + 1]);
                    p += 2;
                    break;
                case LINE:
                    v.line(pts[p], pts[p + 1]);
                    p += 2;
                    break;
                case CUBIC:
                    v.cubic(pts[p], pts[p + 1], pts[p + 2], pts[p + 3], pts[p + 4], pts[p + 5]);
                    p += 6;
                    break;
                default:
                    v.close();
                    break;
            }
        }
    }

    /** 轮廓数量（move 的次数）；连续路径应恰好为 1 */
    public int contourCount() {
        int n = 0;
        for (int i = 0; i < opCount; i++) {
            if (ops[i] == MOVE) {
                n++;
            }
        }
        return n;
    }

    /** 稳定的文本形式，供记录型画布与测试比较 */
    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        accept(new Visitor() {
            @Override public void move(float x, float y) { sb.append(String.format("M%.3f,%.3f ", x, y)); }
            @Override public void line(float x, float y) { sb.append(String.format("L%.3f,%.3f ", x, y)); }
            @Override public void cubic(float a, float b, float c, float d, float e, float f) {
                sb.append(String.format("C%.3f,%.3f,%.3f,%.3f,%.3f,%.3f ", a, b, c, d, e, f));
            }
            @Override public void close() { sb.append("Z "); }
        });
        return sb.toString().trim();
    }
}
