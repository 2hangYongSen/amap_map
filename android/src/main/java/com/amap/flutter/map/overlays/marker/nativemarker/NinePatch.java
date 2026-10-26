package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.List;

/**
 * 九宫格切片几何（§9.3）：纯计算。capInsets 为逻辑像素，乘资源 pixelRatio 换算成图片像素；
 * 目标框的四角保持 capInsets 逻辑尺寸，四边单向拉伸，中间双向拉伸。
 * 每个切片 {srcL, srcT, srcR, srcB, dstL, dstT, dstR, dstB}：src 为整数图片像素，dst 为逻辑像素。
 */
public final class NinePatch {
    private NinePatch() {
    }

    /** 整张图缩放到 dst（固定尺寸背景、图标） */
    public static double[][] whole(int imgW, int imgH, RectD dst) {
        return new double[][]{{0, 0, imgW, imgH, dst.left, dst.top, dst.right, dst.bottom}};
    }

    /**
     * @param cap 1/64 单位的 [l, t, r, b]；为 null 时等同 whole
     */
    public static double[][] slices(int imgW, int imgH, double pixelRatio, int[] cap, RectD dst) {
        if (cap == null) {
            return whole(imgW, imgH, dst);
        }
        double[] c = new double[4];
        for (int i = 0; i < 4; i++) {
            c[i] = Norm.length(cap[i]);
        }
        // 源图切线：逻辑 × pixelRatio，取整到像素并夹在图内（R-VAL-5 已保证不交叉）
        int sl = clampPx(c[0] * pixelRatio, imgW);
        int sr = Math.max(sl, imgW - clampPx(c[2] * pixelRatio, imgW));
        int st = clampPx(c[1] * pixelRatio, imgH);
        int sb = Math.max(st, imgH - clampPx(c[3] * pixelRatio, imgH));
        // 目标框比两角之和还小时按比例压缩角，避免四角重叠
        double kx = scale(c[0] + c[2], dst.width());
        double ky = scale(c[1] + c[3], dst.height());
        double dl = dst.left + c[0] * kx;
        double dr = dst.right - c[2] * kx;
        double dt = dst.top + c[1] * ky;
        double db = dst.bottom - c[3] * ky;
        double[] sx = {0, sl, sr, imgW};
        double[] sy = {0, st, sb, imgH};
        double[] dx = {dst.left, dl, dr, dst.right};
        double[] dy = {dst.top, dt, db, dst.bottom};
        List<double[]> out = new ArrayList<>(9);
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 3; col++) {
                // 源或目标为空的切片不画（例如 capInsets 某边为 0）
                if (sx[col + 1] <= sx[col] || sy[row + 1] <= sy[row]
                        || dx[col + 1] <= dx[col] || dy[row + 1] <= dy[row]) {
                    continue;
                }
                out.add(new double[]{sx[col], sy[row], sx[col + 1], sy[row + 1],
                        dx[col], dy[row], dx[col + 1], dy[row + 1]});
            }
        }
        return out.toArray(new double[0][]);
    }

    /** R-VAL-5：左右之和 < 逻辑宽、上下之和 < 逻辑高 */
    public static boolean fits(int[] cap, double logicalW, double logicalH) {
        return Norm.length(cap[0]) + Norm.length(cap[2]) < logicalW
                && Norm.length(cap[1]) + Norm.length(cap[3]) < logicalH;
    }

    private static int clampPx(double v, int max) {
        return (int) Math.max(0, Math.min(max, Math.round(v)));
    }

    private static double scale(double caps, double size) {
        return caps > size && caps > 0 ? size / caps : 1;
    }
}
