package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

/**
 * ShapeRenderer 几何：期望值全部按 §9.1/9.2 手算，不从被测布局反推。
 * 夹具测量器：文字宽 = 字数 × 字号 × 0.5，行高 = 字号 × 1.25。
 */
public class ShapeGeometryTest {
    private static final int D2 = 2048; // 密度 2.0
    private static final double EPS = 1e-4; // Outline 以 float 存储
    private final Fixtures.FakeResolver resolver = new Fixtures.FakeResolver();

    /** 路径包围盒 [l, t, r, b]（四分之一圆弧的控制点不越出角框） */
    static double[] bounds(Outline o) {
        double[] b = {Double.MAX_VALUE, Double.MAX_VALUE, -Double.MAX_VALUE, -Double.MAX_VALUE};
        o.accept(new Outline.Visitor() {
            void p(float x, float y) {
                b[0] = Math.min(b[0], x); b[1] = Math.min(b[1], y);
                b[2] = Math.max(b[2], x); b[3] = Math.max(b[3], y);
            }
            @Override public void move(float x, float y) { p(x, y); }
            @Override public void line(float x, float y) { p(x, y); }
            @Override public void cubic(float a, float c, float d, float e, float f, float g) {
                p(a, c); p(d, e); p(f, g);
            }
            @Override public void close() { }
        });
        return b;
    }

    private static void assertBounds(double[] expect, Outline o) {
        double[] got = bounds(o);
        for (int i = 0; i < 4; i++) {
            assertEquals(Arrays.toString(got), expect[i], got[i], EPS);
        }
    }

    private ShapeRendererTest.Run run(Map<String, Object> p, int d, boolean sel) throws Exception {
        return ShapeRendererTest.run(resolver, p, d, sel);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> sub(Map<String, Object> st, String key) {
        return (Map<String, Object>) st.get(key);
    }

    // 两态尺寸与锚点都不同：共用 (px, py)，各自按 -a 偏移
    @Test
    public void twoStatesShareAnchorPixel() throws Exception {
        // 普通态：文字 18×15，内边距 6/3 → 主体 30×21，箭头 10×6；a = (15, 27)
        Map<String, Object> n = RenderKeyTest.style(80, null);
        // 选中态：固定 60×24，箭头 16×8，阴影 blur 4、offset (0,2) → 扩边 (4, 6)
        Map<String, Object> s = RenderKeyTest.style(80, RenderKeyTest.shadow(4));
        s.put("width", 60.0);
        s.put("height", 24.0);
        sub(s, "arrow").put("width", 16.0);
        sub(s, "arrow").put("height", 8.0);
        Map<String, Object> p = RenderKeyTest.presentation("abc", n, s);
        // Vn = [-15,-27,15,0]；选中态 visible = [-4,-6,64,38]，a = (30,32) → Vs = [-34,-38,34,6]
        // U = [-34,-38,34,6]；d=2：px = 68，py = 76，W = 68+68 = 136，H = 76+12 = 88
        ShapeRendererTest.Run rn = run(p, D2, false);
        ShapeRendererTest.Run rs = run(p, D2, true);
        for (ShapeRendererTest.Run r : Arrays.asList(rn, rs)) {
            assertEquals(68, r.layout.px);
            assertEquals(76, r.layout.py);
            assertEquals(136, r.layout.width);
            assertEquals(88, r.layout.height);
            assertEquals("origin 68,76", r.surface.calls.get(0));
        }
        // 普通态主体 [-15,-27,15,-6]，尖端 (0,0)；文字 x = -15+6 = -9，cy = -27+3+15/2 = -16.5
        assertBounds(new double[]{-15, -27, 15, 0}, rn.surface.paths.get(0));
        assertEquals(-9, rn.surface.texts.get(0)[0], 1e-9);
        assertEquals(-16.5, rn.surface.texts.get(0)[1], 1e-9);
        // 选中态主体 [-30,-32,30,-8]，尖端 (0,0)；文字 x = -30+6+(48-18)/2 = -9，cy = -32+3+18/2 = -20
        assertBounds(new double[]{-30, -32, 30, 0}, rs.surface.paths.get(0));
        assertEquals(-9, rs.surface.texts.get(0)[0], 1e-9);
        assertEquals(-20, rs.surface.texts.get(0)[1], 1e-9);
    }

    // 圆形：直径 24，bodyCenter；d=2 → U = [-12,-12,12,12]，px = py = 24，画布 48×48
    @Test
    public void circle() throws Exception {
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "shape");
        bg.put("kind", "circle");
        bg.put("diameter", 24.0);
        bg.put("fillColor", 0xFF1E88E5L);
        Map<String, Object> st = new HashMap<>();
        st.put("background", bg);
        Map<String, Object> p = RenderKeyTest.presentation("8", st, null);
        p.put("anchorType", "bodyCenter");
        ShapeRendererTest.Run r = run(p, D2, false);
        assertEquals(24, r.layout.px);
        assertEquals(24, r.layout.py);
        assertEquals(48, r.layout.width);
        assertEquals(48, r.layout.height);
        Outline o = r.surface.paths.get(0);
        assertEquals(1, o.contourCount());
        assertBounds(new double[]{-12, -12, 12, 12}, o);
        assertTrue(r.surface.calls.get(1).startsWith("fill ff1e88e5 "));
        // 文字宽 6 居中：x = -12 + (24-6)/2 = -3；cy = 0
        assertEquals(-3, r.surface.texts.get(0)[0], 1e-9);
        assertEquals(0, r.surface.texts.get(0)[1], 1e-9);
    }

    // D-3：有描边时路径内缩半个线宽，填充与描边共用这条路径
    @Test
    public void borderInsetsHalfWidth() throws Exception {
        Map<String, Object> st = RenderKeyTest.style(80, null);
        sub(st, "background").put("borderColor", 0xFF2266AAL);
        sub(st, "background").put("borderWidth", 2.0);
        ShapeRendererTest.Run r = run(RenderKeyTest.presentation("abc", st, null), D2, false);
        // 主体 [-15,-27,15,-6] 内缩 1 → [-14,-26,14,-7]；尖端 (0,0) 上移 1 → (0,-1)
        double[] expect = {-14, -26, 14, -1};
        assertBounds(expect, r.surface.paths.get(0));
        assertTrue(r.surface.calls.get(2), r.surface.calls.get(2).startsWith("stroke ff2266aa w=0x1.0p1 "));
        assertSame(r.surface.paths.get(0), r.surface.paths.get(1));
        assertEquals(Arrays.asList(2.0), r.surface.strokeWidths);
    }

    // textAlign：主体固定 60 宽，内容区 [-24, 24]，文字宽 18
    @Test
    public void textAlignLeftAndRight() throws Exception {
        double[] xs = new double[2];
        String[] aligns = {"left", "right"};
        for (int i = 0; i < 2; i++) {
            Map<String, Object> st = RenderKeyTest.style(80, null);
            st.put("width", 60.0);
            st.put("textAlign", aligns[i]);
            xs[i] = run(RenderKeyTest.presentation("abc", st, null), D2, false)
                    .surface.texts.get(0)[0];
        }
        assertEquals("左对齐 x = -30+6", -24, xs[0], 1e-9);
        assertEquals("右对齐 x = 24-18", 6, xs[1], 1e-9);
    }

    // D-8：maxWidth 很大、density 3.5 → 画布超过 2048 物理像素，不绘制
    @Test
    public void oversizedCanvasIsRejected() throws Exception {
        char[] cs = new char[150];
        Arrays.fill(cs, 'a');
        Map<String, Object> p = RenderKeyTest.presentation(new String(cs),
                RenderKeyTest.style(1000, null), null);
        NativeMarkerSpec spec = NativeMarkerSpec.parse(p);
        // 主体宽 150×6+12 = 912 → ×3.5 = 3192 像素
        NativeMarkerLayout l = NativeMarkerLayout.compute(spec, 3584, Fixtures.measurer(), resolver);
        assertFalse(l.withinLimit());
        RecordingSurface s = new RecordingSurface();
        try {
            ShapeRenderer.render(spec, l, false, Fixtures.measurer(), s, null);
            fail("超限应拒绝绘制");
        } catch (IllegalStateException expected) {
            assertTrue(s.calls.isEmpty());
        }
    }

    // D-8 边界：恰好 2048 允许
    @Test
    public void canvasAtLimitIsAllowed() throws Exception {
        Map<String, Object> st = RenderKeyTest.style(2000, null);
        st.remove("arrow");
        st.put("width", 1024.0);
        st.put("height", 20.0);
        Map<String, Object> p = RenderKeyTest.presentation("abc", st, null);
        p.put("anchorType", "bodyCenter");
        NativeMarkerLayout l = NativeMarkerLayout.compute(NativeMarkerSpec.parse(p), D2,
                Fixtures.measurer(), resolver);
        assertEquals(2048, l.width);
        assertTrue(l.withinLimit());
    }

    // V-2：API 28 以下的字重降级
    @Test
    public void fontWeightFallback() {
        assertFalse(FontWeights.isBoldFallback(400));
        assertFalse(FontWeights.isBoldFallback(500));
        assertTrue(FontWeights.isBoldFallback(600));
        assertTrue(FontWeights.isBoldFallback(700));
    }
}
