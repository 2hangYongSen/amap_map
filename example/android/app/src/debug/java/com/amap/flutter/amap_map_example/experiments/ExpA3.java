package com.amap.flutter.amap_map_example.experiments;

import android.graphics.Point;

import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

/**
 * E-A3：运行中 setZIndex(99) 能否立刻改变重叠顺序；同时对比 setToTop()。
 * 三个同位置的点 R(z=1)、G(z=2)、B(z=3)，B 在最上。依次把 R 提到 99、再降回 1，
 * 记录多少帧后屏幕中心颜色变化；重复 20 次。
 */
class ExpA3 extends Experiment {
    private static final int R = 0xFFE53935, G = 0xFF43A047, B = 0xFF1E88E5;
    private Marker r, g, b;
    private Point center;
    private int iter, zOk, zFrames, restoreOk, topOk, topFrames, bgOk;

    @Override
    void start() {
        LatLng ll = h.fromScreen(h.mapView.getWidth() / 2, h.mapView.getHeight() / 2);
        int px = Math.round(40 * h.density());
        r = add(ll, R, 1);
        g = add(ll, G, 2);
        b = add(ll, B, 3);
        center = h.toScreen(ll);
        waitDraw(3, 2, 3000, () -> {
            result("initialTopIsBlue", String.valueOf(isColor(h.frame(), center, B)));
            loop();
        });
    }

    private void loop() {
        if (iter >= 20) {
            result("setZIndex99", zOk + "/20 frames(avg)=" + (zFrames / Math.max(1, zOk)));
            result("setZIndexRestore", restoreOk + "/20");
            result("setToTop", topOk + "/20 frames(avg)=" + (topFrames / Math.max(1, topOk)));
            result("backgroundZ(setZIndex on hidden marker only)", bgOk + "/20");
            done();
            return;
        }
        iter++;
        r.setZIndex(99);
        poll(R, 10, f -> {
            if (f >= 0) {
                zOk++;
                zFrames += f;
            }
            r.setZIndex(1);
            poll(B, 10, f2 -> {
                if (f2 >= 0) restoreOk++;
                // setToTop 对比：G 当前在中间
                g.setToTop();
                if (iter == 1) h.log("afterSetToTop zG=" + g.getZIndex() + " zB=" + b.getZIndex());
                poll(G, 10, f3 -> {
                    if (f3 >= 0) {
                        topOk++;
                        topFrames += f3;
                    }
                    // setToTop 之后 setZIndex 能否把顺序改回（B 提到 100）
                    b.setZIndex(100);
                    poll(B, 10, f4 -> {
                        if (f4 >= 0) bgOk++;
                        // 复位：G 回到 2
                        g.setZIndex(2);
                        b.setZIndex(3);
                        waitDraw(2, 1, 1000, this::loop);
                    });
                });
            });
        });
    }

    interface FrameResult {
        void on(int frames);
    }

    /** 每帧取中心色，至多 maxFrames 帧；返回第几帧出现目标色，-1 表示没出现。 */
    private void poll(int color, int maxFrames, FrameResult cb) {
        final int[] n = {0};
        Runnable step = new Runnable() {
            @Override
            public void run() {
                if (isColor(h.frame(), center, color)) {
                    cb.on(n[0]);
                } else if (n[0]++ >= maxFrames) {
                    h.log("poll miss want=" + hex(color) + " got=" + hex(h.frame().getPixel(center.x, center.y)));
                    cb.on(-1);
                } else {
                    waitDraw(1, 1, 200, this);
                }
            }
        };
        waitDraw(1, 1, 200, step);
    }

    private Marker add(LatLng ll, int color, float z) {
        return h.amap.addMarker(new MarkerOptions().position(ll)
                .icon(BitmapDescriptorFactory.fromBitmap(dot(color, Math.round(40 * h.density()))))
                .anchor(0.5f, 0.5f).zIndex(z).infoWindowEnable(false));
    }
}
