package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.Map;
import java.util.concurrent.CancellationException;

/** T-KEY-4：记录型测量器与画布，验证 NormSpec 驱动的测量输入和绘制调用序列 */
public class ShapeRendererTest {
    private static final int D281 = 2880; // 密度 2.8125
    private final Fixtures.FakeResolver resolver = new Fixtures.FakeResolver();

    private static final class Run {
        final RecordingSurface surface = new RecordingSurface();
        final RecordingSurface.Measurer measurer = new RecordingSurface.Measurer();
        NativeMarkerLayout layout;
    }

    private Run run(Map<String, Object> presentation, int density, boolean selected)
            throws Exception {
        NativeMarkerSpec spec = NativeMarkerSpec.parse(presentation);
        Run r = new Run();
        r.layout = NativeMarkerLayout.compute(spec, density, r.measurer, resolver);
        ShapeRenderer.render(spec, r.layout, selected, r.measurer, r.surface, null);
        return r;
    }

    // 规范化后相同的两组原始参数：测量输入、绘制调用序列完全相同
    @Test
    public void tKey4_sameNormSpecSameCalls() throws Exception {
        Run a = run(RenderKeyTest.presentation("abcdefgh", RenderKeyTest.style(60.0,
                RenderKeyTest.shadow(4)), null), D281, false);
        Run b = run(RenderKeyTest.presentation("abcdefgh", RenderKeyTest.style(60.0 + 1e-9,
                RenderKeyTest.shadow(4 - 1e-9)), null), D281, false);
        assertEquals(a.measurer.inputs, b.measurer.inputs);
        assertEquals(a.surface.calls, b.surface.calls);
        assertTrue(a.surface.calls.size() >= 3);
    }

    // 59.995 与 60.004 规范化到同一值，测量输入与绘制调用相同
    @Test
    public void tKey4_roundedMaxWidthSameCalls() throws Exception {
        Run a = run(RenderKeyTest.presentation("abcdefghijkl", RenderKeyTest.style(59.995, null),
                null), D281, false);
        Run b = run(RenderKeyTest.presentation("abcdefghijkl", RenderKeyTest.style(60.004, null),
                null), D281, false);
        assertEquals(a.measurer.inputs, b.measurer.inputs);
        assertEquals(a.surface.calls, b.surface.calls);
    }

    // 可配置长度读取自 NormSpec：字号按 1/64 规范化后传给测量器，不是原始浮点
    @Test
    public void tKey4_measurerReceivesNormalizedFont() throws Exception {
        Map<String, Object> st = RenderKeyTest.style(80, null);
        st.put("fontSize", 12.003); // 规范化为 12
        Run r = run(RenderKeyTest.presentation("abc", st, null), D281, false);
        assertTrue(r.measurer.inputs.get(0), r.measurer.inputs.get(0).contains(" 12.000000 "));
    }

    // 派生值：原点取自布局像素；arrowTip 锚点下箭头尖端落在逻辑原点 (0,0)
    @Test
    public void tKey4_originAndAnchorOffset() throws Exception {
        Run r = run(RenderKeyTest.presentation("abc", RenderKeyTest.style(80, null), null),
                D281, false);
        assertEquals("origin " + r.layout.px + "," + r.layout.py, r.surface.calls.get(0));
        // 无阴影时第一条填充是连续轮廓，其中含尖端 (0,0)
        assertTrue(r.surface.paths.get(0).toString(), r.surface.paths.get(0).toString()
                .contains("L0.000,0.000"));
        // 文字垂直中线 = 主体内容区中线 − 锚点偏移
        StateLayout st = r.layout.normal;
        double expect = st.body.top - st.anchorY + (st.body.height()) / 2
                + (3.0 - 3.0) / 2; // 上下内边距相等
        assertTrue(r.surface.calls.toString(), r.surface.calls.get(r.surface.calls.size() - 1)
                .contains(String.format(java.util.Locale.ROOT, "cy=%.4f", expect)));
    }

    // 密度只影响画布像素原点，逻辑坐标的调用序列不变
    @Test
    public void tKey4_densityOnlyChangesOrigin() throws Exception {
        Map<String, Object> p = RenderKeyTest.presentation("abc", RenderKeyTest.style(80, null), null);
        Run a = run(p, 2048, false);
        Run b = run(p, 3584, false);
        assertEquals(a.surface.calls.subList(1, a.surface.calls.size()),
                b.surface.calls.subList(1, b.surface.calls.size()));
        assertNotEquals(a.surface.calls.get(0), b.surface.calls.get(0));
    }

    @Test
    public void shadowUsesFillWithShadow() throws Exception {
        Run r = run(RenderKeyTest.presentation("abc", RenderKeyTest.style(80,
                RenderKeyTest.shadow(4)), null), D281, false);
        assertTrue(r.surface.calls.get(1).startsWith("fillShadow ffffffff 1f000000 b=4.0000"));
    }

    // R-RES-6：图片背景不可用时，用白色圆角矩形加 1 像素描边降级
    @Test
    public void fallbackBackgroundWhenImageUnusable() throws Exception {
        resolver.failed.add("bg");
        Map<String, Object> st = RenderKeyTest.style(80, null);
        Map<String, Object> bg = new java.util.HashMap<>();
        bg.put("type", "image");
        bg.put("imageId", "bg");
        bg.put("size", java.util.Arrays.asList(60.0, 24.0));
        st.put("background", bg);
        Map<String, Object> arrow = (Map<String, Object>) st.get("arrow");
        arrow.put("color", 0xFFFF0000L);
        Run r = run(RenderKeyTest.presentation("abc", st, null), D281, false);
        String log = r.surface.calls.toString();
        assertTrue(log, log.contains("fill ffffffff"));
        assertTrue(log, log.contains("stroke 1f000000 w=1.0000"));
        assertTrue("箭头异色单独绘制", log.contains("fill ffff0000"));
    }

    @Test
    public void cancelledJobStopsDrawing() throws Exception {
        NativeMarkerSpec spec = NativeMarkerSpec.parse(RenderKeyTest.presentation("abc",
                RenderKeyTest.style(80, null), null));
        NativeMarkerLayout l = NativeMarkerLayout.compute(spec, D281, Fixtures.measurer(), resolver);
        try {
            ShapeRenderer.render(spec, l, false, Fixtures.measurer(), new RecordingSurface(),
                    () -> true);
            fail("应抛出取消");
        } catch (CancellationException expected) {
            // 期望
        }
    }
}
