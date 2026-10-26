package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

/** 形状轮廓：圆角矩形加箭头必须是一条闭合连续路径（没有透明缝） */
public class OutlineBuilderTest {
    private static final RectD BODY = new RectD(0, 0, 60, 24);

    /** 收集端点并检查每段起点等于上一段终点（连续） */
    private static List<float[]> walk(Outline o) {
        List<float[]> pts = new ArrayList<>();
        final float[] cur = new float[2];
        final boolean[] closed = {false};
        o.accept(new Outline.Visitor() {
            private void to(float x, float y, boolean needMove) {
                assertTrue("close 之后不应再有线段", !closed[0]);
                cur[0] = x;
                cur[1] = y;
                pts.add(new float[]{x, y});
            }

            @Override public void move(float x, float y) { to(x, y, false); }
            @Override public void line(float x, float y) { to(x, y, true); }
            @Override public void cubic(float a, float b, float c, float d, float x, float y) {
                to(x, y, true);
            }
            @Override public void close() { closed[0] = true; }
        });
        assertTrue("路径必须闭合", closed[0]);
        return pts;
    }

    @Test
    public void arrowOutlineIsSingleClosedContour() {
        Outline o = OutlineBuilder.withArrow(BODY, 4, 30, 30, 10);
        assertEquals(1, o.contourCount());
        walk(o);
    }

    @Test
    public void arrowTipAndBaseOnBodyBottom() {
        List<float[]> pts = walk(OutlineBuilder.withArrow(BODY, 4, 30, 30, 10));
        boolean tip = false;
        boolean right = false;
        boolean left = false;
        for (float[] p : pts) {
            tip |= p[0] == 30 && p[1] == 30;
            right |= p[0] == 35 && p[1] == 24;
            left |= p[0] == 25 && p[1] == 24;
        }
        assertTrue("尖端", tip);
        assertTrue("右底边点", right);
        assertTrue("左底边点", left);
    }

    @Test
    public void noArrowFallsBackToBody() {
        assertEquals(walk(OutlineBuilder.body(BODY, 4)).size(),
                walk(OutlineBuilder.withArrow(BODY, 4, 30, 24, 10)).size());
    }

    // 圆形：箭头底边点落在圆弧上，路径仍然连续、所有点在主体加箭头范围内
    @Test
    public void circleWithWideArrowStaysOnArc() {
        RectD circle = new RectD(0, 0, 40, 40);
        Outline o = OutlineBuilder.withArrow(circle, 20, 20, 48, 16);
        assertEquals(1, o.contourCount());
        for (float[] p : walk(o)) {
            assertTrue(p[0] >= -0.01 && p[0] <= 40.01 && p[1] >= -0.01 && p[1] <= 48.01);
        }
    }

    // 箭头底边比圆角直边宽：底边点落到圆角弧上，仍为一条路径
    @Test
    public void arrowWiderThanStraightEdge() {
        Outline o = OutlineBuilder.withArrow(new RectD(0, 0, 30, 20), 8, 15, 28, 28);
        assertEquals(1, o.contourCount());
        for (float[] p : walk(o)) {
            assertTrue(p[0] >= -0.01 && p[0] <= 30.01);
        }
    }

    @Test
    public void radiusClampedToHalfShortSide() {
        assertEquals(10, OutlineBuilder.radius(60, 20, 50), 0);
        assertEquals(0, OutlineBuilder.radius(60, 20, -3), 0);
    }
}
