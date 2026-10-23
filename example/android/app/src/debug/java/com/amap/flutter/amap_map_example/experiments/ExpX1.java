package com.amap.flutter.amap_map_example.experiments;

import android.graphics.Bitmap;
import android.graphics.Point;

import com.amap.api.maps.AMap;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

/**
 * E-X1（Android 部分）：AMap.getMapScreenShot（插件 map#takeSnapshot 的实现）是否包含 Marker。
 * 放 5 个纯色点，截图后在点位坐标取色；同时与 TextureView.getBitmap 的结果对照，
 * 并测一次 setIcon 后立即截图能否拿到新图标（截图时效性）。
 */
class ExpX1 extends Experiment {
    private static final int[] C = {0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFF8E24AA, 0xFFFB8C00};
    private final LatLng[] pos = new LatLng[C.length];
    private final Marker[] ms = new Marker[C.length];

    @Override
    void start() {
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        int px = Math.round(28 * h.density());
        for (int i = 0; i < C.length; i++) {
            pos[i] = h.fromScreen(w * (i + 1) / (C.length + 1), ht / 2);
            ms[i] = h.amap.addMarker(new MarkerOptions().position(pos[i]).anchor(0.5f, 0.5f)
                    .icon(BitmapDescriptorFactory.fromBitmap(dot(C[i], px))).infoWindowEnable(false));
        }
        waitDraw(5, 3, 3000, () -> shot("steady", C, () -> {
            // 时效性：改第 0 个点颜色后立即截图
            int[] next = C.clone();
            next[0] = 0xFF00ACC1;
            ms[0].setIcon(BitmapDescriptorFactory.fromBitmap(dot(next[0], px)));
            shot("afterSetIconImmediate", next, () -> waitDraw(3, 2, 2000,
                    () -> shot("afterSetIconDrawn", next, this::done)));
        }));
    }

    private void shot(String tag, int[] expect, Runnable next) {
        final long t0 = System.nanoTime();
        h.amap.getMapScreenShot(new AMap.OnMapScreenShotListener() {
            @Override
            public void onMapScreenShot(Bitmap b) {
                report(tag, b, expect, t0);
                next.run();
            }

            @Override
            public void onMapScreenShot(Bitmap b, int status) {
                h.log("screenshot status=" + status);
            }
        });
    }

    private void report(String tag, Bitmap snap, int[] expect, long t0) {
        double ms = (System.nanoTime() - t0) / 1e6;
        if (snap == null) {
            result(tag, "snapshot=null");
            return;
        }
        Bitmap tex = h.frame();
        int okSnap = 0, okTex = 0;
        for (int i = 0; i < expect.length; i++) {
            Point p = h.toScreen(pos[i]);
            if (isColor(snap, p, expect[i])) okSnap++;
            if (tex != null && isColor(tex, p, expect[i])) okTex++;
        }
        h.savePng(snap, "X1_" + tag + "_snapshot.png");
        result(tag, "snapshotMarkers=" + okSnap + "/" + expect.length + " textureMarkers=" + okTex
                + "/" + expect.length + " size=" + snap.getWidth() + "x" + snap.getHeight()
                + " latencyMs=" + String.format("%.1f", ms));
    }
}
