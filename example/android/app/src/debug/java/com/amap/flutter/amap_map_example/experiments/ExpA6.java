package com.amap.flutter.amap_map_example.experiments;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Point;
import android.graphics.RectF;
import android.view.Choreographer;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * E-A6：集合替换时 immediate 与 replaceWhenReady 的视觉差异，以及 timeout 建议值。
 * 两层各 N 个价格气泡（每次文案不同，保证无缓存命中），在后台线程绘制、主线程每帧 4ms 预算应用，
 * 与 §8.4 的流程一致。每 100ms 截一帧，统计屏幕上可见的旧层、新层点数；
 * 记录“新层全部应用完成”的耗时，用其分布给出 timeout 建议值。
 */
class ExpA6 extends Experiment {
    private static final int OLD = 0xFFE53935, NEW = 0xFF1E88E5;
    private static final long BUDGET_NS = 4_000_000L;
    private final int n;
    private final int rounds;
    private final boolean sample;
    private final ExecutorService painter = Executors.newFixedThreadPool(2);
    private final List<Marker> layer = new ArrayList<>();
    private List<LatLng> posA, posB;
    private int round;
    private final List<Double> readyMsImmediate = new ArrayList<>(), readyMsReplace = new ArrayList<>(),
            blankMsImmediate = new ArrayList<>(), blankMsReplace = new ArrayList<>(),
            paintMs = new ArrayList<>(), minImmediate = new ArrayList<>(), minReplace = new ArrayList<>();

    ExpA6(Intent i) {
        n = i.getIntExtra("n", 200);
        rounds = i.getIntExtra("rounds", 10);
        sample = i.getBooleanExtra("sample", true);
    }

    @Override
    void start() {
        posA = grid(0);
        posB = grid(1); // 与 A 错开半格，模拟价格层与片区层位置不同
        // 初始旧层
        List<Bitmap> init = new ArrayList<>();
        for (int i = 0; i < n; i++) init.add(bubble(OLD, "¥" + (3000 + i)));
        for (int i = 0; i < n; i++) layer.add(add(posA.get(i), BitmapDescriptorFactory.fromBitmap(init.get(i))));
        waitDraw(5, 2, 3000, this::nextRound);
    }

    private void nextRound() {
        if (round >= rounds * 2) {
            report();
            return;
        }
        boolean replace = round % 2 == 1; // 交替两种模式
        boolean toB = round % 2 == 0;
        round++;
        runReplace(replace, toB ? posB : posA, round);
    }

    private void runReplace(boolean replaceWhenReady, List<LatLng> target, int seed) {
        final List<Marker> old = new ArrayList<>(layer);
        layer.clear();
        final long t0 = System.nanoTime();
        final ArrayDeque<Object[]> applyQueue = new ArrayDeque<>();
        final int[] painted = {0}, applied = {0};
        final boolean[] oldRemoved = {false};
        final List<Marker> fresh = new ArrayList<>();
        if (!replaceWhenReady) {
            for (Marker m : old) m.remove();
            oldRemoved[0] = true;
        }
        // 后台绘制
        final int color = colorFor(target);
        for (int i = 0; i < n; i++) {
            final int idx = i;
            painter.execute(() -> {
                long p0 = System.nanoTime();
                Bitmap b = bubble(color, "¥" + (seed * 1000 + idx));
                double pm = (System.nanoTime() - p0) / 1e6;
                h.main.post(() -> {
                    paintMs.add(pm);
                    painted[0]++;
                    applyQueue.add(new Object[]{idx, b});
                });
            });
        }
        // 帧应用器 + 每 100ms 采样
        final List<String> samples = new ArrayList<>();
        final long[] lastSample = {0};
        final double[] blankMs = {0};
        final long[] lastSampleNs = {t0};
        final int[] minShown = {Integer.MAX_VALUE};
        Choreographer.getInstance().postFrameCallback(new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long ft) {
                long f0 = System.nanoTime();
                while (!applyQueue.isEmpty() && System.nanoTime() - f0 < BUDGET_NS) {
                    Object[] it = applyQueue.poll();
                    int idx = (int) it[0];
                    fresh.add(add(target.get(idx), BitmapDescriptorFactory.fromBitmap((Bitmap) it[1])));
                    applied[0]++;
                }
                boolean all = applied[0] == n;
                if (all && !oldRemoved[0]) {
                    for (Marker m : old) m.remove(); // 新层全部应用后同一帧删除旧层
                    oldRemoved[0] = true;
                }
                long now = System.nanoTime();
                // 逐帧采样（1/4 分辨率）：任一层可见的“位置”数 = 屏幕上有内容的点位数
                // sample=false 时只计时，不截图（截图本身约占 50ms/帧，会放大就绪耗时）
                int[] vis = sample ? visible(target) : new int[]{0, n};
                int shown = Math.max(vis[0], 0) + vis[1];
                minShown[0] = Math.min(minShown[0], shown);
                // “缺点”：可见点位少于 90%（屏幕上明显变空）的累计时长
                if (shown < n * 9 / 10) blankMs[0] += (now - lastSampleNs[0]) / 1e6;
                lastSampleNs[0] = now;
                lastSample[0]++;
                if (lastSample[0] % 3 == 1 || all) {
                    samples.add((now - t0) / 1_000_000 + "ms o=" + vis[0] + " n=" + vis[1]);
                }
                if (sample && lastSample[0] == 2) {
                    h.savePng(h.frame(), "A6_" + (replaceWhenReady ? "replace" : "immediate") + "_r" + seed + "_f2.png");
                }
                if (all) {
                    double ready = (now - t0) / 1e6;
                    (replaceWhenReady ? readyMsReplace : readyMsImmediate).add(ready);
                    (replaceWhenReady ? blankMsReplace : blankMsImmediate).add(blankMs[0]);
                    h.log("ROUND " + seed + " mode=" + (replaceWhenReady ? "replaceWhenReady" : "immediate")
                            + " readyMs=" + String.format("%.1f", ready) + " blankMs=" + String.format("%.0f", blankMs[0])
                            + " minShown=" + minShown[0] + "/" + n + " frames=" + lastSample[0]
                            + " samples=" + samples);
                    (replaceWhenReady ? minReplace : minImmediate).add((double) minShown[0]);
                    layer.addAll(fresh);
                    waitDraw(5, 2, 2000, () -> h.after(500, ExpA6.this::nextRound));
                } else {
                    Choreographer.getInstance().postFrameCallback(this);
                }
            }
        });
    }

    private static final int SCALE = 2;

    /** 新层颜色：去 B 位置用 NEW，回 A 位置用 OLD，这样两层颜色总是不同。 */
    private int colorFor(List<LatLng> target) {
        return target == posB ? NEW : OLD;
    }

    /** [旧层可见点, 新层可见点]：在旧层位置取旧层色、在新层位置取新层色（气泡中心在锚点上方 18dp）。 */
    private int[] visible(List<LatLng> target) {
        Bitmap f = h.frame(SCALE);
        List<LatLng> other = target == posA ? posB : posA;
        int newColor = colorFor(target), oldColor = colorFor(other);
        int o = 0, nw = 0;
        // 取色点：气泡主体左上区域（无文字），相对锚点 (-4dp, -12dp)，坐标按 SCALE 缩小
        int left = Math.round(4 * h.density()), up = Math.round(12 * h.density());
        for (int i = 0; i < n; i++) {
            Point p = h.toScreen(other.get(i));
            p.offset(-left, -up);
            p.set(p.x / SCALE, p.y / SCALE);
            if (isColor(f, p, oldColor)) o++;
            Point q = h.toScreen(target.get(i));
            q.offset(-left, -up);
            q.set(q.x / SCALE, q.y / SCALE);
            if (isColor(f, q, newColor)) nw++;
        }
        return new int[]{o, nw};
    }

    private void report() {
        result("paintMs(per bubble, bg)", fmt(stats(paintMs)));
        result("immediate.readyMs", fmt(stats(readyMsImmediate)));
        result("immediate.blankMs", fmt(stats(blankMsImmediate)));
        result("replaceWhenReady.readyMs", fmt(stats(readyMsReplace)));
        result("replaceWhenReady.blankMs", fmt(stats(blankMsReplace)));
        result("immediate.minShown", fmt(stats(minImmediate)));
        result("replaceWhenReady.minShown", fmt(stats(minReplace)));
        painter.shutdown();
        done();
    }

    /**
     * 与 §9.3 相同结构的价格气泡：圆角矩形+箭头连续路径、阴影、文字。
     * 为了 200 点铺满一屏且两层互不遮挡，尺寸缩到画布 20×20dp、主体 16×12dp、箭头 4dp。
     */
    private Bitmap bubble(int color, String text) {
        float d = h.density();
        Bitmap b = Bitmap.createBitmap(Math.round(20 * d), Math.round(20 * d), Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(b);
        RectF r = new RectF(2 * d, 2 * d, 18 * d, 14 * d);
        Path path = new Path();
        path.addRoundRect(r, 3 * d, 3 * d, Path.Direction.CW);
        Path arrow = new Path();
        arrow.moveTo(r.centerX() - 3 * d, r.bottom - 0.5f);
        arrow.lineTo(r.centerX(), r.bottom + 4 * d);
        arrow.lineTo(r.centerX() + 3 * d, r.bottom - 0.5f);
        arrow.close();
        path.op(arrow, Path.Op.UNION);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(color);
        p.setShadowLayer(2 * d, 0, 1 * d, 0x55000000);
        c.drawPath(path, p);
        Paint t = new Paint(Paint.ANTI_ALIAS_FLAG);
        t.setColor(0xFFFFFFFF);
        t.setTextSize(5 * d);
        t.setTextAlign(Paint.Align.CENTER);
        c.drawText(text, r.centerX() + 2 * d, r.bottom - 1 * d, t); // 文字偏右下，左上角留给取色
        return b;
    }

    private Marker add(LatLng ll, BitmapDescriptor d) {
        // 锚点在箭头尖端：(10/20, 18/20)
        return h.amap.addMarker(new MarkerOptions().position(ll).icon(d)
                .anchor(0.5f, 18f / 20f).infoWindowEnable(false));
    }

    private List<LatLng> grid(int shift) {
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        int cols = 10, rows = (n + cols - 1) / cols;
        List<LatLng> r = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            float x = (i % cols + 0.25f + shift * 0.5f) * w / cols;
            float y = ht * 0.12f + (i / cols + 0.6f + shift * 0.3f) * ht * 0.85f / rows;
            r.add(h.fromScreen(Math.round(x), Math.round(y)));
        }
        return r;
    }
}
