package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** 图片背景、九宫格、图标的绘制序列（纯计算，记录型画布）；期望坐标手算 */
public class ImageRendererTest {
    private static final int D2 = 2048; // 密度 2

    /** 所有资源都 ready：100x50 像素、pixelRatio 2（逻辑 50x25） */
    static final class Images implements ImageSet {
        final Map<String, DecodedImage> imgs = new HashMap<>();

        Images(String... ids) {
            for (String id : ids) {
                imgs.put(id, new FakeImages.Image(id, 100, 50, 20_000));
            }
        }

        @Override public boolean usable(String id) { return imgs.containsKey(id); }
        @Override public double[] logicalSize(String id) {
            return imgs.containsKey(id) ? new double[]{50, 25} : null;
        }
        @Override public DecodedImage image(String id) { return imgs.get(id); }
        @Override public double pixelRatio(String id) { return 2; }
    }

    private static RecordingSurface draw(Map<String, Object> p, Images images) throws Exception {
        NativeMarkerSpec spec = NativeMarkerSpec.parse(p);
        TextMeasurer m = Fixtures.measurer();
        NativeMarkerLayout l = NativeMarkerLayout.compute(spec, D2, m, images);
        RecordingSurface s = new RecordingSurface();
        ShapeRenderer.render(spec, l, false, m, images, s, null);
        return s;
    }

    private static Map<String, Object> imageStyle(Map<String, Object> bg) {
        Map<String, Object> st = new HashMap<>();
        st.put("background", bg);
        return st;
    }

    private static Map<String, Object> presentation(String text, Map<String, Object> st) {
        Map<String, Object> c = new HashMap<>();
        c.put("text", text);
        Map<String, Object> p = new HashMap<>();
        p.put("content", c);
        p.put("style", st);
        return p;
    }

    // 固定尺寸 + custom 锚点 (0.5, 1)：主体 40x30，锚点在底边中点 → 主体 (-20,-30)-(20,0)
    @Test
    public void fixedSizeWithCustomAnchor() throws Exception {
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "image");
        bg.put("imageId", "A");
        bg.put("size", Arrays.asList(40.0, 30.0));
        Map<String, Object> p = presentation(null, imageStyle(bg));
        ((Map<String, Object>) p).put("anchorType", "custom");
        p.put("anchor", Arrays.asList(0.5, 1.0));
        p.put("content", new HashMap<>(Map.of("iconId", "I", "iconSize", Arrays.asList(16.0, 16.0))));
        RecordingSurface s = draw(p, new Images("A", "I"));
        assertEquals("origin 40,60", s.calls.get(0));
        assertArrayEquals("背景整图缩放到主体", new double[]{0, 0, 100, 50, -20, -30, 20, 0},
                s.images.get(0)[0], 0);
        // 只有图标：居中 → x = -8，垂直中线 -15 → top = -23
        assertArrayEquals("图标", new double[]{0, 0, 100, 50, -8, -23, 8, -7},
                s.images.get(1)[0], 0);
    }

    // 九宫格 + 阴影 + 箭头：顺序为图片阴影 → 箭头（带阴影）→ 图片本体 → 文字
    @Test
    public void ninePatchShadowArrowOrder() throws Exception {
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "image");
        bg.put("imageId", "A");
        bg.put("capInsets", Arrays.asList(8.0, 6.0, 8.0, 6.0));
        Map<String, Object> st = imageStyle(bg);
        st.put("padding", Arrays.asList(10.0, 4.0, 10.0, 4.0));
        Map<String, Object> arrow = new HashMap<>();
        arrow.put("width", 10.0);
        arrow.put("height", 6.0);
        arrow.put("color", 0xFFFF8800L);
        st.put("arrow", arrow);
        Map<String, Object> sh = new HashMap<>();
        sh.put("color", 0x55000000L);
        sh.put("blurRadius", 3.0);
        sh.put("offset", Arrays.asList(0.0, 2.0));
        st.put("shadow", sh);
        RecordingSurface s = draw(presentation("ab", st), new Images("A"));
        List<String> c = s.calls;
        assertTrue(c.get(1), c.get(1).startsWith("imageShadow img:A 55000000 b=0x1.8p1 d=0x0.0p0,0x1.0p1"));
        assertTrue(c.get(2), c.get(2).startsWith("fillShadow ffff8800 55000000"));
        assertTrue(c.get(3), c.get(3).startsWith("image img:A "));
        assertTrue(c.get(4), c.get(4).startsWith("text 'ab'"));
        assertEquals("九宫格 9 块", 9, s.images.get(0).length);
        // 箭头底边伸进主体 1 物理像素（密度 2 → 0.5 逻辑像素），被图片盖住，不留缝
        double bodyBottom = s.images.get(0)[8][7];
        final double[] baseY = {Double.NaN};
        s.paths.get(0).accept(new Outline.Visitor() {
            @Override public void move(float x, float y) { baseY[0] = y; }
            @Override public void line(float x, float y) { }
            @Override public void cubic(float a, float b, float c2, float d, float e, float f) { }
            @Override public void close() { }
        });
        assertEquals(bodyBottom - 0.5, baseY[0], 1e-6);
    }

    // 图标 + 文字，左对齐：图标在 padL，文字在图标 + 间距之后
    @Test
    public void iconBeforeTextLeftAligned() throws Exception {
        Map<String, Object> bg = new HashMap<>();
        bg.put("type", "shape");
        bg.put("kind", "roundedRect");
        bg.put("fillColor", 0xFFFFFFFFL);
        Map<String, Object> st = imageStyle(bg);
        st.put("padding", Arrays.asList(6.0, 2.0, 6.0, 2.0));
        st.put("textAlign", "left");
        st.put("width", 100.0);
        Map<String, Object> p = presentation("abc", st);
        p.put("content", new HashMap<>(Map.of("text", "abc", "iconId", "I",
                "iconSize", Arrays.asList(12.0, 12.0), "iconSpacing", 3.0)));
        RecordingSurface s = draw(p, new Images("I"));
        double[] icon = s.images.get(0)[0];
        double bodyLeft = -50; // bodyCenter，宽 100
        assertEquals(bodyLeft + 6, icon[4], 0);
        assertEquals(bodyLeft + 6 + 12, icon[6], 0);
        assertEquals("文字在图标 + 间距之后", bodyLeft + 6 + 12 + 3, s.texts.get(0)[0], 0);
        assertEquals("图标与文字共用中线", (icon[5] + icon[7]) / 2, s.texts.get(0)[1], 1e-12);
    }
}
