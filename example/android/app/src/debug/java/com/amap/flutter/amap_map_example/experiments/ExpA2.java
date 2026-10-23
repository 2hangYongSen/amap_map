package com.amap.flutter.amap_map_example.experiments;

import android.graphics.Bitmap;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

import java.util.ArrayList;
import java.util.List;

/**
 * E-A2：主线程上 addMarker / setIcon / setPosition / fromBitmap / remove 单次耗时，
 * 以及 addMarkers(list, false) 与逐个 addMarker 的对比。共 3 轮，每轮 200 点，取全部样本统计。
 * 图标尺寸取价格气泡的典型大小 72×40dp。
 */
class ExpA2 extends Experiment {
    private static final int N = 200, ROUNDS = 3;
    private final List<Double> tAdd = new ArrayList<>(), tSetIcon = new ArrayList<>(),
            tSetPos = new ArrayList<>(), tFromBitmap = new ArrayList<>(), tRemove = new ArrayList<>(),
            tBatchPerMarker = new ArrayList<>(), tBatchTotal = new ArrayList<>(),
            tLoopTotal = new ArrayList<>();
    private int round;

    @Override
    void start() {
        // 预热：类加载、JIT、首个纹理
        Marker w = h.amap.addMarker(opts(h.fromScreen(10, 10), icon(0xFF000000)));
        w.setIcon(icon(0xFF111111));
        w.remove();
        h.after(500, this::runRound);
    }

    private void runRound() {
        if (round >= ROUNDS) {
            report();
            return;
        }
        round++;
        List<LatLng> pos = positions();
        List<BitmapDescriptor> a = new ArrayList<>(), b = new ArrayList<>();
        for (int i = 0; i < N; i++) {
            Bitmap bm = bubble(0xFF1E88E5 + i);
            long t0 = System.nanoTime();
            a.add(BitmapDescriptorFactory.fromBitmap(bm));
            tFromBitmap.add(ms(t0));
            b.add(icon(0xFFE53935 + i));
        }
        // 逐个 addMarker
        List<Marker> ms = new ArrayList<>();
        long loop0 = System.nanoTime();
        for (int i = 0; i < N; i++) {
            long t0 = System.nanoTime();
            ms.add(h.amap.addMarker(opts(pos.get(i), a.get(i))));
            tAdd.add(ms(t0));
        }
        tLoopTotal.add(ms(loop0));
        waitDraw(3, 1, 2000, () -> {
            for (int i = 0; i < N; i++) {
                long t0 = System.nanoTime();
                ms.get(i).setIcon(b.get(i));
                tSetIcon.add(ms(t0));
            }
            waitDraw(3, 1, 2000, () -> {
                for (int i = 0; i < N; i++) {
                    LatLng p = pos.get(i);
                    long t0 = System.nanoTime();
                    ms.get(i).setPosition(new LatLng(p.latitude + 0.0003, p.longitude));
                    tSetPos.add(ms(t0));
                }
                waitDraw(3, 1, 2000, () -> {
                    for (Marker m : ms) {
                        long t0 = System.nanoTime();
                        m.remove();
                        tRemove.add(ms(t0));
                    }
                    waitDraw(3, 1, 2000, () -> batch(pos, a));
                });
            });
        });
    }

    /** addMarkers(list, false) 一次加 N 个。 */
    private void batch(List<LatLng> pos, List<BitmapDescriptor> icons) {
        ArrayList<MarkerOptions> list = new ArrayList<>();
        for (int i = 0; i < N; i++) list.add(opts(pos.get(i), icons.get(i)));
        long t0 = System.nanoTime();
        ArrayList<Marker> ms = h.amap.addMarkers(list, false);
        double total = ms(t0);
        tBatchTotal.add(total);
        tBatchPerMarker.add(total / N);
        waitDraw(3, 1, 2000, () -> {
            for (Marker m : ms) m.remove();
            waitDraw(3, 1, 2000, this::runRound);
        });
    }

    private void report() {
        result("fromBitmap(72x40dp)", fmt(stats(tFromBitmap)));
        result("addMarker", fmt(stats(tAdd)));
        result("setIcon", fmt(stats(tSetIcon)));
        result("setPosition", fmt(stats(tSetPos)));
        result("remove", fmt(stats(tRemove)));
        result("loop200.total", fmt(stats(tLoopTotal)));
        result("addMarkers200.total", fmt(stats(tBatchTotal)));
        result("addMarkers.perMarker", fmt(stats(tBatchPerMarker)));
        done();
    }

    private static double ms(long t0) {
        return (System.nanoTime() - t0) / 1e6;
    }

    private BitmapDescriptor icon(int color) {
        return BitmapDescriptorFactory.fromBitmap(bubble(color));
    }

    private Bitmap bubble(int color) {
        float d = h.density();
        Bitmap bm = Bitmap.createBitmap(Math.round(72 * d), Math.round(40 * d), Bitmap.Config.ARGB_8888);
        bm.eraseColor(color);
        return bm;
    }

    private static MarkerOptions opts(LatLng ll, BitmapDescriptor d) {
        return new MarkerOptions().position(ll).icon(d).anchor(0.5f, 1f).infoWindowEnable(false);
    }

    private List<LatLng> positions() {
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        List<LatLng> r = new ArrayList<>();
        for (int i = 0; i < N; i++) {
            r.add(h.fromScreen((i % 10) * w / 10 + w / 20, (i / 10) * ht / 20 + ht / 40));
        }
        return r;
    }
}
