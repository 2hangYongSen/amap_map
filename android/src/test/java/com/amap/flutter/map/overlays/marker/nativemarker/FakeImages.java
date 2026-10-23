package com.amap.flutter.map.overlays.marker.nativemarker;

import static org.junit.Assert.assertEquals;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** 资源注册表的测试替身：假位图、可控解码器、手动执行器 */
final class FakeImages {
    private FakeImages() {
    }

    static final class Image implements DecodedImage {
        final String id;
        final int w;
        final int h;
        final long bytes;
        boolean recycled = false;

        Image(String id, int w, int h, long bytes) {
            this.id = id;
            this.w = w;
            this.h = h;
            this.bytes = bytes;
        }

        @Override public int width() { return w; }
        @Override public int height() { return h; }
        @Override public long byteCount() { return bytes; }
        @Override public void recycle() { recycled = true; }
        @Override public boolean isRecycled() { return recycled; }
    }

    /** 每张图 w×h，占用 bytesPer；failing 中的 id 解码失败 */
    static final class Decoder implements ImageDecoder {
        final Set<String> failing = new HashSet<>();
        final List<Image> produced = new ArrayList<>();
        int w = 100;
        int h = 50;
        long bytesPer = 20_000;

        @Override
        public DecodedImage decode(ImageSource s) throws Exception {
            if (failing.contains(s.id)) {
                throw new IllegalStateException("asset 暂不可读: " + s.id);
            }
            Image img = new Image(s.id, w, h, bytesPer);
            produced.add(img);
            return img;
        }
    }

    /** 后台与主线程任务都排队，由测试显式推进 */
    static final class ManualRunner implements TaskRunner {
        final ArrayDeque<Runnable> bg = new ArrayDeque<>();
        final ArrayDeque<Runnable> mainQ = new ArrayDeque<>();

        @Override public void background(Runnable r) { bg.add(r); }
        @Override public void main(Runnable r) { mainQ.add(r); }

        /** 执行全部后台任务并把结果投递到主线程处理完 */
        void drain() {
            while (!bg.isEmpty() || !mainQ.isEmpty()) {
                while (!bg.isEmpty()) {
                    bg.poll().run();
                }
                while (!mainQ.isEmpty()) {
                    mainQ.poll().run();
                }
            }
        }
    }

    /** 记录监听回调，格式 "ready:A" / "failed:A" / "redecoded:A" */
    static final class Events implements ImageRegistry.Listener {
        final List<String> log = new ArrayList<>();

        @Override public void onReady(ImageEntry e) { log.add("ready:" + e.id); }
        @Override public void onFailed(ImageEntry e) { log.add("failed:" + e.id); }
        @Override public void onRedecoded(ImageEntry e) { log.add("redecoded:" + e.id); }
    }

    static ImageSource bytes(String id) {
        return new ImageSource(id, ImageSource.TYPE_BYTES, new byte[]{1, 2, 3}, null, null, 2.0);
    }

    static ImageSource asset(String id) {
        return new ImageSource(id, ImageSource.TYPE_ASSET, null, "assets/" + id + ".png", null, 2.0);
    }

    /** 不变量（§15）：所有条目三类引用都已归零 */
    static void assertAllRefsZero(ImageRegistry r) {
        for (ImageEntry e : r.entries()) {
            assertEquals("资源 " + e.id + " 引用未归零", 0, e.totalRefs());
        }
    }
}
