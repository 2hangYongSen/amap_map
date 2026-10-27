package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import com.amap.flutter.map.overlays.marker.nativemarker.Diagnostics;

/**
 * 诊断标记方块（R-TIME-6）：地图左上角 8×8dp 的原生 View，仅诊断模式显示。
 * 第一次 show 时才加入地图容器；地图不是 ViewGroup 时不显示（回执中 t2v 为空）。主线程访问。
 */
public final class AndroidDiagSquare implements Diagnostics.Square {
    private final View host;
    private View square;

    public AndroidDiagSquare(View mapView) {
        this.host = mapView;
    }

    @Override
    public void show(int argb) {
        if (square == null && !attach()) {
            return;
        }
        square.setBackgroundColor(argb);
        square.setVisibility(View.VISIBLE);
    }

    @Override
    public void hide() {
        if (square != null) {
            square.setVisibility(View.GONE);
        }
    }

    private boolean attach() {
        if (!(host instanceof ViewGroup)) {
            return false;
        }
        int size = Math.round(8 * host.getResources().getDisplayMetrics().density);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(size, size, Gravity.TOP | Gravity.START);
        square = new View(host.getContext());
        square.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        ((ViewGroup) host).addView(square, lp);
        return true;
    }
}
