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
        /** 线程安全：realBg 模式下后台线程会向这里投递 */
        final java.util.concurrent.ConcurrentLinkedDeque<Runnable> mainQ =
                new java.util.concurrent.ConcurrentLinkedDeque<>();
        /** 非空时后台任务在真实线程上执行（T-DISP-3），主线程仍是测试线程 */
        java.util.concurrent.ExecutorService realBg = null;
        final List<Runnable> frames = new ArrayList<>();
        long now = 0;
        /** mainDelayed 投递的任务，测试用 fireDelayed 触发 */
        final List<Runnable> delayed = new ArrayList<>();
        int shutdownCalls = 0;

        void fireDelayed() {
            List<Runnable> rs = new ArrayList<>(delayed);
            delayed.clear();
            for (Runnable r : rs) {
                r.run();
            }
        }

        /** 为 true 时模拟执行器已关闭：background 拒绝任务 */
        boolean rejecting = false;

        @Override
        public boolean background(Runnable r) {
            if (rejecting) {
                return false;
            }
            if (realBg != null) {
                realBg.execute(r);
            } else {
                bg.add(r);
            }
            return true;
        }

        @Override public void main(Runnable r) { mainQ.add(r); }
        @Override public void mainDelayed(Runnable r, long ms) { delayed.add(r); }
        @Override public void cancelMainDelayed(Runnable r) { delayed.remove(r); }
        @Override public void shutdown() { shutdownCalls++; }
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
        volatile boolean recycled = false;
        /** pixel 模式下主体中心的像素颜色；0 表示未计算 */
        int centerColor;
        boolean drewText;

        Bitmap(String key) { this.key = key; }
    }

    /** 假 descriptor：持有 SDK 副本 */
    static final class Descriptor {
        final String key;
        final Bitmap copy;
        /** 模拟 descriptor.recycle()：实现不应调用（API>10 空操作，R-CACHE-3） */
        boolean descriptorRecycleCalled = false;
        int centerColor;
        boolean drewText;
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
        /** 为 true 时 toDescriptor 抛异常（模拟 fromBitmap 失败），合成位图未被回收 */
        boolean failToDescriptor = false;

        @Override
        public Object toDescriptor(Object bitmap) {
            Bitmap b = (Bitmap) bitmap;
            if (failToDescriptor) {
                b.recycled = true; // 与 AndroidIconFactory 一致：finally 中回收输入
                throw new IllegalStateException("fromBitmap 失败");
            }
            Descriptor d = new Descriptor(b.key);
            d.centerColor = b.centerColor; // SDK 副本与合成位图像素相同
            d.drewText = b.drewText;
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
        final List<String> painted = java.util.Collections.synchronizedList(new ArrayList<>());
        final Set<String> failing = new HashSet<>();
        /** 为 true 时 paint 抛 OutOfMemoryError（Error 不得让后台线程崩溃） */
        volatile boolean oom = false;
        /** 最近一次产出的合成位图（替身 painter 的输出，用于检查回收） */
        final List<Bitmap> outputs = java.util.Collections.synchronizedList(new ArrayList<>());
        /** 绘制时读到的资源已被回收的次数（R-DISP-1 应恒为 0） */
        volatile int readRecycled = 0;
        /** 读取资源之前调用，可阻塞或抛异常（T-DISP-3/4） */
        java.util.function.Consumer<PaintJob> hook = job -> { };
        /** 为 true 时与 S10 真实 painter 一致，只支持纯形状（D-6）；默认支持全部以覆盖资源路径 */
        boolean pureShapeOnly = false;
        /** 为 true 时用真实 ShapeRenderer 绘制到 CenterPixelSurface，记录主体中心像素 */
        boolean pixel = false;

        @Override
        public boolean supports(NativeMarkerSpec spec) {
            return !pureShapeOnly || spec.isPureShape();
        }

        @Override
        public Result paint(PaintJob job) throws Exception {
            hook.accept(job);
            if (oom) {
                throw new OutOfMemoryError("绘制 OOM");
            }
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
            Bitmap out = new Bitmap(job.key);
            if (pixel) {
                CenterPixelSurface s = CenterPixelSurface.paint(job); // 走真实的 ShapeRenderer
                out.centerColor = s.color;
                out.drewText = s.drewText;
            }
            outputs.add(out);
            return new Result(out, 0.5f, 1f);
        }

        int count() { return painted.size(); }
    }
}
