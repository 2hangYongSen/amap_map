package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/** 完整模式下的管理器：T-NAT-REJ-1、T-INIT-3、T-PROTO-2、资源、帧预算 */
public class NativeMarkerRenderTest {
    private final RenderHarness h = new RenderHarness();

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    // T-NAT-REJ-1：同批 add(A)、add(B 非法)、change(C 非法)
    @Test
    @SuppressWarnings("unchecked")
    public void tNatRej1_rejectsOnlyInvalidMarkers() {
        h.add(Payloads.nativeMarker("C", "c0"));
        h.loop.drain();
        PointTable.Entry c = h.point("C");
        int gen = c.generation();
        FullMarkerOptions desired = c.desired();
        RenderCache.Entry shown = c.shown();

        Map<String, Object> badB = Payloads.nativeMarker("B", "b");
        badB.put("renderMode", null);
        Map<String, Object> badC = Payloads.nativeMarker("C", "c1");
        ((Map<String, Object>) ((Map<String, Object>) badC.get("nativePresentation"))
                .get("style")).put("fontSize", 0.001);
        Map<String, Object> u = Payloads.add(9, Payloads.nativeMarker("A", "a"), badB);
        u.put("markersToChange", Collections.singletonList(badC));
        Map<String, Object> r = h.manager.update(u);
        h.loop.drain();

        assertEquals(Arrays.asList("B", "C"), r.get("rejectedMarkerIds"));
        assertTrue(h.host.hasMarker("A"));
        assertNull(h.point("B"));
        assertFalse(h.host.hasMarker("B"));
        assertEquals(gen, c.generation());
        assertSame(desired, c.desired());
        assertSame(shown, c.shown());
        assertEquals(shown.descriptor, h.iconOf("C"));
    }

    // T-INIT-3：attach 前资源解码完成，不发事件；attach 返回值包含该资源
    @Test
    @SuppressWarnings("unchecked")
    public void tInit3_imagesBeforeAttachOnlyInSnapshot() {
        Map<String, Object> params = Payloads.add(0, Payloads.withImage("m", "t", "img"));
        params.put("imagesToAdd", Collections.singletonList(Payloads.bytesImage("img")));
        h.manager.applyCreation(params);
        h.loop.drain();
        assertTrue("握手前不得发送事件", h.emitted.isEmpty());
        assertTrue(h.host.hasMarker("m"));
        Map<String, Object> snap = h.manager.attach();
        Map<String, Object> images = (Map<String, Object>) snap.get("images");
        assertEquals(Collections.singletonList("img"), images.get("ready"));
        assertEquals(1, snap.get("lastEventSeq"));
        assertTrue(h.emitted.isEmpty());
    }

    // 握手后资源结果实时发送；失败时降级 key，图片背景用默认背景绘制
    @Test
    public void imageFailureAfterAttachEmitsAndFallsBack() {
        h.manager.attach();
        h.decoder.failing.add("bad");
        h.images(Payloads.bytesImage("bad"));
        h.add(Payloads.withImage("m", "t", "bad"));
        assertFalse("资源 pending 时不 addMarker（R-RES-5）", h.host.hasMarker("m"));
        h.loop.drain();
        assertTrue(h.emitted.contains("marker#imagesResult"));
        assertTrue(h.emitted.contains("marker#nativeError"));
        assertTrue(h.host.hasMarker("m"));
        Fixtures.FakeResolver fallback = new Fixtures.FakeResolver();
        fallback.failed.add("bad");
        assertEquals(RenderKey.normalKey(h.point("m").desired().spec, 2880, fallback),
                h.point("m").shown().key);
    }

    // T-PROTO-2（完整模式）：native(A) → icon(X)，没有残留任务、缓存显示引用归还
    @Test
    public void tProto2_nativeToIconClearsTasksAndRefs() {
        h.add(Payloads.nativeMarker("p", "A"));
        h.loop.drain();
        RenderCache.Entry shown = h.point("p").shown();
        h.change(Payloads.nativeMarker("p", "A2"));
        h.change(Payloads.icon("p", "X")); // 新 key 的任务还在排队
        assertNull(h.point("p"));
        assertTrue("调度器中不应残留该点的任务", h.r().scheduler.tasks().isEmpty());
        assertEquals(0, shown.displayRefs());
        h.loop.drain();
        assertEquals("icon:X", h.iconOf("p"));
    }

    // §8.4：普通态全部画完后在同一帧一次放完，不受 4ms 预算限制
    @Test
    @SuppressWarnings("unchecked")
    public void normalAppliesAllInOneFrameWhenPaintsDone() {
        h.host.onNativeCall = () -> h.loop.now += 1_000_000; // 每次 SDK 调用 1ms
        Map<String, Object>[] ms = new Map[10];
        for (int i = 0; i < 10; i++) {
            ms[i] = Payloads.nativeMarker("f" + i, "k" + i);
        }
        h.add(ms);
        h.loop.runMain();
        h.loop.bg.poll().run(); // 只画完一个
        h.loop.runMain();
        h.loop.frame();
        assertEquals("还有普通态没画完：不放", 0, h.host.count("add:"));
        h.loop.drainNoFrame();
        h.loop.frame();
        assertEquals("全部画完：同一帧放完", 10, h.host.count("add:"));
    }

    // §8.4：攒超过 300ms 仍有普通态没画完，先按每帧预算放已画好的
    @Test
    @SuppressWarnings("unchecked")
    public void holdTimesOutAndAppliesByBudget() {
        h.host.onNativeCall = () -> h.loop.now += 1_000_000;
        Map<String, Object>[] ms = new Map[10];
        for (int i = 0; i < 10; i++) {
            ms[i] = Payloads.nativeMarker("t" + i, "k" + i);
        }
        h.add(ms);
        // 逐个画完 9 个，第 10 个派发后卡住不执行
        h.loop.runMain();
        while (h.host.count("add:") == 0 && h.loop.bg.size() + h.loop.mainQ.size() > 0) {
            if (h.loop.bg.size() == 1 && h.r().scheduler.tasks().size() == 1) {
                break;
            }
            h.loop.runBg();
            h.loop.runMain();
        }
        Runnable stuck = h.loop.bg.poll();
        h.loop.frame();
        assertEquals("攒着：还有 1 个没画完", 0, h.host.count("add:"));
        h.loop.now += FrameApplier.HOLD_TIMEOUT_NANOS;
        h.loop.frame();
        assertEquals("超时：按 4ms 预算放", 4, h.host.count("add:"));
        h.loop.frame();
        assertEquals(8, h.host.count("add:"));
        stuck.run();
        h.loop.drain();
        assertEquals(10, h.host.count("add:"));
    }

    // R-GEN-6 immediate 删除：remove() 之后才归还显示引用，期望引用与资源一起释放
    @Test
    public void removeReturnsAllRefs() {
        h.images(Payloads.bytesImage("img"));
        h.add(Payloads.withImage("m", "t", "img"));
        h.loop.drain();
        RenderCache.Entry shown = h.point("m").shown();
        h.manager.update(releaseAndRemove("img", "m"));
        assertNull(h.point("m"));
        assertFalse(h.host.hasMarker("m"));
        assertEquals(0, shown.displayRefs());
        assertNull("资源 releasing 且无引用后立即释放", h.r().registry.entry("img"));
    }

    private static Map<String, Object> releaseAndRemove(String imageId, String markerId) {
        Map<String, Object> u = Payloads.update(50, new java.util.ArrayList<Object>(
                Collections.singletonList(markerId)));
        u.put("imageIdsToRelease", Collections.singletonList(imageId));
        return u;
    }

    // 绘制失败：报 renderFailed 一次，不自动重试，key 变化后重新调度
    @Test
    public void renderFailureReportedOnce() {
        h.manager.attach();
        h.add(Payloads.nativeMarker("a", "boom"));
        h.painter.failing.add(h.point("a").normalKey());
        h.loop.drain();
        assertFalse(h.host.hasMarker("a"));
        List<String> errs = h.emitted;
        assertEquals(1, Collections.frequency(errs, "marker#nativeError"));
        h.change(Payloads.nativeAt("a", "boom", 5.0));
        h.loop.drain();
        assertEquals("同 key 不重试", 1, Collections.frequency(errs, "marker#nativeError"));
        h.change(Payloads.nativeMarker("a", "ok"));
        h.loop.drain();
        assertTrue(h.host.hasMarker("a"));
    }
}
