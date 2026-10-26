package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.Map;

/** T-CACHE-7/8：选中点的普通态备用引用（R-CACHE-6） */
public class RetainedNormalTest {
    private RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    private RenderCache.Entry normal(String id) {
        return h.r().cache.get(h.point(id).normalKey());
    }

    /** 新增并选中，推进到选中态已显示 */
    private void addSelected(String id, String text) {
        h.add(Payloads.selectable(id, text));
        h.loop.drain();
        h.select(id);
        h.loop.drain();
    }

    // T-CACHE-7：选中后淘汰压力下普通态被保留；取消选择无需绘制、无需 Dart 回传
    @Test
    public void tCache7_retainedSurvivesEvictionAndRestores() {
        h = new RenderHarness(1, 20_000); // 每条 10_000：普通 + 选中即满
        h.enableSelection();
        addSelected("A", "a");
        RenderCache.Entry n = normal("A");
        assertEquals(0, n.displayRefs());
        assertEquals(1, n.retainedRefs());
        h.r().cache.evictAllEvictable(); // 制造淘汰压力
        h.add(Payloads.nativeMarker("X", "x"), Payloads.nativeMarker("Y", "y"));
        h.loop.drain();
        assertTrue("备用未被淘汰", h.r().cache.contains(n.key));
        int painted = h.painter.count();
        int calls = h.emitted.size();
        h.manager.onMapTap();
        h.loop.drain();
        assertEquals("无需绘制", painted, h.painter.count());
        assertEquals("只发了一次选择事件", calls + 1, h.emitted.size());
        assertEquals(n.descriptor, h.iconOf("A"));
        assertEquals(1, n.displayRefs());
        assertEquals(0, n.retainedRefs());
        assertNull(h.point("A").retainedNormal());
    }

    // T-CACHE-8a：A→B，A 恢复普通态并归还备用，B 取得备用
    @Test
    public void tCache8_switchReturnsRetained() {
        h.enableSelection();
        h.add(Payloads.selectable("B", "b"));
        addSelected("A", "a");
        h.select("B");
        h.loop.drain();
        assertNull(h.point("A").retainedNormal());
        assertEquals(1, normal("A").displayRefs());
        assertNotNull(h.point("B").retainedNormal());
        assertEquals(1, normal("B").retainedRefs());
    }

    // T-CACHE-8b：选中点改样式，旧备用立即归还；迟到的新普通态只更新备用，不覆盖选中外观
    @Test
    public void tCache8_styleChangeReplacesRetained() {
        h.enableSelection();
        addSelected("A", "a");
        RenderCache.Entry oldN = normal("A");
        Object selIcon = h.iconOf("A");
        h.change(Payloads.selectable("A", "a2"));
        assertEquals("旧备用立即归还", 0, oldN.retainedRefs());
        h.loop.drain();
        PointTable.Entry e = h.point("A");
        assertEquals(e.normalKey(), e.retainedNormal().key);
        assertTrue(e.shownSelected());
        assertEquals(h.r().cache.get(e.selectedKey()).descriptor, h.iconOf("A"));
        assertTrue("选中样式也变了，显示新选中态", !selIcon.equals(h.iconOf("A")));
    }

    // T-CACHE-8c：纯位置变化保留原备用，不增加绘制
    @Test
    public void tCache8_positionKeepsRetained() {
        h.enableSelection();
        h.add(Payloads.selectableAt("A", "a", 39.9));
        h.loop.drain();
        h.select("A");
        h.loop.drain();
        RenderCache.Entry n = h.point("A").retainedNormal();
        int painted = h.painter.count();
        h.change(Payloads.selectableAt("A", "a", 40.1));
        h.loop.drain();
        assertEquals(n, h.point("A").retainedNormal());
        assertEquals(painted, h.painter.count());
        assertEquals(40.1, h.lat("A"), 1e-9);
    }

    // T-CACHE-8d：删除归还备用
    @Test
    public void tCache8_removeReturnsRetained() {
        h.enableSelection();
        addSelected("A", "a");
        RenderCache.Entry n = normal("A");
        h.remove("A");
        assertEquals(0, n.retainedRefs());
        assertTrue(n.evictable());
    }

    // T-CACHE-8e：切 icon 归还备用与选中显示
    @Test
    public void tCache8_toIconReturnsRetained() {
        h.enableSelection();
        addSelected("A", "a");
        RenderCache.Entry n = normal("A");
        RenderCache.Entry s = h.r().cache.get(h.point("A").selectedKey());
        Map<String, Object> icon = Payloads.icon("A", "pin");
        h.change(icon);
        assertEquals(0, n.retainedRefs());
        assertEquals(0, s.displayRefs());
        assertEquals("icon:pin", h.iconOf("A"));
    }

    // T-CACHE-8f：销毁归还备用（tearDown 检查归零与 terminated）
    @Test
    public void tCache8_disposeReturnsRetained() {
        h.enableSelection();
        addSelected("A", "a");
        assertEquals(1, normal("A").retainedRefs());
    }

    // 普通态尚未就绪时选中：选中态（P0）先出现，普通态完成后只登记备用，不覆盖选中外观
    @Test
    public void selectBeforeNormalReady() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"));
        h.select("A");
        h.loop.drain();
        PointTable.Entry e = h.point("A");
        assertTrue(e.shownSelected());
        assertEquals(e.normalKey(), e.retainedNormal().key);
        assertEquals(2, h.painter.count());
    }
}
