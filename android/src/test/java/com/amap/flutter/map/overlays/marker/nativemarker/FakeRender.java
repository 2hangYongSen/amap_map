package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** 调度器测试替身：可控事件循环（后台 / 主线程 / 帧）、假 Painter、假 descriptor */
final class FakeRender {
    private FakeRender() {
    }

    /** 后台、主线程、帧回调三个队列，由测试逐步推进 */
    static final class Loop implements TaskRunner, FrameClock {
        final ArrayDeque<Runnable> bg = new ArrayDeque<>();
        final ArrayDeque<Runnable> mainQ = new ArrayDeque<>();
        final List<Runnable> frames = new ArrayList<>();
        long now = 0;

        @Override public void background(Runnable r) { bg.add(r); }
        @Override public void main(Runnable r) { mainQ.add(r); }
        @Override public void postFrame(Runnable r) { frames.add(r); }
        @Override public void removeFrame(Runnable r) { frames.remove(r); }
        @Override public long nanoTime() { return now; }

        /** 只处理主线程队列（任务被挑选后进入 running，但后台尚未执行） */
        void runMain() {
            while (!mainQ.isEmpty()) {
                mainQ.poll().run();
            }
        }

        /** 执行当前已排队的后台任务（不含其间新投递的） */
        void runBg() {
            for (int n = bg.size(); n > 0; n--) {
                bg.poll().run();
            }
        }

        /** 触发一帧 */
        void frame() {
            List<Runnable> fs = new ArrayList<>(frames);
            frames.clear();
            for (Runnable r : fs) {
                r.run();
            }
        }

        /** 推进到全部队列为空 */
        void drain() {
            while (!bg.isEmpty() || !mainQ.isEmpty() || !frames.isEmpty()) {
                runMain();
                runBg();
                runMain();
                frame();
            }
        }

        /** 只推进后台与主线程，不触发帧（结果停在应用队列） */
        void drainNoFrame() {
            while (!bg.isEmpty() || !mainQ.isEmpty()) {
                runMain();
                runBg();
            }
        }
    }

    /** 假合成位图：记录 key，判断是否被回收 */
    static final class Bitmap {
        final String key;
        boolean recycled = false;

        Bitmap(String key) { this.key = key; }
    }

    /** 假 descriptor：持有 SDK 副本 */
    static final class Descriptor {
        final String key;
        final Bitmap copy;
        /** 模拟 descriptor.recycle()：实现不应调用（API>10 空操作，R-CACHE-3） */
        boolean descriptorRecycleCalled = false;
        int copyRecycles = 0;

        Descriptor(String key) {
            this.key = key;
            this.copy = new Bitmap(key + "#copy");
        }

        @Override public String toString() { return "desc:" + key; }
    }

    /** fromBitmap 后立即回收合成位图；每个 descriptor 计 bytesPer 字节 */
    static final class Icons implements IconFactory {
        final List<Descriptor> made = new ArrayList<>();
        final List<Bitmap> discarded = new ArrayList<>();
        long bytesPer = 10_000;

        @Override
        public Object toDescriptor(Object bitmap) {
            Bitmap b = (Bitmap) bitmap;
            Descriptor d = new Descriptor(b.key);
            b.recycled = true; // R-CACHE-3：合成位图转换后立即回收
            made.add(d);
            return d;
        }

        @Override public long byteCount(Object descriptor) { return bytesPer; }

        @Override
        public void recycleCopy(Object descriptor) {
            Descriptor d = (Descriptor) descriptor;
            d.copy.recycled = true;
            d.copyRecycles++;
        }

        @Override
        public void discard(Object bitmap) {
            ((Bitmap) bitmap).recycled = true;
            discarded.add((Bitmap) bitmap);
        }
    }

    /** Painter 替身：记录绘制的 key；failing 中的 key 抛异常；可检查读到的资源未被回收 */
    static final class Painter implements MarkerPainter {
        final List<String> painted = new ArrayList<>();
        final Set<String> failing = new HashSet<>();
        /** 绘制时读到的资源已被回收的次数（R-DISP-1 应恒为 0） */
        int readRecycled = 0;

        @Override
        public Result paint(PaintJob job) throws Exception {
            for (String id : job.spec.imageIds()) {
                DecodedImage img = job.image(id);
                if (img != null && img.isRecycled()) {
                    readRecycled++;
                }
            }
            if (failing.contains(job.key)) {
                throw new IllegalStateException("绘制失败");
            }
            painted.add(job.key);
            return new Result(new Bitmap(job.key), 0.5f, 1f);
        }

        int count() { return painted.size(); }
    }
}
