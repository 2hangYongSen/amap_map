package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 交给 MarkerHost 的原生绘制结果：SDK descriptor + 两态共用画布的锚点（§9.2）。
 * native 点位的锚点只来自这里，不读 FullMarkerOptions.anchor。
 */
public final class NativeIcon {
    /** Android 为 BitmapDescriptor，JVM 测试为替身 */
    public final Object descriptor;
    public final float anchorU;
    public final float anchorV;

    public NativeIcon(Object descriptor, float anchorU, float anchorV) {
        this.descriptor = descriptor;
        this.anchorU = anchorU;
        this.anchorV = anchorV;
    }
}
