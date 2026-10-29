package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 图片背景绘制（§9.3）：固定尺寸或九宫格，阴影走遮罩方式（E-A5），箭头单独画三角形。纯计算。
 * 顺序：图片阴影 → 箭头（含阴影）→ 图片本体，图片最后画，盖住箭头阴影漫到主体上的部分。
 */
final class ImageDrawing {
    private ImageDrawing() {
    }

    /** 箭头底边与图片主体的重叠量：1 物理像素 */
    static double arrowOverlap(double density) {
        return 1 / density;
    }

    static void background(NormStyle style, StateLayout st, double ox, double oy, double density,
                           ImageSet images, DrawSurface s, Cancelable c) {
        DecodedImage img = images == null ? null : images.image(style.imageId);
        if (img == null) {
            throw new IllegalStateException("背景资源不可用: " + style.imageId);
        }
        RectD body = st.body.offset(ox, oy);
        double[][] slices = NinePatch.slices(img.width(), img.height(),
                images.pixelRatio(style.imageId), style.capInsets, body);
        ShadowSpec shadow = ShadowSpec.of(style);
        if (shadow != null) {
            s.imageShadow(img, slices, body, shadow);
            ShapeRenderer.check(c);
        }
        if (style.hasArrow) {
            // 图片背景下 arrow.color 必填（NormStyle 已校验）；箭头不参与九宫格拉伸。
            // 底边向主体内多伸 1 物理像素，之后画的图片会盖住它，消除抗锯齿发丝缝
            Outline tri = OutlineBuilder.triangle(st.arrowTipX + ox, st.arrowTipY + oy,
                    body.bottom - arrowOverlap(density), Norm.length(style.arrowWidth));
            if (shadow != null) {
                s.fillWithShadow(tri, style.arrowColor, shadow.color, shadow.blur, shadow.dx,
                        shadow.dy);
            } else {
                s.fill(tri, style.arrowColor);
            }
            ShapeRenderer.check(c);
        }
        s.image(img, slices);
    }
}
