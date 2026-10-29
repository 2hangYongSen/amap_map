package com.amap.flutter.amap_map_example.experiments;

import android.graphics.Bitmap;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;

import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.MarkerOptions;

/**
 * E-A5：软件画布（Bitmap 背后的 Canvas，无硬件加速）上 setShadowLayer 的效果。
 * 变体：
 *  1 drawPath（圆角矩形+箭头的连续路径）+ setShadowLayer
 *  2 drawBitmap（不透明矩形图）+ setShadowLayer
 *  3 drawBitmap（带透明的圆形 PNG）+ setShadowLayer
 *  4 九宫格方式（9 次 drawBitmap 各自带阴影）
 *  5 备选：先用 extractAlpha + BlurMaskFilter 画阴影，再画原图（图片背景的保底方案）
 * 每个变体导出 PNG，并统计主体外的阴影像素（alpha&gt;8 的个数、最大 alpha、偏移方向），
 * 然后贴到地图上截图。
 */
class ExpA5 extends Experiment {
    private float d;
    private static final float BLUR = 6, DX = 0, DY = 3; // dp
    private static final int SHADOW = 0x66000000;

    @Override
    void start() {
        d = h.density();
        Bitmap[] out = {variantPath(), variantBitmap(opaque(), 0xFFFFFFFF), variantBitmap(round(), 0xFFFFFFFF),
                variantNine(0xFFFFFFFF), variantMaskFilter(round()),
                variantBitmap(round(), 0xFF000000), variantNine(0xFF000000), variantNineThenShadow()};
        String[] names = {"1_path", "2_bitmap_opaque", "3_bitmap_alpha", "4_ninepatch", "5_maskfilter_alpha",
                "6_bitmap_alpha_blackPaint", "7_ninepatch_blackPaint", "8_ninepatch_composeThenShadow"};
        for (int i = 0; i < out.length; i++) {
            h.savePng(out[i], "A5_" + names[i] + ".png");
            result(names[i], measure(out[i]));
        }
        // 贴到地图上看实际效果（浅色底图上）
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        for (int i = 0; i < out.length; i++) {
            LatLng ll = h.fromScreen(w / 4 + (i % 2) * w / 2, ht / 8 + (i / 2) * ht / 5);
            h.amap.addMarker(new MarkerOptions().position(ll).anchor(0.5f, 0.5f)
                    .icon(BitmapDescriptorFactory.fromBitmap(out[i])).infoWindowEnable(false));
        }
        waitDraw(5, 3, 3000, () -> {
            h.savePng(h.frame(), "A5_on_map.png");
            done();
        });
    }

    /** 画布：主体 80×40dp，四周留 16dp 给阴影，底部再留 8dp 给箭头。 */
    private Bitmap canvasBitmap() {
        return Bitmap.createBitmap(Math.round(112 * d), Math.round(80 * d), Bitmap.Config.ARGB_8888);
    }

    private RectF body() {
        return new RectF(16 * d, 16 * d, 96 * d, 56 * d);
    }

    private Paint shadowPaint(int fill) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        p.setColor(fill);
        p.setShadowLayer(BLUR * d, DX * d, DY * d, SHADOW);
        return p;
    }

    private Bitmap variantPath() {
        Bitmap b = canvasBitmap();
        Canvas c = new Canvas(b);
        RectF r = body();
        Path path = new Path();
        path.addRoundRect(r, 8 * d, 8 * d, Path.Direction.CW);
        Path arrow = new Path();
        arrow.moveTo(r.centerX() - 6 * d, r.bottom - 0.5f);
        arrow.lineTo(r.centerX(), r.bottom + 8 * d);
        arrow.lineTo(r.centerX() + 6 * d, r.bottom - 0.5f);
        arrow.close();
        path.op(arrow, Path.Op.UNION); // 一条闭合路径，接缝无缝
        c.drawPath(path, shadowPaint(0xFFFFFFFF));
        result("1_path.hwAccelerated", String.valueOf(c.isHardwareAccelerated()));
        return b;
    }

    private Bitmap opaque() {
        Bitmap s = Bitmap.createBitmap(Math.round(80 * d), Math.round(40 * d), Bitmap.Config.ARGB_8888);
        s.eraseColor(0xFFFFFFFF);
        return s;
    }

    private Bitmap round() {
        Bitmap s = Bitmap.createBitmap(Math.round(80 * d), Math.round(40 * d), Bitmap.Config.ARGB_8888);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(0xFFFFFFFF);
        new Canvas(s).drawRoundRect(new RectF(0, 0, s.getWidth(), s.getHeight()), 20 * d, 20 * d, p);
        return s;
    }

    /** paintColor：drawBitmap 时阴影是否取 paint 颜色而非阴影色（白色 paint 对照黑色 paint）。 */
    private Bitmap variantBitmap(Bitmap src, int paintColor) {
        Bitmap b = canvasBitmap();
        new Canvas(b).drawBitmap(src, null, body(), shadowPaint(paintColor));
        return b;
    }

    /** 方案：九宫格先无阴影地画到临时位图，再整体 drawBitmap 一次（黑色 paint + setShadowLayer）。 */
    private Bitmap variantNineThenShadow() {
        Bitmap tmp = Bitmap.createBitmap(Math.round(80 * d), Math.round(40 * d), Bitmap.Config.ARGB_8888);
        drawNine(new Canvas(tmp), new RectF(0, 0, tmp.getWidth(), tmp.getHeight()),
                new Paint(Paint.FILTER_BITMAP_FLAG));
        Bitmap b = canvasBitmap();
        new Canvas(b).drawBitmap(tmp, null, body(), shadowPaint(0xFF000000));
        return b;
    }

    /** 九宫格：源图切 9 块分别 drawBitmap(src, dst)，每块都带阴影。 */
    private Bitmap variantNine(int paintColor) {
        Bitmap b = canvasBitmap();
        drawNine(new Canvas(b), body(), shadowPaint(paintColor));
        return b;
    }

    private void drawNine(Canvas c, RectF r, Paint p) {
        Bitmap src = round();
        int cap = Math.round(12 * d);
        int sw = src.getWidth(), sh = src.getHeight();
        int[] sx = {0, cap, sw - cap, sw}, sy = {0, cap, sh - cap, sh};
        float[] dx = {r.left, r.left + cap, r.right - cap, r.right}, dy = {r.top, r.top + cap, r.bottom - cap, r.bottom};
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
                c.drawBitmap(src, new android.graphics.Rect(sx[i], sy[j], sx[i + 1], sy[j + 1]),
                        new RectF(dx[i], dy[j], dx[i + 1], dy[j + 1]), p);
            }
        }
    }

    /** 保底方案：alpha 遮罩模糊后作为阴影，再在上面画原图。 */
    private Bitmap variantMaskFilter(Bitmap src) {
        Bitmap b = canvasBitmap();
        Canvas c = new Canvas(b);
        Paint blur = new Paint(Paint.ANTI_ALIAS_FLAG);
        blur.setColor(SHADOW);
        blur.setMaskFilter(new BlurMaskFilter(BLUR * d, BlurMaskFilter.Blur.NORMAL));
        Bitmap alpha = src.extractAlpha();
        RectF r = body();
        RectF sr = new RectF(r);
        sr.offset(DX * d, DY * d);
        c.drawBitmap(alpha, null, sr, blur);
        c.drawBitmap(src, null, r, new Paint(Paint.FILTER_BITMAP_FLAG));
        return b;
    }

    /** 主体外阴影像素数量、最大 alpha，以及上下方向的阴影量（验证 dy 偏移）。 */
    private String measure(Bitmap b) {
        RectF r = body();
        int count = 0, maxA = 0, above = 0, below = 0;
        for (int y = 0; y < b.getHeight(); y++) {
            for (int x = 0; x < b.getWidth(); x++) {
                if (r.contains(x + 0.5f, y + 0.5f)) continue;
                int a = Color.alpha(b.getPixel(x, y));
                if (a > 8) {
                    count++;
                    maxA = Math.max(maxA, a);
                    if (y < r.top && x > r.left && x < r.right) above++;
                    if (y > r.bottom && x > r.left && x < r.right) below++;
                }
            }
        }
        int bodyA = Color.alpha(b.getPixel(Math.round(r.centerX()), Math.round(r.centerY())));
        // 下方 5dp 处阴影像素的颜色：应为黑色系（阴影色），白色系说明阴影取了 paint 颜色
        int s = b.getPixel(Math.round(r.centerX()), Math.round(r.bottom + 5 * d));
        return "outsidePx=" + count + " maxAlpha=" + maxA + " above=" + above + " below=" + below
                + " bodyAlpha=" + bodyA + " shadowRGB=" + hex(s);
    }
}
