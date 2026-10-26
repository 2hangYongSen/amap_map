package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CancellationException;

/** T-KEY-4：记录型测量器与画布（%a 精确记录），验证 NormSpec 驱动的测量输入和绘制调用序列 */
public class ShapeRendererTest {
    private static final int D281 = 2880; // 密度 2.8125
    private static final double HALF_UNIT = 1.0 / 128; // 1/64 单位的一半
    private final Fixtures.FakeResolver resolver = new Fixtures.FakeResolver();

    static final class Run {
        final RecordingSurface surface = new RecordingSurface();
        final RecordingSurface.Measurer measurer = new RecordingSurface.Measurer();
        NativeMarkerLayout layout;
    }

    static Run run(Fixtures.FakeResolver resolver, Map<String, Object> presentation, int density,
                   boolean selected) throws Exception {
        NativeMarkerSpec spec = NativeMarkerSpec.parse(presentation);
        Run r = new Run();
        r.layout = NativeMarkerLayout.compute(spec, density, r.measurer, resolver);
        ShapeRenderer.render(spec, r.layout, selected, r.measurer, r.surface, null);
        return r;
    }

    private Run run(Map<String, Object> presentation, int density, boolean selected)
            throws Exception {
        return run(resolver, presentation, density, selected);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> sub(Map<String, Object> st, String key) {
        return (Map<String, Object>) st.get(key);
    }

    /** 带描边、阴影、箭头的完整样式；mutate 写入被扰动的一个字段 */
    private Run full(String field, double v) throws Exception {
        Map<String, Object> st = RenderKeyTest.style(80, RenderKeyTest.shadow(4));
        sub(st, "background").put("borderColor", 0xFF2266AAL);
        sub(st, "background").put("borderWidth", 1.0);
        switch (field) {
            case "padding": st.put("padding", Arrays.asList(v, 3.0, 6.0, 3.0)); break;
            case "cornerRadius": sub(st, "background").put(field, v); break;
            case "borderWidth": sub(st, "background").put(field, v); break;
            case "arrowWidth": sub(st, "arrow").put("width", v); break;
            case "arrowHeight": sub(st, "arrow").put("height", v); break;
            case "shadowDy": sub(st, "shadow").put("offset", Arrays.asList(0.0, v)); break;
            default: throw new IllegalArgumentException(field);
        }
        return run(RenderKeyTest.presentation("abcdefgh", st, null), D281, false);
    }

    // 每个长度字段：规范化后相同的扰动 → 记录完全相同；规范化后不同（差 1/64）→ 记录必须不同
    @Test
    public void tKey4_perturbationsPerField() throws Exception {
        Object[][] cases = {{"padding", 6.0}, {"cornerRadius", 4.0}, {"borderWidth", 1.0},
                {"arrowWidth", 10.0}, {"arrowHeight", 6.0}, {"shadowDy", 2.0}};
        for (Object[] c : cases) {
            String f = (String) c[0];
            double base = (Double) c[1];
            Run a = full(f, base);
            for (double same : new double[]{base + 1e-9, base + HALF_UNIT * 0.9,
                    base - HALF_UNIT * 0.9}) {
                Run b = full(f, same);
                assertEquals(f + "=" + same + " 测量输入", a.measurer.inputs, b.measurer.inputs);
                assertEquals(f + "=" + same + " 绘制调用", a.surface.calls, b.surface.calls);
            }
            Run d = full(f, base + 1.0 / 64);
            assertNotEquals(f + " 规范化后不同，记录必须不同", a.surface.calls, d.surface.calls);
        }
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

    // 字号按 1/64 规范化后传给测量器（12.003 → 12 = 0x1.8p3），不是原始浮点
    @Test
    public void tKey4_measurerReceivesNormalizedFont() throws Exception {
        Map<String, Object> st = RenderKeyTest.style(80, null);
        st.put("fontSize", 12.003);
        Run r = run(RenderKeyTest.presentation("abc", st, null), D281, false);
        assertTrue(r.measurer.inputs.get(0), r.measurer.inputs.get(0).contains(" 0x1.8p3 "));
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
        assertTrue(r.surface.calls.get(1),
                r.surface.calls.get(1).startsWith("fillShadow ffffffff 1f000000 b=0x1.0p2 d=0x0.0p0,0x1.0p1 "));
    }

    // R-RES-6 + D-2：图片背景不可用时白色圆角矩形，描边 1 物理像素 = 1/density 逻辑像素；箭头并入同一路径
    @Test
    public void fallbackBackgroundWhenImageUnusable() throws Exception {
        resolver.failed.add("bg");
        Map<String, Object> st = RenderKeyTest.style(80, null);
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "image");
        bg.put("imageId", "bg");
        bg.put("size", Arrays.asList(60.0, 24.0));
        st.put("background", bg);
        sub(st, "arrow").put("color", 0xFFFF0000L);
        Run r = run(RenderKeyTest.presentation("abc", st, null), D281, false);
        String log = r.surface.calls.toString();
        assertTrue(log, log.contains("fill ffffffff"));
        assertEquals(1, r.surface.strokeWidths.size());
        assertEquals(1 / 2.8125, r.surface.strokeWidths.get(0), 1e-12);
        assertFalse("不再单独画异色三角形", log.contains("ffff0000"));
        assertEquals(1, r.surface.paths.get(0).contourCount());
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
