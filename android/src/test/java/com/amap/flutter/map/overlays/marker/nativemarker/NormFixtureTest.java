package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.List;
import java.util.Map;

/** T-NORM-1（JVM 端）：舍入结果与 Dart 共用同一份夹具 */
public class NormFixtureTest {

    private static int units(String kind, double v) throws InvalidMarkerException {
        return "length".equals(kind) ? Norm.lengthUnits(v) : Norm.ratioUnits(v);
    }

    @Test
    public void scalesMatchFixture() {
        Map<String, Object> n = Fixtures.section("normalization");
        assertEquals(Norm.LENGTH_SCALE, Fixtures.num(n.get("lengthScale")), 0);
        assertEquals(Norm.RATIO_SCALE, Fixtures.num(n.get("ratioScale")), 0);
    }

    @Test
    @SuppressWarnings("unchecked")
    public void tNorm1_casesMatchFixture() throws Exception {
        List<Map<String, Object>> cases = Fixtures.cases("normalization");
        for (Map<String, Object> c : cases) {
            int got = units((String) c.get("kind"), Fixtures.num(c.get("input")));
            assertEquals((String) c.get("name"), (int) Fixtures.num(c.get("units")), got);
        }
    }

    @Test
    @SuppressWarnings("unchecked")
    public void sameGroupsNormalizeEqually() throws Exception {
        List<Map<String, Object>> groups =
                (List<Map<String, Object>>) Fixtures.section("normalization").get("sameGroups");
        for (Map<String, Object> g : groups) {
            List<Object> inputs = (List<Object>) g.get("inputs");
            String kind = (String) g.get("kind");
            int first = units(kind, Fixtures.num(inputs.get(0)));
            for (Object in : inputs) {
                assertEquals((String) g.get("name"), first, units(kind, Fixtures.num(in)));
            }
        }
    }

    @Test
    public void nonFiniteAndHugeRejected() {
        for (double v : new double[]{Double.NaN, Double.POSITIVE_INFINITY,
                Double.NEGATIVE_INFINITY, 1e300, 4e7}) {
            try {
                Norm.lengthUnits(v);
                fail("应拒绝 " + v);
            } catch (InvalidMarkerException expected) {
                // 期望抛出
            }
        }
    }

    @Test
    public void roundHalfAwayFromZeroEdges() {
        assertEquals(0, Norm.roundHalfAwayFromZero(0.49999999999999994));
        assertEquals(1, Norm.roundHalfAwayFromZero(0.5));
        assertEquals(-1, Norm.roundHalfAwayFromZero(-0.5));
        assertEquals(-2, Norm.roundHalfAwayFromZero(-1.5));
        assertEquals(0, Norm.roundHalfAwayFromZero(-0.0));
    }
}
