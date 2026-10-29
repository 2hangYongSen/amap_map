package com.amap.flutter.map.overlays.marker.nativemarker;

/** 偏差 V-2：API 28 以下没有精确字重，只能在常规与粗体之间二选一 */
public final class FontWeights {
    private FontWeights() {
    }

    /** 400/500 → 常规，600/700 → 粗体 */
    public static boolean isBoldFallback(int weight) {
        return weight >= 600;
    }
}
