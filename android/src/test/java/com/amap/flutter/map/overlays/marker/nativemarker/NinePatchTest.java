package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** 九宫格切片几何（§9.3），期望值全部手算 */
public class NinePatchTest {
    private static int[] cap(double l, double t, double r, double b) {
        return new int[]{(int) (l * 64), (int) (t * 64), (int) (r * 64), (int) (b * 64)};
    }

    // 图 60x40 像素、pixelRatio 2（逻辑 30x20），cap 逻辑 (8,6,8,6) → 源切线 16/44、12/28；
    // 目标 (10,5)-(110,45)：角保持逻辑尺寸，边单向拉伸，中间双向拉伸
    @Test
    public void ninePiecesWithPixelRatio() {
        double[][] s = NinePatch.slices(60, 40, 2.0, cap(8, 6, 8, 6), new RectD(10, 5, 110, 45));
        assertEquals(9, s.length);
        assertArrayEquals("左上角", new double[]{0, 0, 16, 12, 10, 5, 18, 11}, s[0], 0);
        assertArrayEquals("上边", new double[]{16, 0, 44, 12, 18, 5, 102, 11}, s[1], 0);
        assertArrayEquals("右上角", new double[]{44, 0, 60, 12, 102, 5, 110, 11}, s[2], 0);
        assertArrayEquals("中间", new double[]{16, 12, 44, 28, 18, 11, 102, 39}, s[4], 0);
        assertArrayEquals("右下角", new double[]{44, 28, 60, 40, 102, 39, 110, 45}, s[8], 0);
    }

    // 某边 cap 为 0：该行或列的切片为空，不绘制
    @Test
    public void zeroInsetSkipsEmptySlices() {
        double[][] s = NinePatch.slices(60, 40, 2.0, cap(8, 0, 8, 0), new RectD(0, 0, 100, 20));
        assertEquals("只剩中间一行 3 块", 3, s.length);
        assertArrayEquals(new double[]{0, 0, 16, 40, 0, 0, 8, 20}, s[0], 0);
        assertArrayEquals(new double[]{16, 0, 44, 40, 8, 0, 92, 20}, s[1], 0);
    }

    // 目标宽小于左右角之和：角按比例压缩，不重叠；中间列消失
    @Test
    public void tinyTargetShrinksCorners() {
        double[][] s = NinePatch.slices(60, 40, 2.0, cap(8, 6, 8, 6), new RectD(0, 0, 8, 40));
        for (double[] p : s) {
            assertTrue("目标框不越界", p[4] >= 0 && p[6] <= 8);
        }
        assertEquals("左右各 4，中间列为空", 6, s.length);
        assertEquals(4, s[0][6], 0);
    }

    @Test
    public void wholeImage() {
        double[][] s = NinePatch.slices(60, 40, 2.0, null, new RectD(1, 2, 31, 22));
        assertArrayEquals(new double[]{0, 0, 60, 40, 1, 2, 31, 22}, s[0], 0);
    }

    // R-VAL-5：左右之和、上下之和必须严格小于逻辑尺寸
    @Test
    public void fitsIsStrict() {
        assertTrue(NinePatch.fits(cap(14, 9, 15, 10), 30, 20));
        assertFalse("等于不允许", NinePatch.fits(cap(15, 9, 15, 10), 30, 20));
        assertFalse(NinePatch.fits(cap(1, 10, 1, 10), 30, 20));
    }
}
