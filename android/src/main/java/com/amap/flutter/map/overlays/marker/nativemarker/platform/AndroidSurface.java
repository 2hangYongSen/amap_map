package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;

import com.amap.flutter.map.overlays.marker.nativemarker.DrawSurface;
import com.amap.flutter.map.overlays.marker.nativemarker.Outline;

/**
 * DrawSurface 的 Canvas 实现：逻辑坐标乘密度后落到物理像素。
 * 画布是 Bitmap 软件画布，setShadowLayer 的行为按 E-A5 验证过；阴影参数需自行乘密度。
 */
final class AndroidSurface implements DrawSurface {
    private final Canvas canvas;
    private final float density;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Matrix scale = new Matrix();

    AndroidSurface(Canvas canvas, double density) {
        this.canvas = canvas;
        this.density = (float) density;
        scale.setScale(this.density, this.density);
    }

    @Override
    public void setOrigin(int px, int py) {
        canvas.translate(px, py);
    }

    @Override
    public void fill(Outline outline, int color) {
        reset(Paint.Style.FILL, color);
        canvas.drawPath(toPath(outline), paint);
    }

    @Override
    public void fillWithShadow(Outline outline, int color, int shadowColor, double blur,
                               double dx, double dy) {
        reset(Paint.Style.FILL, color);
        paint.setShadowLayer((float) blur * density, (float) dx * density, (float) dy * density,
                shadowColor);
        canvas.drawPath(toPath(outline), paint);
        paint.clearShadowLayer();
    }

    @Override
    public void stroke(Outline outline, int color, double width) {
        reset(Paint.Style.STROKE, color);
        paint.setStrokeWidth((float) width * density);
        paint.setStrokeJoin(Paint.Join.ROUND);
        canvas.drawPath(toPath(outline), paint);
    }

    @Override
    public void text(String text, double x, double centerY, double fontSize, int fontWeight,
                     int color) {
        reset(Paint.Style.FILL, color);
        paint.setSubpixelText(true);
        paint.setTypeface(AndroidFonts.typeface(fontWeight));
        paint.setTextSize((float) fontSize * density);
        Paint.FontMetrics m = paint.getFontMetrics();
        // 行高 = descent − ascent，中线对齐 centerY
        float baseline = (float) centerY * density - (m.ascent + m.descent) / 2;
        canvas.drawText(text, (float) x * density, baseline, paint);
    }

    private void reset(Paint.Style style, int color) {
        paint.reset();
        paint.setAntiAlias(true);
        paint.setStyle(style);
        paint.setColor(color);
    }

    private Path toPath(Outline outline) {
        final Path path = new Path();
        outline.accept(new Outline.Visitor() {
            @Override public void move(float x, float y) { path.moveTo(x, y); }
            @Override public void line(float x, float y) { path.lineTo(x, y); }
            @Override public void cubic(float a, float b, float c, float d, float e, float f) {
                path.cubicTo(a, b, c, d, e, f);
            }
            @Override public void close() { path.close(); }
        });
        path.transform(scale);
        return path;
    }
}
