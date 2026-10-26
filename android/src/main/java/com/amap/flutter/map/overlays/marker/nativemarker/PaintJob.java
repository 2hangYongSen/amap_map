package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * 交给后台线程的不可变绘制输入（§8.2）：规格、密度、role 与资源快照。
 * 不含位置等非渲染属性（R-GEN-4）。资源由 RUNNING 引用保护，绘制期间不会被回收（R-DISP-1）。
 */
public final class PaintJob implements ImageSet, Cancelable {
    public final String key;
    public final NativeMarkerSpec spec;
    public final boolean selected;
    public final int densityUnits;
    /** 可用资源的解码结果；不在表中的按 fallback 绘制 */
    private final Map<String, DecodedImage> images;
    private final Map<String, double[]> sizes;
    private final Map<String, Double> ratios;
    private volatile boolean cancelled = false;

    /** readyIds：key 中解析为 ready 的资源，开始前已确认全部解码完成 */
    PaintJob(String key, NativeMarkerSpec spec, boolean selected, int densityUnits,
             ImageRegistry registry, Collection<String> readyIds) {
        this.key = key;
        this.spec = spec;
        this.selected = selected;
        this.densityUnits = densityUnits;
        Map<String, DecodedImage> imgs = new HashMap<>();
        Map<String, double[]> sz = new HashMap<>();
        Map<String, Double> pr = new HashMap<>();
        // 在主线程拍快照，后台只读这几张不可变表；只放 key 认定为 ready 的资源
        for (String id : readyIds) {
            ImageEntry e = registry.entry(id);
            imgs.put(id, e.decoded());
            sz.put(id, registry.logicalSize(id));
            pr.put(id, e.source.pixelRatio);
        }
        this.images = Collections.unmodifiableMap(imgs);
        this.sizes = Collections.unmodifiableMap(sz);
        this.ratios = Collections.unmodifiableMap(pr);
    }

    @Override
    public DecodedImage image(String id) {
        return images.get(id);
    }

    @Override
    public double pixelRatio(String id) {
        Double r = ratios.get(id);
        return r == null ? 1 : r;
    }

    @Override
    public boolean usable(String imageId) {
        return images.containsKey(imageId);
    }

    @Override
    public double[] logicalSize(String imageId) {
        return sizes.get(imageId);
    }

    /** 销毁时置位，Painter 在步骤之间检查（R-DISP-4） */
    @Override
    public boolean isCancelled() {
        return cancelled;
    }

    void cancel() {
        cancelled = true;
    }
}
