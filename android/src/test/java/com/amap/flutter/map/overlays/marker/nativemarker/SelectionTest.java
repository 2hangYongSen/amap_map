package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.List;
import java.util.Map;

/** T-SEL-1～5：原生选择状态机（§11），外观由调度器异步补齐 */
public class SelectionTest {
    private final RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    private List<Map<String, Object>> changes() {
        return h.events("marker#selectionChanged");
    }

    private Object normalIcon(String id) {
        return h.r().cache.get(h.point(id).normalKey()).descriptor;
    }

    private Object selectedIcon(String id) {
        return h.r().cache.get(h.point(id).selectedKey()).descriptor;
    }

    /** 推进到两个普通态都已显示；此时 A 的选中态预热已开始、B 的仍在排队 */
    private void untilNormalsShown(String... ids) {
        for (int i = 0; i < 50; i++) {
            h.loop.runMain();
            h.loop.frame();
            boolean all = true;
            for (String id : ids) {
                all &= h.host.hasMarker(id);
            }
            if (all) {
                return;
            }
            h.loop.runBg();
        }
        throw new AssertionError("普通态未全部显示");
    }

    // T-SEL-1：A → B → 取消，revision 1/2/3，事件早于外观，迟到的 A 选中态不应用
    @Test
    public void tSel1_eventsBeforeAppearanceAndLateResultDropped() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"), Payloads.selectable("B", "b"));
        untilNormalsShown("A", "B");
        assertEquals(1, h.select("A"));
        assertEquals("事件不等外观", 1, changes().size());
        assertEquals(normalIcon("A"), h.iconOf("A"));
        assertEquals(2, h.select("B"));
        assertEquals(3, h.select(null));
        List<Map<String, Object>> c = changes();
        assertEquals(3, c.size());
        assertNull(c.get(0).get("previousId"));
        assertEquals("A", c.get(1).get("previousId"));
        assertEquals("B", c.get(2).get("previousId"));
        assertEquals("api", c.get(2).get("reason"));
        h.loop.drain();
        assertTrue("A 的选中态结果进了缓存", h.r().cache.contains(h.point("A").selectedKey()));
        assertEquals("迟到结果不覆盖普通态", normalIcon("A"), h.iconOf("A"));
        assertEquals(normalIcon("B"), h.iconOf("B"));
        assertEquals(0, h.host.count("setIcon:"));
    }

    // 选中态就绪时立即切换，zIndex 取 selectedZIndex；取消后恢复
    @Test
    public void selectSwitchesAppearanceAndZIndex() {
        h.enableSelection();
        h.add(Payloads.selectableZ("A", "a", 1, 99));
        h.loop.drain();
        int painted = h.painter.count();
        h.manager.onMarkerTap("A");
        assertEquals("markerTap", changes().get(0).get("reason"));
        h.loop.drain();
        assertEquals(selectedIcon("A"), h.iconOf("A"));
        assertEquals(99f, h.host.markers.get("A").zIndex, 0);
        h.manager.onMarkerTap("A"); // deselectOnRetap
        assertEquals("retap", changes().get(1).get("reason"));
        h.loop.drain();
        assertEquals(normalIcon("A"), h.iconOf("A"));
        assertEquals(1f, h.host.markers.get("A").zIndex, 0);
        assertEquals("切换不重新绘制", painted, h.painter.count());
    }

    // T-SEL-2：相同 id 不发事件、revision 不变；回调里反复回写也不循环
    @Test
    public void tSel2_sameIdIsNoop() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"));
        h.loop.drain();
        assertEquals(1, h.select("A"));
        for (int i = 0; i < 10; i++) {
            assertEquals(1, h.select("A")); // 模拟 Dart 在回调中回写
        }
        assertEquals(1, changes().size());
        assertEquals(1, h.select("A"));
        assertEquals(2, h.select(null));
        assertEquals(2, h.select(null));
        assertEquals(2, changes().size());
    }

    // T-SEL-3：选中点删除后重新加入，选中态恢复，期间不发选择事件
    @Test
    public void tSel3_removedSelectionRestoredOnReAdd() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"));
        h.loop.drain();
        h.select("A");
        h.loop.drain();
        h.remove("A");
        assertEquals("A", h.manager.selection().selectedId());
        h.add(Payloads.selectable("A", "a"));
        h.loop.drain();
        assertEquals(1, changes().size());
        assertEquals(selectedIcon("A"), h.iconOf("A"));
    }

    // T-SEL-4：选中点改为不可选择，发 invalidated 并恢复普通态
    @Test
    public void tSel4_unselectableInvalidates() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"));
        h.loop.drain();
        h.select("A");
        h.loop.drain();
        Map<String, Object> plain = Payloads.selectable("A", "a");
        plain.put("selectable", false);
        h.change(plain);
        Map<String, Object> last = changes().get(changes().size() - 1);
        assertEquals("invalidated", last.get("reason"));
        assertNull(last.get("selectedId"));
        h.loop.drain();
        assertEquals(normalIcon("A"), h.iconOf("A"));
    }

    // T-SEL-5：点击非 selectable 点选择不变、onTap 照常；地图单击按 deselectOnMapTap 取消
    @Test
    public void tSel5_nonSelectableTapKeepsSelection() {
        h.enableSelection();
        h.add(Payloads.selectable("A", "a"), Payloads.nativeMarker("D", "district"));
        h.loop.drain();
        h.manager.onMarkerTap("D");
        assertEquals(0, changes().size());
        assertEquals(1, h.events("marker#onTap").size());
        h.manager.onMarkerTap("A");
        // R-SEL-3：同一次点击先 selectionChanged 再 onTap
        int n = h.emitted.size();
        assertEquals("marker#selectionChanged", h.emitted.get(n - 2));
        assertEquals("marker#onTap", h.emitted.get(n - 1));
        h.manager.onMarkerTap("D");
        assertEquals("A", h.manager.selection().selectedId());
        assertEquals(1, changes().size());
        assertEquals(3, h.events("marker#onTap").size());
        h.manager.onMapTap();
        assertEquals("mapTap", changes().get(1).get("reason"));
        h.loop.drain();
    }
}
