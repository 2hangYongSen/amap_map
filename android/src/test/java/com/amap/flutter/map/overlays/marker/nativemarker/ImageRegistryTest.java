package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

/** T-RES-1/2/3/8/9 与 epoch、快照 */
public class ImageRegistryTest {
    private static final long MIB = 1024 * 1024;
    private FakeImages.Decoder decoder;
    private FakeImages.ManualRunner runner;
    private FakeImages.Events events;
    private ImageRegistry registry;

    @Before
    public void setUp() {
        decoder = new FakeImages.Decoder();
        runner = new FakeImages.ManualRunner();
        events = new FakeImages.Events();
        registry = new ImageRegistry(decoder, runner);
        registry.setListener(events);
    }

    @After
    public void tearDown() {
        // §15 不变量：每个测试结束时引用计数全部归零
        FakeImages.assertAllRefsZero(registry);
    }

    private FakeImages.Image readyImage(String id) {
        registry.register(FakeImages.bytes(id));
        runner.drain();
        return (FakeImages.Image) registry.entry(id).decoded();
    }

    // T-RES-1：执行中任务持有 A 时下发 release A，不回收；任务归还后才释放
    @Test
    public void tRes1_releaseWhileRunningKeepsDecoded() {
        FakeImages.Image a = readyImage("A");
        registry.acquire("A", ImageEntry.Ref.RUNNING);
        registry.release("A");
        ImageEntry e = registry.entry("A");
        assertNotNull(e);
        assertTrue(e.isReleasing());
        assertEquals(1, e.totalRefs());
        assertFalse("执行中任务仍在读取，不能回收", a.isRecycled());

        registry.unref("A", ImageEntry.Ref.RUNNING);
        assertNull("refs 归零后条目被释放", registry.entry("A"));
        assertTrue(a.isRecycled());
    }

    // T-RES-2：排队任务被取消时归还引用，不泄漏
    @Test
    public void tRes2_cancelledQueuedTaskReturnsRef() {
        readyImage("A");
        registry.acquire("A", ImageEntry.Ref.DESIRED);
        registry.acquire("A", ImageEntry.Ref.QUEUED);
        registry.acquire("A", ImageEntry.Ref.QUEUED);
        // 点位被删除：撤销排队任务、撤销期望引用
        registry.unref("A", ImageEntry.Ref.QUEUED);
        registry.unref("A", ImageEntry.Ref.QUEUED);
        registry.unref("A", ImageEntry.Ref.DESIRED);
        assertEquals(0, registry.entry("A").totalRefs());
        registry.release("A");
        assertNull(registry.entry("A"));
    }

    @Test(expected = IllegalStateException.class)
    public void unbalancedUnrefFailsFast() {
        readyImage("A");
        registry.unref("A", ImageEntry.Ref.QUEUED);
    }

    // T-RES-3：releasing 中再次 imagesToAdd：ready 不重新解码；failed 重新解码并恢复
    @Test
    public void tRes3_reAddWhileReleasing() {
        FakeImages.Image a = readyImage("A");
        registry.acquire("A", ImageEntry.Ref.RUNNING);
        registry.release("A");
        int decodes = registry.decodeCount();
        registry.register(FakeImages.bytes("A"));
        runner.drain();
        assertEquals("ready 资源不重新解码", decodes, registry.decodeCount());
        assertFalse(registry.entry("A").isReleasing());
        assertEquals(ImageEntry.State.READY, registry.entry("A").state());
        assertFalse(a.isRecycled());
        registry.unref("A", ImageEntry.Ref.RUNNING);
        assertNotNull("取消 releasing 后归还引用不应释放", registry.entry("A"));

        decoder.failing.add("B");
        registry.register(FakeImages.asset("B"));
        runner.drain();
        assertEquals(ImageEntry.State.FAILED, registry.entry("B").state());
        assertFalse(registry.usable("B"));
        registry.acquire("B", ImageEntry.Ref.DESIRED);
        registry.release("B");
        int epoch = registry.entry("B").epoch();
        decoder.failing.clear();
        registry.register(FakeImages.asset("B"));
        assertEquals(ImageEntry.State.PENDING, registry.entry("B").state());
        assertTrue("重试换新 epoch", registry.entry("B").epoch() != epoch);
        runner.drain();
        assertEquals(ImageEntry.State.READY, registry.entry("B").state());
        assertTrue(registry.usable("B"));
        assertEquals(Arrays.asList("ready:A", "failed:B", "ready:B"), events.log);
        registry.unref("B", ImageEntry.Ref.DESIRED);
    }

    // S18：failed 后重新登记时使用新来源（与 iOS registerSource: 一致），T-RES-13 依赖
    @Test
    public void failedRetryUsesLatestSource() {
        ImageSource bad = new ImageSource("P", ImageSource.TYPE_ASSET, null, "assets/missing.png", null, 2.0);
        decoder.failingAssets.add("assets/missing.png");
        registry.register(bad);
        runner.drain();
        assertEquals(ImageEntry.State.FAILED, registry.entry("P").state());
        registry.register(FakeImages.asset("P"));
        runner.drain();
        assertEquals("重试应读取新的 asset 名", ImageEntry.State.READY, registry.entry("P").state());
        assertEquals("assets/P.png", registry.entry("P").source.asset);
        // ready 后再登记不同来源：不重新解码，来源不变
        int decodes = registry.decodeCount();
        registry.register(bad);
        runner.drain();
        assertEquals(decodes, registry.decodeCount());
        assertEquals("assets/P.png", registry.entry("P").source.asset);
    }

    // T-RES-8：12 个 1MiB 资源，4 个被任务引用；淘汰只发生在另外 8 个中
    @Test
    public void tRes8_evictOnlyUnreferenced() {
        decoder.bytesPer = MIB;
        for (int i = 0; i < 12; i++) {
            registry.register(FakeImages.bytes("r" + i));
            registry.acquire("r" + i, ImageEntry.Ref.DESIRED);
        }
        // 解码完成前先让 4 个被任务引用
        for (int i = 0; i < 4; i++) {
            registry.acquire("r" + i, ImageEntry.Ref.QUEUED);
        }
        runner.drain();
        int evicted = 0;
        for (int i = 0; i < 12; i++) {
            ImageEntry e = registry.entry("r" + i);
            if (i < 4) {
                assertNotNull("被任务引用的不得淘汰", e.decoded());
            } else if (e.isEvicted()) {
                evicted++;
            }
            assertTrue("淘汰后状态仍为 ready", e.state() == ImageEntry.State.READY);
        }
        assertEquals("12MiB - 8MiB 预算 = 淘汰 4 个", 4, evicted);
        assertTrue(registry.decodedBytes() <= 8 * MIB);
        for (FakeImages.Image img : decoder.produced) {
            boolean protectedImg = Arrays.asList("r0", "r1", "r2", "r3").contains(img.id);
            assertFalse(protectedImg && img.isRecycled());
        }
        for (int i = 0; i < 12; i++) {
            if (i < 4) {
                registry.unref("r" + i, ImageEntry.Ref.QUEUED);
            }
            registry.unref("r" + i, ImageEntry.Ref.DESIRED);
        }
    }

    // 被引用的总量超预算：记录 decodedOverBudget，不强制回收
    @Test
    public void referencedOverBudgetIsReportedNotRecycled() {
        decoder.bytesPer = 3 * MIB;
        for (int i = 0; i < 4; i++) {
            registry.register(FakeImages.bytes("r" + i));
            registry.acquire("r" + i, ImageEntry.Ref.RUNNING);
        }
        runner.drain();
        assertTrue(registry.decodedOverBudget());
        for (FakeImages.Image img : decoder.produced) {
            assertFalse(img.isRecycled());
        }
        for (int i = 0; i < 4; i++) {
            registry.unref("r" + i, ImageEntry.Ref.RUNNING);
        }
        assertFalse("归还后按 LRU 淘汰回到预算内", registry.decodedOverBudget());
    }

    // T-RES-9：淘汰后新任务引用时从保留的原始数据重新解码，不找 Dart
    @Test
    public void tRes9_redecodeAfterEviction() {
        decoder.bytesPer = 5 * MIB;
        registry.register(FakeImages.bytes("A"));
        registry.register(FakeImages.bytes("B"));
        registry.acquire("A", ImageEntry.Ref.DESIRED);
        runner.drain();
        ImageEntry a = registry.entry("A");
        ImageEntry b = registry.entry("B");
        assertTrue("A 较旧且无任务需要，应被淘汰", a.isEvicted() ^ b.isEvicted());
        ImageEntry victim = a.isEvicted() ? a : b;
        double[] size = registry.logicalSize(victim.id);
        assertNotNull("淘汰后逻辑尺寸仍可用于布局", size);
        assertEquals(50.0, size[0], 0);
        int decodes = registry.decodeCount();
        events.log.clear();

        registry.acquire(victim.id, ImageEntry.Ref.QUEUED);
        assertEquals("任务引用触发重新解码", decodes + 1, registry.decodeCount());
        runner.drain();
        assertNotNull(victim.decoded());
        assertFalse(victim.decoded().isRecycled());
        assertEquals(Collections.singletonList("redecoded:" + victim.id), events.log);
        registry.unref(victim.id, ImageEntry.Ref.QUEUED);
        registry.unref("A", ImageEntry.Ref.DESIRED);
    }

    // epoch：重试解码进行中又被释放并重新登记，旧结果被丢弃
    @Test
    public void staleDecodeDiscardedByEpoch() {
        registry.register(FakeImages.asset("A"));
        registry.release("A");
        assertNull("无引用的 pending 资源立即释放", registry.entry("A"));
        registry.register(FakeImages.asset("A"));
        runner.drain();
        assertEquals(ImageEntry.State.READY, registry.entry("A").state());
        assertEquals("旧解码结果被回收", true, decoder.produced.get(0).isRecycled());
        assertFalse(decoder.produced.get(1).isRecycled());
        assertEquals(Collections.singletonList("ready:A"), events.log);
    }

    // R-INIT-3 快照与 resync 释放
    @Test
    public void snapshotAndResyncRelease() {
        decoder.failing.add("F");
        registry.register(FakeImages.bytes("R"));
        registry.register(FakeImages.bytes("F"));
        runner.drain();
        registry.register(FakeImages.bytes("P"));
        assertEquals(Collections.singletonList("P"), registry.pendingIds());
        java.util.Map<String, Object> snap = registry.snapshot();
        assertEquals(Collections.singletonList("R"), snap.get("ready"));
        assertEquals(Collections.singletonList("P"), snap.get("pending"));
        assertEquals(1, ((java.util.List<?>) snap.get("failed")).size());

        registry.releaseAllExcept(Collections.singleton("R"));
        runner.drain();
        assertEquals(1, registry.size());
        assertNotNull(registry.entry("R"));
    }

    // 第一阶段销毁：被执行中任务引用的保留，最后一次归还后释放
    @Test
    public void disposeKeepsRunningInputs() {
        FakeImages.Image a = readyImage("A");
        FakeImages.Image b = readyImage("B");
        registry.acquire("A", ImageEntry.Ref.RUNNING);
        registry.dispose();
        assertTrue(b.isRecycled());
        assertFalse(a.isRecycled());
        assertEquals(1, registry.size());
        registry.unref("A", ImageEntry.Ref.RUNNING);
        assertTrue(a.isRecycled());
        assertEquals(0, registry.size());
    }
}
