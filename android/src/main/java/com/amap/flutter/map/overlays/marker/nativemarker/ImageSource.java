package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Map;

/**
 * 资源来源（§6.2 imagesToAdd 的一项），不可变。
 * 字节资源的原始数据一直保留到资源释放，驱逐解码结果后可直接重新解码（R-RES-11）。
 */
public final class ImageSource {
    public static final String TYPE_BYTES = "bytes";
    public static final String TYPE_ASSET = "asset";

    public final String id;
    public final String type;
    /** bytes 来源的原始数据；asset 为 null。不得修改 */
    public final byte[] data;
    public final String asset;
    public final String assetPackage;
    public final double pixelRatio;

    public ImageSource(String id, String type, byte[] data, String asset, String assetPackage,
                       double pixelRatio) {
        this.id = id;
        this.type = type;
        this.data = data;
        this.asset = asset;
        this.assetPackage = assetPackage;
        this.pixelRatio = pixelRatio;
    }

    /** 解析通道载荷；结构不合法时抛 InvalidMarkerException */
    public static ImageSource parse(Object raw) throws InvalidMarkerException {
        SpecReader.require(raw instanceof Map, "imagesToAdd 项必须是对象");
        Map<?, ?> m = (Map<?, ?>) raw;
        String id = SpecReader.optString(m, "id");
        SpecReader.require(id != null && !id.isEmpty(), "资源缺少 id");
        Object pr = m.get("pixelRatio");
        double ratio = pr == null ? 1 : SpecReader.number(pr, "pixelRatio");
        SpecReader.require(ratio > 0 && !Double.isInfinite(ratio), "pixelRatio 必须大于 0");
        Object type = m.get("type");
        if (TYPE_BYTES.equals(type)) {
            Object data = m.get("data");
            SpecReader.require(data instanceof byte[], "bytes 资源缺少 data");
            return new ImageSource(id, TYPE_BYTES, (byte[]) data, null, null, ratio);
        }
        SpecReader.require(TYPE_ASSET.equals(type), "资源 type 非法: " + type);
        String asset = SpecReader.optString(m, "asset");
        SpecReader.require(asset != null && !asset.isEmpty(), "asset 资源缺少 asset");
        return new ImageSource(id, TYPE_ASSET, null, asset, SpecReader.optString(m, "package"), ratio);
    }

    /** 原始数据占用（单独统计，不计入 8MiB 解码预算） */
    public long rawBytes() {
        return data == null ? 0 : data.length;
    }
}
