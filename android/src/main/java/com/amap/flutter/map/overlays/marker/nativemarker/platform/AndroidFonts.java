package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.graphics.Typeface;
import android.os.Build;

import com.amap.flutter.map.overlays.marker.nativemarker.FontWeights;

import java.util.HashMap;
import java.util.Map;

/** 字体选择（§9.3）：API 28+ 用精确字重，更低按 V-2 降级（400/500 常规，600/700 粗体） */
final class AndroidFonts {
    private static final Map<Integer, Typeface> CACHE = new HashMap<>();

    private AndroidFonts() {
    }

    static synchronized Typeface typeface(int weight) {
        Typeface t = CACHE.get(weight);
        if (t == null) {
            if (Build.VERSION.SDK_INT >= 28) {
                t = Typeface.create(Typeface.DEFAULT, weight, false);
            } else {
                t = FontWeights.isBoldFallback(weight) ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT;
            }
            CACHE.put(weight, t);
        }
        return t;
    }
}
