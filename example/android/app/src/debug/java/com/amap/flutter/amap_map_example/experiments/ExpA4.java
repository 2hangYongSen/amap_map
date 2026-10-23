package com.amap.flutter.amap_map_example.experiments;

import android.graphics.Point;
import android.os.SystemClock;
import android.view.MotionEvent;

import com.amap.api.maps.AMap;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;
import com.amap.api.maps.model.Poi;

import java.util.ArrayList;
import java.util.List;

/**
 * E-A4：点击 Marker 时是否同时触发 onMapClick / onPOIClick，以及回调顺序。
 * 每个阶段输出 TAP 行（屏幕坐标），主机脚本 tool/s6_run.sh 用 adb input tap 执行后发送 step=next。
 * 阶段：
 *  0 扫描 6×8 网格，记录哪些位置触发 onPOIClick、哪些只触发 onMapClick；
 *  1 在“空白”和“POI”位置各放一个 Marker，onMarkerClick 返回 true（插件现状），各点一次，再点一次空白处对照；
 *  2..n onMarkerClick 返回 false，每次只点一个 Marker（SDK 会移动相机，所以每次重新计算坐标）。
 * 回调都带 vsync 帧号与 uptime，用来判断是否属于同一次触摸。
 */
class ExpA4 extends Experiment {
    private final List<LatLng> poiHits = new ArrayList<>(), blankHits = new ArrayList<>();
    private boolean consume = true;
    private int tapSeq, stage;
    private Marker blankMarker, poiMarker;

    @Override
    void start() {
        AMap a = h.amap;
        a.addOnMarkerClickListener(m -> {
            ev("onMarkerClick id=" + m.getTitle() + " return=" + consume);
            return consume;
        });
        a.addOnMapClickListener(ll -> {
            ev("onMapClick " + ll);
            if (stage == 0) blankHits.add(ll);
        });
        a.addOnPOIClickListener(this::onPoi);
        a.setOnMapTouchListener(e -> {
            if (e.getAction() == MotionEvent.ACTION_UP) ev("onTouch UP");
        });
        int w = h.mapView.getWidth(), ht = h.mapView.getHeight();
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 6; x++) {
                requestTap("scan", Math.round((x + 0.5f) * w / 6), Math.round(ht * 0.15f + (y + 0.5f) * ht * 0.8f / 8));
            }
        }
        h.log("WAIT_TAPS");
    }

    private void onPoi(Poi p) {
        ev("onPOIClick name=" + p.getName() + " at=" + p.getCoordinate());
        if (stage == 0) poiHits.add(p.getCoordinate());
    }

    private void ev(String s) {
        h.log("EV f=" + h.frameNo + " t=" + SystemClock.uptimeMillis() + " " + s);
    }

    private void requestTap(String label, int mapX, int mapY) {
        int[] loc = new int[2];
        h.mapView.getLocationOnScreen(loc);
        h.log("TAP " + (++tapSeq) + " " + (mapX + loc[0]) + " " + (mapY + loc[1]) + " " + label);
    }

    private void requestTap(String label, LatLng ll) {
        Point p = h.toScreen(ll);
        requestTap(label, p.x, p.y);
    }

    @Override
    void onStep(String step) {
        stage++;
        switch (stage) {
            case 1: {
                result("scan", "poi=" + poiHits.size() + " mapOnly=" + blankHits.size());
                // 空白处取中间一个只触发 onMapClick 的位置
                LatLng blank = blankHits.get(blankHits.size() / 2);
                blankMarker = add(blank, 0xFFE53935, "blank");
                if (!poiHits.isEmpty()) poiMarker = add(poiHits.get(0), 0xFF1E88E5, "poi");
                h.after(800, () -> {
                    h.log("PHASE consume=true");
                    requestTap("marker-blank-consume", blankMarker.getPosition());
                    if (poiMarker != null) requestTap("marker-poi-consume", poiMarker.getPosition());
                    requestTap("control-empty-near-blank", h.toScreen(blank).x + Math.round(60 * h.density()),
                            h.toScreen(blank).y);
                    h.log("WAIT_TAPS");
                });
                break;
            }
            case 2:
                consume = false;
                h.log("PHASE consume=false (blank)");
                requestTap("marker-blank-pass", blankMarker.getPosition());
                h.log("WAIT_TAPS");
                break;
            case 3:
                // 上一步 SDK 可能已移动相机，等动画结束后再算坐标
                h.after(1500, () -> {
                    h.log("PHASE consume=false (poi)");
                    if (poiMarker != null) requestTap("marker-poi-pass", poiMarker.getPosition());
                    h.log("WAIT_TAPS");
                });
                break;
            default:
                done();
                break;
        }
    }

    private Marker add(LatLng ll, int color, String title) {
        return h.amap.addMarker(new MarkerOptions().position(ll).title(title)
                .icon(BitmapDescriptorFactory.fromBitmap(dot(color, Math.round(36 * h.density()))))
                .anchor(0.5f, 0.5f).infoWindowEnable(false));
    }
}
