package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

/** §8.6 两阶段销毁：T-DISP-1/3/4/5 与 R-DISP-4 */
public class DisposeTest {

    private static FakeImages.Image produced(RenderHarness h, String id) {
        for (FakeImages.Image i : h.decoder.produced) {
            if (i.id.equals(id)) {
                return i;
            }
        }
        throw new AssertionError("没有解码过 " + id);
    }

    // T-DISP-1：任务执行期间 dispose，完成后不 addMarker、不发事件、输出不进缓存
    @Test
    public void tDisp1_lateOutputIsDiscarded() {
        RenderHarness h = new RenderHarness();
        h.manager.attach();
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.runMain(); // 任务进入 running，后台尚未执行
        int adds = h.host.count("add:");
        int events = h.emitted.size();
        h.manager.dispose();
        assertFalse(h.manager.isTerminated());
        assertEquals(1, h.loop.shutdownCalls);
        h.loop.drain();
        assertEquals("销毁后不得 addMarker", adds, h.host.count("add:"));
        assertEquals("销毁后不得发事件", events, h.emitted.size());
        assertEquals("迟到输出直接回收，不进缓存", 1, h.icons.discarded.size());
        assertTrue(h.icons.discarded.get(0).recycled);
        RenderInvariants.checkTerminated(h);
    }

    // T-DISP-3：任务在读取资源 A 中途 dispose；A releasing 且未回收，B 已释放，归还后 A 释放
    @Test
    public void tDisp3_runningInputSurvivesDispose() {
        RenderHarness h = new RenderHarness();
        h.images(Payloads.bytesImage("A"), Payloads.bytesImage("B"));
        h.add(Payloads.withImage("mB", "b", "B"));
        h.loop.drain();
        assertNotNull(h.point("mB").shown());
        h.add(Payloads.withImage("mA", "a", "A"));
        final boolean[] midRead = {false};
        h.painter.hook = job -> {
            if (job.spec.imageIds().contains("A")) {
                // 读取中途调用 dispose：同步返回，输入不得被回收
                h.manager.dispose();
                assertFalse("读取中 A 已被回收", job.image("A").isRecycled());
                midRead[0] = true;
            }
        };
        h.loop.runMain(); // A 的任务进入 running
        assertEquals(1, h.r().scheduler.runningCount());
        h.loop.runBg();    // 任务读 A，途中 dispose
        assertTrue(midRead[0]);
        ImageEntry a = h.r().registry.entry("A");
        assertNotNull(a);
        assertTrue(a.isReleasing());
        assertEquals(1, a.refs(ImageEntry.Ref.RUNNING));
        assertFalse(produced(h, "A").isRecycled());
        assertTrue("无执行中引用的 B 已释放", produced(h, "B").isRecycled());
        assertFalse(h.manager.isTerminated());
        assertEquals(0, h.painter.readRecycled);
        h.loop.drain(); // 归还
        assertTrue(produced(h, "A").isRecycled());
        RenderInvariants.checkTerminated(h);
    }

    // T-DISP-4：读取中抛异常，finally 仍归还引用，进入 terminated
    @Test
    public void tDisp4_exceptionStillReturnsRefs() {
        RenderHarness h = new RenderHarness();
        h.images(Payloads.bytesImage("A"));
        h.loop.drain();
        h.add(Payloads.withImage("mA", "a", "A"));
        h.painter.hook = job -> {
            throw new IllegalStateException("读取失败");
        };
        h.loop.runMain();
        h.manager.dispose();
        assertFalse(h.manager.isTerminated());
        h.loop.drain();
        assertTrue(produced(h, "A").isRecycled());
        RenderInvariants.checkTerminated(h);
    }

    // T-DISP-5：3 个 running 任务，只有最后一个归还后才 terminated
    @Test
    public void tDisp5_terminatedOnlyAfterLastReturns() {
        RenderHarness h = new RenderHarness(3);
        h.add(Payloads.nativeMarker("a", "a"), Payloads.nativeMarker("b", "b"),
                Payloads.nativeMarker("c", "c"));
        h.loop.runMain();
        assertEquals(3, h.r().scheduler.runningCount());
        h.manager.dispose();
        for (int left = 3; left > 0; left--) {
            assertFalse("还剩 " + left + " 个", h.manager.isTerminated());
            h.loop.bg.poll().run(); // 只让一个后台任务结束
            h.loop.runMain();
        }
        RenderInvariants.checkTerminated(h);
    }

    // R-DISP-4：10s 后仍有 running 任务，记录一次日志，仍不回收输入
    @Test
    public void stuckTaskIsLoggedOnceAndInputKept() {
        RenderHarness h = new RenderHarness();
        h.images(Payloads.bytesImage("A"));
        h.loop.drain();
        h.add(Payloads.withImage("mA", "a", "A"));
        h.loop.runMain();
        h.manager.dispose();
        assertEquals("只登记一次检查", 1, h.loop.delayed.size());
        h.loop.fireDelayed();
        assertEquals(1, h.r().stuckTasks());
        List<String> logs = new ArrayList<>(h.logs);
        assertEquals(1, logs.size());
        assertFalse("卡住时也不回收输入", produced(h, "A").isRecycled());
        h.loop.drain();
        assertTrue(produced(h, "A").isRecycled());
        RenderInvariants.checkTerminated(h);
    }

    // 没有 running 任务时 dispose 直接 terminated，不登记卡住检查
    @Test
    public void idleDisposeTerminatesImmediately() {
        RenderHarness h = new RenderHarness();
        h.add(Payloads.nativeMarker("a", "a"));
        h.loop.drain();
        h.manager.dispose();
        assertTrue(h.manager.isTerminated());
        assertTrue(h.loop.delayed.isEmpty());
        RenderInvariants.checkTerminated(h);
    }
}
