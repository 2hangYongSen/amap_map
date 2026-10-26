package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 绘制出口：ShapeRenderer 只通过它画图，Android 用 Canvas/Paint 实现，JVM 测试用记录型替身。
 * 坐标均为逻辑像素，原点由 setOrigin 指定（地理锚点所在的画布像素）。
 */
public interface DrawSurface {
    /** 把逻辑坐标原点平移到画布像素 (px, py) */
    void setOrigin(int px, int py);

    void fill(Outline path, int color);

    /** 填充并投影（软件画布 setShadowLayer，E-A5） */
    void fillWithShadow(Outline path, int color, int shadowColor, double blur, double dx, double dy);

    /** 居中描边；width 为逻辑像素 */
    void stroke(Outline path, int color, double width);

    /**
     * 单行文字：x 为文字左端，centerY 为文字行的垂直中线；
     * 基线由平台按字体度量计算，保证行高与测量器一致。
     */
    void text(String text, double x, double centerY, double fontSize, int fontWeight, int color);

    /** 绘制图片切片（NinePatch 的输出：src 为图片像素，dst 为逻辑像素） */
    void image(DecodedImage img, double[][] slices);

    /**
     * 图片背景阴影（§9.3，E-A5）：先把切片合成到 bounds 大小的临时位图，取 alpha 遮罩，
     * 再用阴影色加模糊画到 bounds + offset 处。只画阴影，不画图片本身。
     */
    void imageShadow(DecodedImage img, double[][] slices, RectD bounds, ShadowSpec shadow);
}
