package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.List;
import java.util.Map;

/** T-GEO-1 与 T-GEO-3（共享夹具） */
public class GeometryFixtureTest {

    private static double tol() {
        return Fixtures.num(Fixtures.section("geometry").get("tolerancePx"));
    }

    @Test
    @SuppressWarnings("unchecked")
    public void tGeo1_unionAndCanvasMatchFixture() throws Exception {
        TextMeasurer m = Fixtures.measurer();
        for (Map<String, Object> c : Fixtures.cases("geometry")) {
            String name = (String) c.get("name");
            double d = Fixtures.num(c.get("density"));
            NativeMarkerSpec spec = NativeMarkerSpec.parse((Map<?, ?>) c.get("presentation"));
            NativeMarkerLayout l = NativeMarkerLayout.compute(spec, Norm.ratioUnits(d), m,
                    new Fixtures.FakeResolver());
            List<Object> u = (List<Object>) c.get("union");
            // 逻辑像素误差换算到物理像素后 ≤ 0.5
            double t = tol() / d;
            assertEquals(name + " U.left", Fixtures.num(u.get(0)), l.union.left, t);
            assertEquals(name + " U.top", Fixtures.num(u.get(1)), l.union.top, t);
            assertEquals(name + " U.right", Fixtures.num(u.get(2)), l.union.right, t);
            assertEquals(name + " U.bottom", Fixtures.num(u.get(3)), l.union.bottom, t);
            assertCanvas(name, c, l.px, l.py, l.width, l.height);
            if (c.containsKey("normalText")) {
                assertEquals(name + " 文字", c.get("normalText"), l.normal.displayText);
            }
            assertAnchorsCoincide(name, l);
        }
    }

    @Test
    @SuppressWarnings("unchecked")
    public void tGeo3_pixelizationMatchesFixture() {
        for (Map<String, Object> c : Fixtures.cases("pixelization")) {
            String name = (String) c.get("name");
            double d = Fixtures.num(c.get("density"));
            List<Object> u = (List<Object>) c.get("union");
            RectD r = new RectD(Fixtures.num(u.get(0)), Fixtures.num(u.get(1)),
                    Fixtures.num(u.get(2)), Fixtures.num(u.get(3)));
            int[] p = NativeMarkerLayout.pixelize(r, d);
            assertCanvas(name, c, p[0], p[1], p[2], p[3]);
            // 通用不变量：U 完整落在画布内，W ≥ ceil(U.width × d)，u × W == px
            assertTrue(name, p[2] >= Math.ceil(r.width() * d - 1e-9));
            assertTrue(name, p[3] >= Math.ceil(r.height() * d - 1e-9));
            assertTrue(name, p[0] + r.left * d >= -1e-9 && p[1] + r.top * d >= -1e-9);
            assertTrue(name, p[0] + r.right * d <= p[2] + 1e-9);
            assertTrue(name, p[1] + r.bottom * d <= p[3] + 1e-9);
            assertTrue(name, p[2] >= 1 && p[3] >= 1);
            assertEquals(name, p[0], (p[0] / (double) p[2]) * p[2], 1e-9);
        }
    }

    private static void assertCanvas(String name, Map<String, Object> c, int px, int py, int w, int h) {
        assertEquals(name + " px", (int) Fixtures.num(c.get("px")), px);
        assertEquals(name + " py", (int) Fixtures.num(c.get("py")), py);
        assertEquals(name + " W", (int) Fixtures.num(c.get("width")), w);
        assertEquals(name + " H", (int) Fixtures.num(c.get("height")), h);
    }

    /** R-GEO-1：两态各自的 visibleRect 平移 -a 后都落在 U 内，地理点两态重合 */
    private static void assertAnchorsCoincide(String name, NativeMarkerLayout l) {
        for (StateLayout s : new StateLayout[]{l.normal, l.selected}) {
            RectD v = s.visible.offset(-s.anchorX, -s.anchorY);
            assertTrue(name, v.left >= l.union.left - 1e-9 && v.top >= l.union.top - 1e-9);
            assertTrue(name, v.right <= l.union.right + 1e-9 && v.bottom <= l.union.bottom + 1e-9);
        }
    }
}
