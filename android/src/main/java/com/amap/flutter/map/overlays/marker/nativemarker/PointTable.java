package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 新协议点位表：markerId → {代次, 期望快照}（§8.2）。
 * S5 只保存期望快照；显示条目与任务在 S9 接入。主线程访问。
 */
public final class PointTable {

    public static final class Entry {
        public final String id;
        /** 期望快照每次整体替换 +1（R-GEN-1 的雏形） */
        public final int generation;
        public final FullMarkerOptions desired;

        Entry(String id, int generation, FullMarkerOptions desired) {
            this.id = id;
            this.generation = generation;
            this.desired = desired;
        }
    }

    private final Map<String, Entry> entries = new LinkedHashMap<>();

    public Entry get(String id) {
        return entries.get(id);
    }

    /** 整体替换期望快照，不做逐字段合并（R-PROTO-2） */
    public Entry put(FullMarkerOptions desired) {
        Entry old = entries.get(desired.id);
        Entry next = new Entry(desired.id, old == null ? 1 : old.generation + 1, desired);
        entries.put(desired.id, next);
        return next;
    }

    public void remove(String id) {
        entries.remove(id);
    }

    public int size() {
        return entries.size();
    }

    public List<String> ids() {
        return new ArrayList<>(entries.keySet());
    }

    public void clear() {
        entries.clear();
    }
}
