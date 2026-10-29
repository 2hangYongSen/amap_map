package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 文字测量（R-NORM-4）：由平台实现（S10 用 Paint），JVM 测试用替身。
 * 输入全部来自 NormSpec，同一设备上结果确定。
 */
public interface TextMeasurer {
    /** 单行文字宽度（逻辑像素） */
    double width(String text, double fontSize, int fontWeight);

    /** 单行文字高度（逻辑像素） */
    double lineHeight(double fontSize, int fontWeight);
}
