package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 记录 SDK 调用的假地图：id → 当前显示状态 */
final class FakeMarkerHost implements MarkerHost {
    static final String DEFAULT_ICON = "<default>";

    /** 地图上一个 Marker 的当前显示 */
    static final class Shown {
        FullMarkerOptions options;
        Object icon;
        /** 实际生效的 zIndex（选中置顶，§8.5） */
        float zIndex;
    }

    final Map<String, Shown> markers = new LinkedHashMap<>();
    final List<String> calls = new ArrayList<>();

    /** 旧协议登记的点（R-PROTO-1a） */
    void addLegacy(String id, Object icon) {
        Shown s = new Shown();
        s.icon = icon;
        markers.put(id, s);
    }

    @Override
    public boolean hasMarker(String id) {
        return markers.containsKey(id);
    }

    @Override
    public void addMarker(FullMarkerOptions options, Object icon) {
        calls.add("add:" + options.id);
        Shown s = new Shown();
        s.options = options;
        s.icon = icon;
        markers.put(options.id, s);
    }

    @Override
    public void updateMarker(FullMarkerOptions options, Object icon) {
        calls.add("update:" + options.id);
        Shown s = markers.get(options.id);
        s.options = options;
        if (icon != null) {
            s.icon = icon;
        }
    }

    @Override
    public void removeMarker(String id) {
        if (markers.remove(id) != null) {
            calls.add("remove:" + id);
        }
    }

    @Override
    public Iterable<String> markerIds() {
        return markers.keySet();
    }

    /** 图标描述 ["fromAsset", name]：解码结果用 "icon:" + name 表示；"bad" 视为解码失败 */
    @Override
    public Object decodeIcon(Object rawIcon) {
        List<?> l = (List<?>) rawIcon;
        if (l.size() > 1 && "bad".equals(l.get(1))) {
            throw new IllegalArgumentException("decode failed");
        }
        return "icon:" + (l.size() > 1 ? l.get(1) : l.get(0));
    }

    @Override
    public Object defaultIcon() {
        return DEFAULT_ICON;
    }

    /** 为 true 时下一次 native 应用抛异常（applyFailed 路径） */
    boolean failNextNative = false;

    @Override
    public void addNativeMarker(FullMarkerOptions options, NativeIcon icon, boolean selected) {
        failIfAsked();
        calls.add("add:" + options.id);
        Shown s = new Shown();
        s.options = options;
        s.icon = icon.descriptor;
        s.zIndex = options.zIndexFor(selected);
        markers.put(options.id, s);
    }

    /** 批量新增调用次数与每次的点数（验证一次 addMarkers） */
    final List<Integer> batchSizes = new ArrayList<>();
    /** 为 true 时下一次批量新增整批抛异常 */
    boolean failNextBatch = false;

    @Override
    public void addNativeMarkers(List<FullMarkerOptions> os, List<NativeIcon> icons, List<Boolean> selected) {
        if (failNextBatch) {
            failNextBatch = false;
            throw new IllegalStateException("addMarkers 失败");
        }
        batchSizes.add(os.size());
        for (int i = 0; i < os.size(); i++) {
            addNativeMarker(os.get(i), icons.get(i), selected.get(i));
        }
    }

    @Override
    public void updateNativeMarker(FullMarkerOptions options, NativeIcon icon, boolean selected) {
        failIfAsked();
        // icon 为空即只改属性，相当于 setPosition 等（T-GEN-2/4 计数用）
        calls.add((icon == null ? "props:" : "setIcon:") + options.id);
        Shown s = markers.get(options.id);
        s.options = options;
        s.zIndex = options.zIndexFor(selected);
        if (icon != null) {
            s.icon = icon.descriptor;
        }
    }

    /** 每次 native SDK 调用后执行（帧预算测试用来推进假时钟） */
    Runnable onNativeCall;

    private void failIfAsked() {
        if (onNativeCall != null) {
            onNativeCall.run();
        }
        if (failNextNative) {
            failNextNative = false;
            throw new IllegalStateException("SDK 调用失败");
        }
    }

    /** 某类调用的次数，如 count("props:") */
    int count(String prefix) {
        int n = 0;
        for (String c : calls) {
            if (c.startsWith(prefix)) {
                n++;
            }
        }
        return n;
    }
}
