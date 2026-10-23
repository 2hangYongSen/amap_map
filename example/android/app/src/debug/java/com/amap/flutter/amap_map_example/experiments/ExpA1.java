package com.amap.flutter.amap_map_example.experiments;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.os.Debug;
import android.view.Choreographer;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * E-A1：BitmapDescriptor 共享、remove/destroy、回收时机、前后台与低内存、onDestroy 后回收。
 * policy=none|immediate|deferred，对应 R-CACHE-3 的既定行为、候选 1、候选 2。
 * “回收”指回收 SDK 持有的像素 descriptor.getBitmap()（fromBitmap 内部会复制一份，见结论）。
 */
class ExpA1 extends Experiment {
    private static final int[] PALETTE = {0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835,
            0xFF8E24AA, 0xFFFB8C00, 0xFF00ACC1, 0xFF6D4C41};
    private static final int N = 200, BATCH = 50;

    private final String policy;
    private final int SWITCHES;
    private final Random rnd = new Random(42);
    private final List<Marker> markers = new ArrayList<>();
    private final List<LatLng> pos = new ArrayList<>();
    private final int[] expect = new int[N];
    private final BitmapDescriptor[] shown = new BitmapDescriptor[N];
    private final ArrayDeque<Object[]> deferred = new ArrayDeque<>(); // {bitmap, frameNo, texUpdates}
    private int iconPx, switches, blankTotal, recycled, checks;
    private long recycleThrows;

    ExpA1(Intent i) {
        String p = i.getStringExtra("policy");
        policy = p == null ? "none" : p;
        SWITCHES = i.getIntExtra("switches", 1000);
    }

    @Override
    void start() {
        h.log("policy=" + policy);
        iconPx = Math.round(18 * h.density());
        sharedDescriptorTest();
    }

    // ---- 第 1 部分：100 个点共享一个 descriptor，remove()/destroy() 其中一个 ----
    private void sharedDescriptorTest() {
        Bitmap src = dot(PALETTE[0], iconPx);
        BitmapDescriptor d = BitmapDescriptorFactory.fromBitmap(src);
        // fromBitmap 是否复制：源位图与 descriptor 内位图是不是同一个对象
        result("fromBitmapCopies", String.valueOf(d.getBitmap() != src));
        src.recycle(); // 源位图立刻回收，验证 SDK 不再依赖它
        final List<Marker> group = new ArrayList<>();
        final List<LatLng> where = grid(20, 5);
        for (LatLng ll : where) group.add(add(ll, d));
        waitDraw(3, 2, 3000, () -> {
            int ok0 = countColor(where, PALETTE[0], group, -1);
            group.get(0).remove();
            waitDraw(3, 2, 3000, () -> {
                int okRemove = countColor(where, PALETTE[0], group, 0);
                group.get(1).destroy();
                waitDraw(3, 2, 3000, () -> {
                    int okDestroy = countColor(where, PALETTE[0], group, 1);
                    int total = where.size();
                    result("shared.before", ok0 + "/" + total);
                    result("shared.afterRemove1", okRemove + "/" + (total - 1));
                    result("shared.afterDestroy1", okDestroy + "/" + (total - 2) + " recycled="
                            + d.getBitmap().isRecycled());
                    // descriptor.recycle() 在 API>10 上是否真的回收像素
                    BitmapDescriptor probe = BitmapDescriptorFactory.fromBitmap(dot(PALETTE[1], iconPx));
                    probe.recycle();
                    result("descriptorRecycleIsNoop", String.valueOf(!probe.getBitmap().isRecycled()));
                    // 共享 descriptor 被 SDK 复用到新点：remove 过后仍可用于 addMarker
                    Marker again = add(where.get(0), d);
                    waitDraw(3, 2, 3000, () -> {
                        result("shared.reAddAfterDestroy",
                                String.valueOf(isColor(h.frame(), h.toScreen(where.get(0)), PALETTE[0])));
                        again.remove();
                        for (Marker m : group) m.remove();
                        if ("displayed".equals(policy)) {
                            displayedProbe();
                        } else {
                            raceTest(0); // none 策略下同样跑，作为对照
                        }
                    });
                });
            });
        });
    }

    /** where 中除 skipUpTo 及之前的点外，有多少个在截图里是目标色。 */
    private int countColor(List<LatLng> where, int color, List<Marker> group, int skipUpTo) {
        Bitmap f = h.frame();
        int ok = 0;
        for (int i = skipUpTo + 1; i < where.size(); i++) {
            if (isColor(f, h.toScreen(where.get(i)), color)) ok++;
        }
        // 已删除的点应当不再显示
        for (int i = 0; i <= skipUpTo; i++) {
            if (isColor(f, h.toScreen(where.get(i)), color)) h.log("WARN removed still visible " + i);
        }
        return ok;
    }

    /**
     * 探针（policy=displayed）：addMarker 返回后立刻回收该点“正在显示”的像素。
     * 若 SDK 在 GL 线程上延迟读取，或 GL 重建后从 Java 位图重新上传，就会出现空白或崩溃。
     * 只用于取证，不是候选策略。
     */
    private void displayedProbe() {
        List<LatLng> where = grid(4, 5);
        probeWhere = where;
        for (int i = 0; i < where.size(); i++) {
            BitmapDescriptor d = BitmapDescriptorFactory.fromBitmap(dot(PALETTE[(i + 2) % 8], iconPx));
            markers.add(add(where.get(i), d));
            doRecycle(d.getBitmap()); // 同一主线程任务内，GL 线程还没画过这一帧
        }
        waitDraw(3, 2, 3000, () -> h.after(1000, () -> {
            int ok = countColor2(where, 0, true);
            result("displayedProbe.afterAdd", ok + "/" + where.size() + " recycled=" + recycled
                    + " missing=" + missing(where));
            h.log("READY_FOR_LIFECYCLE");
        }));
    }

    private List<LatLng> probeWhere;

    // ---- 第 1.5 部分：同一帧内 add→remove→回收、setIcon→setIcon→回收（GL 线程尚未处理时回收）----
    private void raceTest(int round) {
        if (round >= 20) {
            result("race", "rounds=20 points=400 notYetAt2Frames=" + raceLate + " blankAfter1s=" + raceFinal
                    + " recycleThrows=" + recycleThrows);
            stressSetup();
            return;
        }
        List<LatLng> where = grid(4, 5);
        List<Marker> keep = new ArrayList<>();
        for (int i = 0; i < where.size(); i++) {
            // a) 新 descriptor 加上去立刻删，再按策略回收它的像素
            BitmapDescriptor d = BitmapDescriptorFactory.fromBitmap(dot(PALETTE[i % 8], iconPx));
            Marker m = add(where.get(i), d);
            m.remove();
            evict(d);
            // b) 同一帧内连续 setIcon 两次，中间那张按策略回收
            BitmapDescriptor a = BitmapDescriptorFactory.fromBitmap(dot(PALETTE[(i + 1) % 8], iconPx));
            BitmapDescriptor b = BitmapDescriptorFactory.fromBitmap(dot(PALETTE[(i + 2) % 8], iconPx));
            Marker k = add(where.get(i), a);
            k.setIcon(b);
            evict(a);
            keep.add(k);
        }
        waitDraw(2, 1, 2000, () -> {
            int ok = countColor2(where, round, false);
            // 1 秒后复查：区分“还没画到”（暂时）和“纹理丢失”（永久空白）
            h.after(1000, () -> waitDraw(3, 2, 2000, () -> {
                int ok2 = countColor2(where, round, true);
                if (ok != where.size() || ok2 != where.size()) {
                    h.log("WARN race round=" + round + " ok@2frames=" + ok + " ok@1s=" + ok2
                            + " missing=" + missing(where));
                }
                for (Marker k : keep) k.remove();
                waitDraw(1, 1, 1000, () -> raceTest(round + 1));
            }));
        });
    }

    private int raceLate, raceFinal;

    /** race 中保留下来的点应显示第二次 setIcon 的颜色。final=true 时计入永久空白。 */
    private int countColor2(List<LatLng> where, int round, boolean fin) {
        Bitmap f = h.frame();
        int ok = 0;
        for (int i = 0; i < where.size(); i++) {
            if (isColor(f, h.toScreen(where.get(i)), PALETTE[(i + 2) % 8])) ok++;
        }
        if (fin) raceFinal += where.size() - ok;
        else raceLate += where.size() - ok;
        return ok;
    }

    /** 未显示期望颜色的点：下标与实际像素。 */
    private String missing(List<LatLng> where) {
        Bitmap f = h.frame();
        StringBuilder s = new StringBuilder();
        for (int i = 0; i < where.size(); i++) {
            Point p = h.toScreen(where.get(i));
            if (!isColor(f, p, PALETTE[(i + 2) % 8])) {
                s.append(i).append('=').append(hex(f.getPixel(p.x, p.y))).append(' ');
            }
        }
        return s.toString();
    }

    // ---- 第 2 部分：T-CACHE-6 压力 ----
    private void stressSetup() {
        pos.addAll(grid(N / 10, 10));
        for (int i = 0; i < N; i++) {
            expect[i] = PALETTE[i % PALETTE.length];
            shown[i] = BitmapDescriptorFactory.fromBitmap(dot(expect[i], iconPx));
            markers.add(add(pos.get(i), shown[i]));
        }
        waitDraw(3, 2, 3000, () -> {
            verify("initial");
            tickDeferred();
            nextBatch();
        });
    }

    private void nextBatch() {
        if (switches >= SWITCHES) {
            result("stress.switches", switches + " permanentBlank=" + stressPermanent
                    + " blankSamples(incl. transient)=" + blankTotal + " checks=" + checks
                    + " recycled=" + recycled + " recycleThrows=" + recycleThrows);
            memory("afterStress");
            h.log("READY_FOR_LIFECYCLE"); // 主机脚本据此开始前后台切换与低内存
            return;
        }
        for (int k = 0; k < BATCH; k++, switches++) {
            int i = rnd.nextInt(N);
            int color = PALETTE[rnd.nextInt(PALETTE.length)];
            Bitmap src = dot(color, iconPx);
            BitmapDescriptor next = BitmapDescriptorFactory.fromBitmap(src);
            src.recycle(); // 插件自己的合成位图：fromBitmap 已复制，所有策略下都立即回收
            BitmapDescriptor old = shown[i];
            if (switches % 10 == 9) {
                // 每 10 次做一次 remove + 重新 add，覆盖 remove 后回收的路径
                markers.get(i).remove();
                markers.set(i, add(pos.get(i), next));
            } else {
                markers.get(i).setIcon(next);
            }
            shown[i] = next;
            expect[i] = color;
            evict(old);
        }
        waitDraw(2, 1, 2000, () -> {
            int bad = verify("batch" + switches);
            if (bad > 0) {
                // 复查一次：1 秒后仍不对才算永久空白
                h.after(1000, () -> waitDraw(3, 2, 2000, () -> {
                    stressPermanent += verify("recheck" + switches);
                    nextBatch();
                }));
            } else {
                nextBatch();
            }
        });
    }

    /** 被淘汰的旧 descriptor 按策略处理。 */
    private void evict(BitmapDescriptor old) {
        Bitmap px = old.getBitmap();
        switch (policy) {
            case "immediate":
                doRecycle(px);
                break;
            case "deferred":
                deferred.add(new Object[]{px, h.frameNo, h.texUpdates});
                break;
            default:
                break; // none：只解除引用
        }
    }

    /** 候选 2：两次 vsync + 至少一次 GL 新帧之后再回收。 */
    private void tickDeferred() {
        Choreographer.getInstance().postFrameCallback(t -> {
            while (!deferred.isEmpty()) {
                Object[] e = deferred.peek();
                if (h.frameNo - (long) e[1] >= 2 && h.texUpdates - (long) e[2] >= 1) {
                    deferred.poll();
                    doRecycle((Bitmap) e[0]);
                } else {
                    break;
                }
            }
            tickDeferred();
        });
    }

    private void doRecycle(Bitmap b) {
        try {
            if (b != null && !b.isRecycled()) {
                b.recycle();
                recycled++;
            }
        } catch (Throwable e) {
            recycleThrows++;
        }
    }

    private int stressPermanent;

    /** 截图核对每个点的颜色，不一致记为空白/错误图标；返回不一致数。 */
    private int verify(String tag) {
        Bitmap f = h.frame();
        int bad = 0;
        StringBuilder sample = new StringBuilder();
        for (int i = 0; i < N; i++) {
            Point p = h.toScreen(pos.get(i));
            if (!isColor(f, p, expect[i])) {
                bad++;
                if (sample.length() < 120) sample.append(i).append(':').append(hex(f.getPixel(
                        Math.max(0, Math.min(f.getWidth() - 1, p.x)),
                        Math.max(0, Math.min(f.getHeight() - 1, p.y))))).append(' ');
            }
        }
        checks++;
        blankTotal += bad;
        h.log("VERIFY " + tag + " bad=" + bad + (lastWaitTimedOut ? " (waitTimeout)" : "") + " " + sample);
        return bad;
    }

    @Override
    void onResumed() {
        if (probeWhere != null) {
            waitDraw(10, 5, 4000, () -> result("displayedProbe.resume",
                    countColor2(probeWhere, 0, true) + "/" + probeWhere.size()));
            return;
        }
        if (markers.isEmpty()) return;
        // 回到前台：多等几帧让 GL 重建纹理，再核对
        waitDraw(10, 5, 4000, () -> verify("resume"));
    }

    @Override
    void onTrim() {
        if (markers.isEmpty() || probeWhere != null) return;
        h.after(300, () -> waitDraw(5, 2, 3000, () -> verify("trim")));
    }

    @Override
    void beforeMapDestroy() {
        memory("beforeDestroy");
    }

    /** onDestroy 之后回收所有仍在显示的像素（R-DISP-2），观察是否报错或崩溃。 */
    @Override
    void afterMapDestroy() {
        if (probeWhere != null) return;
        int n = 0;
        for (BitmapDescriptor d : shown) {
            if (d != null) {
                doRecycle(d.getBitmap());
                n++;
            }
        }
        h.log("RESULT postDestroyRecycle count=" + n + " throws=" + recycleThrows);
    }

    private void memory(String tag) {
        Runtime.getRuntime().gc();
        System.runFinalization();
        Runtime.getRuntime().gc();
        result("mem." + tag, "nativeHeapKB=" + Debug.getNativeHeapAllocatedSize() / 1024
                + " javaUsedKB=" + (Runtime.getRuntime().totalMemory()
                - Runtime.getRuntime().freeMemory()) / 1024);
    }

    private Marker add(LatLng ll, BitmapDescriptor d) {
        return h.amap.addMarker(new MarkerOptions().position(ll).icon(d).anchor(0.5f, 0.5f)
                .infoWindowEnable(false));
    }

    /** 在地图可见区域内均匀铺 cols×rows 个位置。 */
    List<LatLng> grid(int rows, int cols) {
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        List<LatLng> r = new ArrayList<>();
        int top = Math.round(ht * 0.12f);
        for (int y = 0; y < rows; y++) {
            for (int x = 0; x < cols; x++) {
                int px = Math.round((x + 0.5f) * w / cols);
                int py = top + Math.round((y + 0.5f) * (ht - top) / rows);
                r.add(h.fromScreen(px, py));
            }
        }
        return r;
    }
}
