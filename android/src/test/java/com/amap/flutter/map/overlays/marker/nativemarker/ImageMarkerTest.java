package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** S11：图片背景的等待、降级、恢复与九宫格异步校验（T-RES-6/10/11、T-NAT-REJ-2、D-5） */
public class ImageMarkerTest {
    private RenderHarness h;

    @Before
    public void setUp() {
        h = new RenderHarness();
        h.painter.pixel = true; // 走真实 ShapeRenderer，记录主体中心像素
        h.manager.attach();
    }

    @After
    public void tearDown() {
        RenderInvariants.check(h);
        h.manager.dispose();
        h.loop.drain();
        RenderInvariants.checkTerminated(h);
    }

    private FakeRender.Descriptor shownIcon(String id) {
        return (FakeRender.Descriptor) h.iconOf(id);
    }

    private int errors(String code) {
        int n = 0;
        for (int i = 0; i < h.emitted.size(); i++) {
            if ("marker#nativeError".equals(h.emitted.get(i))
                    && code.equals(h.emittedArgs.get(i).get("code"))) {
                n++;
            }
        }
        return n;
    }

    // T-RES-6：pending 时不 addMarker，ready 后才添加；failed 时按降级背景添加且保留文字
    @Test
    public void tRes6_pendingWaitsAndFailedFallsBack() {
        h.decoder.failing.add("bad");
        h.images(Payloads.bytesImage("ok"), Payloads.bytesImage("bad"));
        h.add(Payloads.withImage("mOk", "好", "ok"), Payloads.withImage("mBad", "坏", "bad"));
        h.loop.runMain(); // 任务已登记，资源仍在解码
        assertFalse("pending 资源不得 addMarker", h.host.hasMarker("mOk"));
        assertFalse(h.host.hasMarker("mBad"));
        assertEquals(0, h.painter.count());
        h.loop.drain();
        assertEquals(FakeImages.IMAGE_COLOR, shownIcon("mOk").centerColor);
        assertEquals("降级为默认白色背景", ShapeRenderer.FALLBACK_FILL, shownIcon("mBad").centerColor);
        assertTrue("降级时保留文字", shownIcon("mBad").drewText);
        assertEquals(1, errors(ImageRegistry.ERR_DECODE_FAILED));
    }

    // T-RES-10：20 个点引用 asset A（10 个共享 key），A 先失败后恢复；全部换成 A 的正常位图
    @Test
    public void tRes10_recoveryRepaintsEveryPoint() {
        h.decoder.failing.add("A");
        h.images(Payloads.assetImage("A"));
        @SuppressWarnings("unchecked")
        Map<String, Object>[] ms = new Map[20];
        for (int i = 0; i < 20; i++) {
            ms[i] = Payloads.withImage("m" + i, i < 10 ? "同" : "异" + i, "A");
        }
        h.add(ms);
        h.loop.drain();
        Set<String> fallbackKeys = new HashSet<>();
        for (int i = 0; i < 20; i++) {
            assertEquals(ShapeRenderer.FALLBACK_FILL, shownIcon("m" + i).centerColor);
            fallbackKeys.add(h.point("m" + i).shown().key);
        }
        assertEquals("10 个共享 + 10 个独立", 11, fallbackKeys.size());
        assertEquals(11, h.painter.count());

        h.decoder.failing.clear();
        h.images(Payloads.assetImage("A")); // R-RES-8 asset 重试
        h.loop.drain();
        Fixtures.FakeResolver ready = new Fixtures.FakeResolver();
        Set<String> readyKeys = new HashSet<>();
        for (int i = 0; i < 20; i++) {
            PointTable.Entry p = h.point("m" + i);
            assertEquals("shown.key 是 A:ready 版本",
                    RenderKey.normalKey(p.desired().spec, 2880, ready), p.shown().key);
            assertEquals("中心像素来自 A", FakeImages.IMAGE_COLOR, shownIcon("m" + i).centerColor);
            readyKeys.add(p.shown().key);
        }
        assertEquals("恢复后绘制次数 = 不同 key 数", 11 + readyKeys.size(), h.painter.count());
        for (String k : fallbackKeys) {
            RenderCache.Entry c = h.r().cache.get(k);
            assertTrue("降级条目 displayRefs = 0", c == null || c.displayRefs() == 0);
        }
    }

    // T-RES-11：降级任务 running 时 A 恢复 ready；迟到的降级结果不被应用，最终显示 A
    @Test
    public void tRes11_lateFallbackResultIsDropped() {
        h.decoder.failing.add("A");
        h.images(Payloads.assetImage("A"));
        h.add(Payloads.withImage("m", "t", "A"));
        h.loop.runMain();
        h.loop.runBg(); // 解码失败
        h.loop.runMain(); // onFailed → 降级 key → 降级任务开始（已提交后台）
        assertEquals(1, h.loop.bg.size());
        Runnable fallbackPaint = h.loop.bg.poll();

        h.decoder.failing.clear();
        h.images(Payloads.assetImage("A"));
        h.loop.runBg(); // 重试解码成功
        h.loop.runMain(); // onReady → 重新计算 key，代次 +1，正常 key 等待
        fallbackPaint.run(); // 降级绘制此时才完成
        h.loop.drain();

        assertEquals(FakeImages.IMAGE_COLOR, shownIcon("m").centerColor);
        assertEquals("只 add 一次，没有先显示降级图", 1, h.host.count("add:"));
        assertEquals(0, h.host.count("setIcon:"));
        assertEquals(2, h.painter.count());
    }

    // T-NAT-REJ-2：九宫格超限 → 默认背景、错误只报一次；只改位置成功；改合法 capInsets 后显示图片
    @Test
    public void tNatRej2_capOverflowFallsBackOnce() {
        // 假图 100x50 像素、pixelRatio 2 → 逻辑 50x25；左右 30+30 超限
        h.images(Payloads.bytesImage("A"));
        h.add(Payloads.ninePatch("m", "九宫格", "A", 30, 4, 30, 4));
        h.loop.drain();
        assertTrue("期望快照保留，点位按降级显示", h.host.hasMarker("m"));
        assertEquals(ShapeRenderer.FALLBACK_FILL, shownIcon("m").centerColor);
        assertEquals(1, errors(NativeMarkerManager.ERR_INVALID_CONFIG));

        Map<String, Object> moved = Payloads.ninePatch("m", "九宫格", "A", 30, 4, 30, 4);
        moved.put("position", Arrays.asList(40.5, 116.4));
        h.change(moved);
        h.loop.drain();
        assertEquals(40.5, h.lat("m"), 0);
        assertEquals("只改位置不重复报错", 1, errors(NativeMarkerManager.ERR_INVALID_CONFIG));

        h.change(Payloads.ninePatch("m", "九宫格", "A", 10, 4, 10, 4));
        h.loop.drain();
        assertEquals(FakeImages.IMAGE_COLOR, shownIcon("m").centerColor);
        assertEquals(1, errors(NativeMarkerManager.ERR_INVALID_CONFIG));
    }

    // D-5：背景与图标都失败且没有文字时不显示；保留期望快照，资源恢复后按新增处理
    @Test
    @SuppressWarnings("unchecked")
    public void d5_hiddenWhenNothingToShowThenRestored() {
        h.decoder.failing.add("B");
        h.decoder.failing.add("I");
        h.images(Payloads.assetImage("B"), Payloads.assetImage("I"));
        Map<String, Object> m = Payloads.withImage("m", null, "B");
        Map<String, Object> content = (Map<String, Object>) ((Map<String, Object>)
                m.get("nativePresentation")).get("content");
        content.remove("text");
        content.put("iconId", "I");
        content.put("iconSize", Arrays.asList(16.0, 16.0));
        h.add(m);
        h.loop.drain();
        assertFalse("不显示该点", h.host.hasMarker("m"));
        assertTrue("期望快照仍在", h.point("m") != null);

        h.decoder.failing.clear();
        h.images(Payloads.assetImage("B"), Payloads.assetImage("I"));
        h.loop.drain();
        assertTrue("恢复后 addMarker", h.host.hasMarker("m"));
        assertEquals(FakeImages.IMAGE_COLOR, shownIcon("m").centerColor);
        assertNotEquals(ShapeRenderer.FALLBACK_FILL, shownIcon("m").centerColor);
    }
}
