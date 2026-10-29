package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Bitmap;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;

import com.amap.flutter.map.overlays.marker.nativemarker.DecodedImage;
import com.amap.flutter.map.overlays.marker.nativemarker.DrawSurface;
import com.amap.flutter.map.overlays.marker.nativemarker.Outline;
import com.amap.flutter.map.overlays.marker.nativemarker.RectD;
import com.amap.flutter.map.overlays.marker.nativemarker.ShadowSpec;

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

    @Override
    public void image(DecodedImage img, double[][] slices) {
        paint.reset();
        paint.setFilterBitmap(true); // 拉伸时双线性过滤
        drawSlices(canvas, ((BitmapImage) img).bitmap, slices, 0, 0, density);
    }

    /** E-A5：drawBitmap + setShadowLayer 阴影色不对，改用 extractAlpha 遮罩 + BlurMaskFilter */
    @Override
    public void imageShadow(DecodedImage img, double[][] slices, RectD b, ShadowSpec sh) {
        int w = Math.max(1, (int) Math.ceil(b.width() * density));
        int h = Math.max(1, (int) Math.ceil(b.height() * density));
        Bitmap tmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Bitmap mask = null;
        try {
            paint.reset();
            paint.setFilterBitmap(true);
            // 先把背景（九宫格先合成）画到与主体同尺寸的临时位图
            drawSlices(new Canvas(tmp), ((BitmapImage) img).bitmap, slices, b.left, b.top, density);
            mask = tmp.extractAlpha();
            reset(Paint.Style.FILL, sh.color);
            if (sh.blur > 0) {
                paint.setMaskFilter(new BlurMaskFilter((float) sh.blur * density,
                        BlurMaskFilter.Blur.NORMAL));
            }
            canvas.drawBitmap(mask, (float) (b.left + sh.dx) * density,
                    (float) (b.top + sh.dy) * density, paint);
        } finally {
            tmp.recycle();
            if (mask != null) {
                mask.recycle();
            }
        }
    }

    /** 切片 dst 以 (originX, originY) 为原点换算成物理像素 */
    private void drawSlices(Canvas c, Bitmap src, double[][] slices, double originX,
                            double originY, float d) {
        for (double[] s : slices) {
            Rect from = new Rect((int) s[0], (int) s[1], (int) s[2], (int) s[3]);
            RectF to = new RectF((float) ((s[4] - originX) * d), (float) ((s[5] - originY) * d),
                    (float) ((s[6] - originX) * d), (float) ((s[7] - originY) * d));
            c.drawBitmap(src, from, to, paint);
        }
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
