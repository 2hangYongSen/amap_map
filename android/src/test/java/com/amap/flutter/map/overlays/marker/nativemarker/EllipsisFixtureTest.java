package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Map;

/** T-ELL-1（共享夹具）：等于不省略、超出以“…”结尾且宽度 ≤ avail、不拆字形簇、avail ≤ 0 不显示 */
public class EllipsisFixtureTest {

    @Test
    public void tEll1_casesMatchFixture() {
        TextMeasurer m = Fixtures.measurer();
        double font = Fixtures.num(Fixtures.section("ellipsis").get("fontSize"));
        for (Map<String, Object> c : Fixtures.cases("ellipsis")) {
            String name = (String) c.get("name");
            double avail = Fixtures.num(c.get("avail"));
            String got = Ellipsizer.ellipsize((String) c.get("text"), avail, m, font, 400);
            assertEquals(name, c.get("expected"), got);
            // 平台差异允许 1 个字符，但宽度上限是硬约束
            assertTrue(name, got.isEmpty() || m.width(got, font, 400) <= avail);
        }
    }

    @Test
    public void neverSplitsSurrogatePair() {
        TextMeasurer m = Fixtures.measurer();
        String text = "😀😀😀😀";
        for (double avail = 1; avail < 40; avail += 0.5) {
            String got = Ellipsizer.ellipsize(text, avail, m, 10, 400);
            for (int i = 0; i < got.length(); i++) {
                char ch = got.charAt(i);
                if (Character.isHighSurrogate(ch)) {
                    assertTrue("高位代理后必须跟低位代理",
                            i + 1 < got.length() && Character.isLowSurrogate(got.charAt(i + 1)));
                }
            }
        }
    }
}
