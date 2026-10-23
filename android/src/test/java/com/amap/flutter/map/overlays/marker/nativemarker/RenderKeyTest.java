package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

/** T-KEY-1/2/3/5 与 NormSpec 防御性校验 */
public class RenderKeyTest {
    private static final int D3 = 3072; // density 3.0 的 1/1024 单位
    private final Fixtures.FakeResolver resolver = new Fixtures.FakeResolver();

    static Map<String, Object> style(double width, Map<String, Object> shadow) {
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "shape");
        bg.put("kind", "roundedRect");
        bg.put("fillColor", 0xFFFFFFFFL);
        bg.put("cornerRadius", 4.0);
        Map<String, Object> s = new HashMap<>();
        s.put("background", bg);
        s.put("fontSize", 12.0);
        s.put("padding", Arrays.asList(6.0, 3.0, 6.0, 3.0));
        s.put("maxWidth", width);
        Map<String, Object> arrow = new HashMap<>();
        arrow.put("width", 10.0);
        arrow.put("height", 6.0);
        s.put("arrow", arrow);
        s.put("shadow", shadow);
        return s;
    }

    static Map<String, Object> shadow(double blur) {
        Map<String, Object> sh = new HashMap<>();
        sh.put("color", 0x1F000000);
        sh.put("blurRadius", blur);
        sh.put("offset", Arrays.asList(0.0, 2.0));
        return sh;
    }

    static Map<String, Object> presentation(String text, Map<String, Object> normal,
                                            Map<String, Object> selected) {
        Map<String, Object> content = new HashMap<>();
        content.put("text", text);
        content.put("iconId", null);
        content.put("iconSize", null);
        content.put("iconSpacing", 4.0);
        Map<String, Object> p = new HashMap<>();
        p.put("content", content);
        p.put("style", normal);
        p.put("selectedStyle", selected);
        p.put("anchorType", "arrowTip");
        p.put("anchor", null);
        return p;
    }

    private String normalKey(Map<String, Object> p) throws InvalidMarkerException {
        return RenderKey.normalKey(NativeMarkerSpec.parse(p), D3, resolver);
    }

    // T-KEY-1：普通态相同、选中态不同 → normalKey 不同
    @Test
    public void tKey1_selectedStyleAffectsNormalKey() throws Exception {
        Map<String, Object> a = presentation("¥3000", style(80, null), null);
        Map<String, Object> b = presentation("¥3000", style(80, null), style(80, shadow(4)));
        assertNotEquals(normalKey(a), normalKey(b));
    }

    // T-KEY-2：只改位置、zIndex、ID 时 key 不变
    @Test
    public void tKey2_nonRenderPropsDoNotAffectKey() throws Exception {
        Map<String, Object> m1 = Payloads.base("h:1");
        m1.put("renderMode", "native");
        m1.put("icon", null);
        m1.put("nativePresentation", presentation("¥3000", style(80, null), null));
        Map<String, Object> m2 = Payloads.base("h:2");
        m2.putAll(m1);
        m2.put("id", "h:2");
        m2.put("position", Arrays.asList(30.1, 120.2));
        m2.put("zIndex", 9.0);
        m2.put("alpha", 0.5);
        m2.put("visible", false);
        FullMarkerOptions o1 = FullMarkerOptions.parse(m1);
        FullMarkerOptions o2 = FullMarkerOptions.parse(m2);
        assertEquals(normalKey(castMap(o1.nativePresentation)), normalKey(castMap(o2.nativePresentation)));
    }

    // T-KEY-3：浮点相差 1e-9 → NormSpec 序列化、key、布局都相同
    @Test
    public void tKey3_tinyFloatDiffIsSameKeyAndLayout() throws Exception {
        NativeMarkerSpec a = NativeMarkerSpec.parse(presentation("abcdefgh", style(60.0, shadow(4)), null));
        NativeMarkerSpec b = NativeMarkerSpec.parse(
                presentation("abcdefgh", style(60.0 + 1e-9, shadow(4 - 1e-9)), null));
        KeyWriter ka = RenderKey.writer(a, D3, resolver, RenderKey.ROLE_NORMAL);
        KeyWriter kb = RenderKey.writer(b, D3, resolver, RenderKey.ROLE_NORMAL);
        assertEquals(ka.raw(), kb.raw());
        assertEquals(ka.hash(), kb.hash());
        NativeMarkerLayout la = NativeMarkerLayout.compute(a, D3, Fixtures.measurer(), resolver);
        NativeMarkerLayout lb = NativeMarkerLayout.compute(b, D3, Fixtures.measurer(), resolver);
        assertEquals(la.union, lb.union);
        assertEquals(la.normal.body, lb.normal.body);
        assertEquals(la.normal.displayText, lb.normal.displayText);
        assertEquals(la.width, lb.width);
        assertEquals(la.px, lb.px);
        // 逐像素对比依赖 Painter，留到 S10 的 T-KEY-4 一并覆盖
    }

    // 规格失败场景 1：59.995 与 60.004 规范化到同一值，布局也相同
    @Test
    public void maxWidthNearSixtyNormalizesTogether() throws Exception {
        NativeMarkerSpec a = NativeMarkerSpec.parse(presentation("abcdefghijkl", style(59.995, null), null));
        NativeMarkerSpec b = NativeMarkerSpec.parse(presentation("abcdefghijkl", style(60.004, null), null));
        assertEquals(a.normal.maxWidth, b.normal.maxWidth);
        assertEquals(RenderKey.normalKey(a, D3, resolver), RenderKey.normalKey(b, D3, resolver));
    }

    // T-KEY-5：同一资源 ready 与 fallback 两种解析结果下 key 不同
    @Test
    @SuppressWarnings("unchecked")
    public void tKey5_readyAndFallbackDiffer() throws Exception {
        Map<String, Object> p = presentation("景点", style(80, null), null);
        ((Map<String, Object>) p.get("content")).put("iconId", "spot");
        NativeMarkerSpec spec = NativeMarkerSpec.parse(p);
        String ready = RenderKey.normalKey(spec, D3, resolver);
        resolver.failed.add("spot");
        String fallback = RenderKey.normalKey(spec, D3, resolver);
        assertNotEquals(ready, fallback);
        resolver.failed.clear();
        assertEquals(ready, RenderKey.normalKey(spec, D3, resolver));
    }

    @Test
    public void roleAndDensityAffectKey() throws Exception {
        NativeMarkerSpec spec = NativeMarkerSpec.parse(presentation("a", style(80, null), null));
        assertNotEquals(RenderKey.normalKey(spec, D3, resolver), RenderKey.selectedKey(spec, D3, resolver));
        assertNotEquals(RenderKey.normalKey(spec, D3, resolver), RenderKey.normalKey(spec, 2688, resolver));
    }

    // R-VAL-10：规范化后为 0 的字号被拒绝；其余原生防御性校验
    @Test
    public void invalidSpecsRejected() {
        Map<String, Object> tinyFont = style(80, null);
        tinyFont.put("fontSize", 0.001);
        Map<String, Object> badRange = style(80, null);
        badRange.put("minWidth", 100.0);
        Map<String, Object> nan = style(Double.NaN, null);
        Map<String, Object> noArrow = style(80, null);
        noArrow.put("arrow", null);
        for (Map<String, Object> s : Arrays.asList(tinyFont, badRange, nan, noArrow)) {
            try {
                NativeMarkerSpec.parse(presentation("a", s, null));
                fail("应拒绝 " + s);
            } catch (InvalidMarkerException expected) {
                // 期望抛出
            }
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Map<?, ?> m) {
        return (Map<String, Object>) m;
    }
}
