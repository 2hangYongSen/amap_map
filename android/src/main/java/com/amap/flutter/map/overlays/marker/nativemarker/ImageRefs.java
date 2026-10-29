package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * 期望快照对资源的 DESIRED 引用与反向索引 imageId → {markerId}（R-RES-1、R-RES-12）。主线程访问。
 */
final class ImageRefs {
    private final ImageRegistry registry;
    private final Map<String, Set<String>> index = new HashMap<>();

    ImageRefs(ImageRegistry registry) {
        this.registry = registry;
    }

    /**
     * 把点位持有的资源换成 wanted：先取新引用再还旧引用，同一资源不会出现空档。
     * @return 注册表中不存在的资源 id（调用方报 imageMissing）
     */
    List<String> hold(PointTable.Entry p, Set<String> wanted) {
        List<String> missing = new ArrayList<>();
        for (String id : wanted) {
            if (p.heldImages.contains(id)) {
                continue;
            }
            if (registry.acquire(id, ImageEntry.Ref.DESIRED)) {
                p.heldImages.add(id);
                indexOf(id).add(p.id);
            } else {
                missing.add(id);
            }
        }
        for (String id : new ArrayList<>(p.heldImages)) {
            if (!wanted.contains(id)) {
                p.heldImages.remove(id);
                unindex(id, p.id);
                registry.unref(id, ImageEntry.Ref.DESIRED);
            }
        }
        return missing;
    }

    /** 删除、native→icon、销毁：归还全部期望引用 */
    void releaseAll(PointTable.Entry p) {
        hold(p, new TreeSet<String>());
    }

    /** 引用该资源的点位（快照，调用方可在遍历中修改点位） */
    List<String> markersOf(String imageId) {
        Set<String> s = index.get(imageId);
        return s == null ? new ArrayList<String>() : new ArrayList<>(s);
    }

    private Set<String> indexOf(String id) {
        Set<String> s = index.get(id);
        if (s == null) {
            s = new TreeSet<>();
            index.put(id, s);
        }
        return s;
    }

    private void unindex(String imageId, String markerId) {
        Set<String> s = index.get(imageId);
        if (s != null) {
            s.remove(markerId);
            if (s.isEmpty()) {
                index.remove(imageId);
            }
        }
    }
}
