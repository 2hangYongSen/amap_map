package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Bitmap;
import android.graphics.Canvas;

import com.amap.flutter.map.overlays.marker.nativemarker.MarkerPainter;
import com.amap.flutter.map.overlays.marker.nativemarker.NativeMarkerLayout;
import com.amap.flutter.map.overlays.marker.nativemarker.NativeMarkerSpec;
import com.amap.flutter.map.overlays.marker.nativemarker.PaintJob;
import com.amap.flutter.map.overlays.marker.nativemarker.ShapeRenderer;

import java.util.concurrent.CancellationException;

/** 后台线程把 PaintJob 画成 ARGB_8888 位图；布局、绘制算法都在纯 Java 的 ShapeRenderer 中 */
public final class NativeMarkerPainter implements MarkerPainter {
    /** D-6：图片背景与图标在 S11 实现，之前只完整绘制纯形状点位 */
    @Override
    public boolean supports(NativeMarkerSpec spec) {
        return spec.isPureShape();
    }

    @Override
    public Result paint(PaintJob job) throws Exception {
        double density = job.densityUnits / 1024.0;
        AndroidTextMeasurer measurer = new AndroidTextMeasurer(density);
        NativeMarkerLayout layout = NativeMarkerLayout.compute(job.spec, job.densityUnits,
                measurer, job);
        layout.requireWithinLimit(); // D-8：超限不分配位图，直接报 renderFailed
        if (job.isCancelled()) {
            throw new CancellationException("绘制已取消");
        }
        Bitmap bitmap = Bitmap.createBitmap(layout.width, layout.height, Bitmap.Config.ARGB_8888);
        try {
            AndroidSurface surface = new AndroidSurface(new Canvas(bitmap), density);
            ShapeRenderer.render(job.spec, layout, job.selected, measurer, surface, job);
            if (job.isCancelled()) {
                throw new CancellationException("绘制已取消");
            }
            return new Result(bitmap, layout.anchorU(), layout.anchorV());
        } catch (Exception e) {
            bitmap.recycle(); // 失败或取消的位图从未交给任何人
            throw e;
        } catch (Error e) {
            bitmap.recycle();
            // 不再把 Error 抛出后台线程：包成普通异常，由调度器报 renderFailed
            throw new Exception("绘制失败: " + e, e);
        }
    }
}
