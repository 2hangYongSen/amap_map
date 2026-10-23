package com.amap.flutter.map.overlays.marker.nativemarker;

/** 在后台线程把一个 PaintJob 画成位图；S10 由 NativeMarkerPainter 实现，S9 测试用替身 */
public interface MarkerPainter {

    /** 绘制输出：合成位图（Android 为 Bitmap）与画布锚点 */
    final class Result {
        public final Object bitmap;
        public final float anchorU;
        public final float anchorV;

        public Result(Object bitmap, float anchorU, float anchorV) {
            this.bitmap = bitmap;
            this.anchorU = anchorU;
            this.anchorV = anchorV;
        }
    }

    /** 每个绘制步骤之间应检查 job.isCancelled()，尽早结束（R-DISP-4） */
    Result paint(PaintJob job) throws Exception;
}
