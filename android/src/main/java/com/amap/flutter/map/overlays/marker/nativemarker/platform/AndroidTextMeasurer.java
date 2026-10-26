package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Paint;

import com.amap.flutter.map.overlays.marker.nativemarker.TextMeasurer;

/**
 * 文字测量（R-NORM-4）：按密度放大字号测量再除回，减少亚像素取整误差。
 * Paint 非线程安全，每次绘制任务创建一个实例。
 */
final class AndroidTextMeasurer implements TextMeasurer {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
    private final double density;

    AndroidTextMeasurer(double density) {
        this.density = density;
    }

    private void configure(double fontSize, int weight) {
        paint.setTypeface(AndroidFonts.typeface(weight));
        paint.setTextSize((float) (fontSize * density));
    }

    @Override
    public double width(String text, double fontSize, int fontWeight) {
        configure(fontSize, fontWeight);
        return paint.measureText(text) / density;
    }

    @Override
    public double lineHeight(double fontSize, int fontWeight) {
        configure(fontSize, fontWeight);
        Paint.FontMetrics m = paint.getFontMetrics();
        return (m.descent - m.ascent) / density;
    }
}
