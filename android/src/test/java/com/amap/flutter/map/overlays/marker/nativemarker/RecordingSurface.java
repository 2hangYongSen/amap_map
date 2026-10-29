package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 记录型画布与测量器替身：把每次调用写成一行文本，供 T-KEY-4 比较。
 * 浮点一律用 %a（十六进制，逐位精确），不做十进制舍入，避免掩盖微小差异。
 */
final class RecordingSurface implements DrawSurface {
    final List<String> calls = new ArrayList<>();
    final List<Outline> paths = new ArrayList<>();
    /** 结构化记录：便于按数值断言 */
    final List<double[]> texts = new ArrayList<>();
    final List<Double> strokeWidths = new ArrayList<>();

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
        calls.add(String.format(Locale.ROOT, "fillShadow %08x %08x b=%a d=%a,%a %s",
                color, sc, blur, dx, dy, p));
    }

    @Override
    public void stroke(Outline p, int color, double width) {
        paths.add(p);
        strokeWidths.add(width);
        calls.add(String.format(Locale.ROOT, "stroke %08x w=%a %s", color, width, p));
    }

    @Override
    public void text(String t, double x, double cy, double font, int weight, int color) {
        texts.add(new double[]{x, cy});
        calls.add(String.format(Locale.ROOT, "text '%s' x=%a cy=%a f=%a w=%d %08x",
                t, x, cy, font, weight, color));
    }

    /** 图片调用：每项为切片数组 */
    final List<double[][]> images = new ArrayList<>();

    @Override
    public void image(DecodedImage img, double[][] slices) {
        images.add(slices);
        calls.add("image " + img + " " + slices(slices));
    }

    @Override
    public void imageShadow(DecodedImage img, double[][] slices, RectD b, ShadowSpec s) {
        calls.add(String.format(Locale.ROOT, "imageShadow %s %08x b=%a d=%a,%a bounds=%a,%a,%a,%a %s",
                img, s.color, s.blur, s.dx, s.dy, b.left, b.top, b.right, b.bottom, slices(slices)));
    }

    private static String slices(double[][] ss) {
        StringBuilder sb = new StringBuilder();
        for (double[] s : ss) {
            sb.append(String.format(Locale.ROOT, "[%a,%a,%a,%a>%a,%a,%a,%a]",
                    s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]));
        }
        return sb.toString();
    }

    /** 记录每次测量的输入 */
    static final class Measurer implements TextMeasurer {
        final TextMeasurer inner = Fixtures.measurer();
        final List<String> inputs = new ArrayList<>();

        @Override
        public double width(String text, double fontSize, int fontWeight) {
            inputs.add(String.format(Locale.ROOT, "w '%s' %a %d", text, fontSize, fontWeight));
            return inner.width(text, fontSize, fontWeight);
        }

        @Override
        public double lineHeight(double fontSize, int fontWeight) {
            inputs.add(String.format(Locale.ROOT, "h %a %d", fontSize, fontWeight));
            return inner.lineHeight(fontSize, fontWeight);
        }
    }
}
