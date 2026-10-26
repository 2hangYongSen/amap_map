package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Map;

/** S10 审查修复：销毁时断开引用、后台 Error、主线程 toDescriptor 失败、执行器拒绝、排队解码撤销 */
public class RobustnessTest {

    private static int errors(RenderHarness h, String code) {
        int n = 0;
        for (int i = 0; i < h.emitted.size(); i++) {
            if ("marker#nativeError".equals(h.emitted.get(i))
                    && code.equals(h.emittedArgs.get(i).get("code"))) {
                n++;
            }
        }
        return n;
    }

    // 1. 提前 terminate：撤销 10s 卡住检查，断开对 host（amap、通道）的引用
    @Test
    public void earlyTerminateCancelsStuckCheckAndDropsHost() {
        RenderHarness h = new RenderHarness();
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.runMain(); // 任务 running
        h.manager.dispose();
        assertEquals(1, h.loop.delayed.size());
        h.loop.drain(); // 任务归还 → terminated
        assertTrue(h.manager.isTerminated());
        assertTrue("延迟任务应被撤销", h.loop.delayed.isEmpty());
        assertFalse("不应再持有 host", h.r().holdsHost());
        assertFalse("不应再持有事件出口", h.r().holdsSink());
    }

    // 2a. 后台绘制抛 OutOfMemoryError：进程不崩，报 renderFailed，引用归零
    @Test
    public void paintErrorReportsRenderFailed() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.painter.oom = true;
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.drain(); // Error 未被捕获时会从这里抛出
        assertEquals(1, errors(h, NativeRenderer.ERR_RENDER_FAILED));
        assertEquals(0, h.r().scheduler.runningCount());
        RenderInvariants.check(h);
    }

    // 2b. 后台解码抛 OutOfMemoryError：报 imageDecodeFailed，引用归零
    @Test
    public void decodeErrorReportsDecodeFailed() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.decoder.oom.add("A");
        h.images(Payloads.bytesImage("A"));
        h.add(Payloads.withImage("mA", "a", "A"));
        h.loop.drain();
        assertEquals(1, errors(h, ImageRegistry.ERR_DECODE_FAILED));
        assertEquals(ImageEntry.State.FAILED, h.r().registry.entry("A").state());
        RenderInvariants.check(h);
        h.remove("mA");
        h.loop.drain();
        h.manager.dispose();
        RenderInvariants.checkTerminated(h);
    }

    // 3. 主线程 toDescriptor 失败：记 failedKey、报 renderFailed，不写缓存，合成位图已回收
    @Test
    public void toDescriptorFailureReportsRenderFailed() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.icons.failToDescriptor = true;
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.drain(); // 异常未被捕获时会从这里抛出
        assertEquals(1, errors(h, NativeRenderer.ERR_RENDER_FAILED));
        assertEquals(0, h.r().cache.size());
        assertTrue(h.painter.outputs.get(0).recycled);
        assertEquals(h.point("a").normalKey(), h.point("a").failedKey[0]);
        RenderInvariants.check(h);
    }

    // 12. D-6：含图标或图片背景的点位走协议桩占位图标，不调度、不报 renderFailed；纯形状照常绘制
    @Test
    @SuppressWarnings("unchecked")
    public void iconMarkersUsePlaceholderUntilS11() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.painter.pureShapeOnly = true;
        h.images(Payloads.bytesImage("I"), Payloads.bytesImage("B"));
        Map<String, Object> withIcon = Payloads.nativeMarker("mi", "a");
        ((Map<String, Object>) ((Map<String, Object>) withIcon.get("nativePresentation"))
                .get("content")).put("iconId", "I");
        h.add(withIcon, Payloads.withImage("mb", "b", "B"), Payloads.nativeMarker("ms", "s"));
        h.loop.drain();
        assertEquals(FakeMarkerHost.DEFAULT_ICON, h.iconOf("mi"));
        assertEquals(FakeMarkerHost.DEFAULT_ICON, h.iconOf("mb"));
        assertEquals("只有纯形状点被绘制", 1, h.painter.count());
        assertTrue(h.iconOf("ms") instanceof FakeRender.Descriptor);
        assertEquals(0, errors(h, NativeRenderer.ERR_RENDER_FAILED));
        RenderInvariants.check(h);
        // 纯形状改成含图片：换回占位图标，原生显示引用归还
        h.change(Payloads.withImage("ms", "s", "B"));
        h.loop.drain();
        assertEquals(FakeMarkerHost.DEFAULT_ICON, h.iconOf("ms"));
        RenderInvariants.check(h);
        h.manager.dispose();
        RenderInvariants.checkTerminated(h);
    }

    // 7. 执行器拒绝：立即在主线程归还，running 归零
    @Test
    public void rejectedTaskReturnsImmediately() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.loop.rejecting = true;
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.runMain();
        assertEquals(0, h.r().scheduler.runningCount());
        assertTrue(h.r().scheduler.tasks().isEmpty());
        assertEquals(1, errors(h, NativeRenderer.ERR_RENDER_FAILED));
        h.manager.dispose();
        RenderInvariants.checkTerminated(h);
    }

    // 8'. 已提交到执行器但未开始的绘制，dispose 后不再执行，只走归还
    @Test
    public void queuedPaintIsSkippedOnDispose() {
        RenderHarness h = new RenderHarness();
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.runMain(); // 已提交到执行器
        h.manager.dispose();
        h.loop.drain();
        assertEquals("排队绘制不应执行", 0, h.painter.count());
        RenderInvariants.checkTerminated(h);
    }

    // 8. 排队中的解码在 dispose 后不再执行（解码计数不变），管理器照常 terminated
    @Test
    public void queuedDecodesAreDroppedOnDispose() {
        RenderHarness h = new RenderHarness();
        h.images(Payloads.bytesImage("A"), Payloads.bytesImage("B"));
        assertEquals(2, h.loop.bg.size());
        h.manager.dispose();
        h.loop.drain();
        assertEquals("排队解码不应执行", 0, h.decoder.calls);
        assertTrue(h.decoder.produced.isEmpty());
        RenderInvariants.checkTerminated(h);
        assertNull(h.r().registry.entry("A"));
    }
}
