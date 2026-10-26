package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** 记录型画布与测量器替身：把每次调用写成一行文本，供 T-KEY-4 比较 */
final class RecordingSurface implements DrawSurface {
    final List<String> calls = new ArrayList<>();
    final List<Outline> paths = new ArrayList<>();

    @Override
    public void setOrigin(int px, int py) {
        calls.add("origin " + px + "," + py);
    }

    @Override
    public void fill(Outline p, int color) {
        paths.add(p);
        calls.add(String.format(Locale.ROOT, "fill %08x %s", color, p));
    }

    @Override
    public void fillWithShadow(Outline p, int color, int sc, double blur, double dx, double dy) {
        paths.add(p);
        calls.add(String.format(Locale.ROOT, "fillShadow %08x %08x b=%.4f d=%.4f,%.4f %s",
                color, sc, blur, dx, dy, p));
    }

    @Override
    public void stroke(Outline p, int color, double width) {
        calls.add(String.format(Locale.ROOT, "stroke %08x w=%.4f %s", color, width, p));
    }

    @Override
    public void text(String t, double x, double cy, double font, int weight, int color) {
        calls.add(String.format(Locale.ROOT, "text '%s' x=%.4f cy=%.4f f=%.4f w=%d %08x",
                t, x, cy, font, weight, color));
    }

    /** 记录每次测量的输入 */
    static final class Measurer implements TextMeasurer {
        final TextMeasurer inner = Fixtures.measurer();
        final List<String> inputs = new ArrayList<>();

        @Override
        public double width(String text, double fontSize, int fontWeight) {
            inputs.add(String.format(Locale.ROOT, "w '%s' %.6f %d", text, fontSize, fontWeight));
            return inner.width(text, fontSize, fontWeight);
        }

        @Override
        public double lineHeight(double fontSize, int fontWeight) {
            inputs.add(String.format(Locale.ROOT, "h %.6f %d", fontSize, fontWeight));
            return inner.lineHeight(fontSize, fontWeight);
        }
    }
}
