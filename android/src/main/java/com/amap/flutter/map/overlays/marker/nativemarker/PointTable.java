package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * 新协议点位表（§8.2）：markerId → {代次, 期望快照, 两态 key, 显示条目, 待删除代次}。
 * 只在主线程访问。
 */
public final class PointTable {

    public static final class Entry {
        public final String id;
        int generation;
        FullMarkerOptions desired;
        String normalKey;
        String selectedKey;
        /** 当前显示的合成位图条目；null 表示还没有显示原生位图 */
        RenderCache.Entry shown;
        /** 已取得 DESIRED 引用的资源 id，归还时一一对应 */
        final Set<String> heldImages = new TreeSet<>();
        /** 待执行删除的代次（R-GEN-6）；null 表示没有 */
        Integer pendingRemoval;
        /** 每个 role（0 普通、1 选中）当前的接收路径：任务登记或应用项，至多其一（R-GEN-2） */
        final Waiter[] waiting = new Waiter[2];
        final ApplyItem[] applying = new ApplyItem[2];
        /** 绘制或应用失败的 key：已报错、保持原显示，不再自动重试，直到 key 变化 */
        final String[] failedKey = new String[2];
        /** D-6：painter 暂不支持该规格，显示协议桩的占位图标，没有 key 与接收路径 */
        boolean placeholder;
        /** R-RES-6/D-5：背景与图标都失败且无文字，不显示；保留期望快照，恢复后按新增处理 */
        boolean hidden;
        /** R-NAT-REJ-2：已为该 normalKey 报过 invalidConfig，key 变化前不再报 */
        String capErrorKey;

        Entry(String id) {
            this.id = id;
        }

        public int generation() {
            return generation;
        }

        public FullMarkerOptions desired() {
            return desired;
        }

        public String normalKey() {
            return normalKey;
        }

        public String selectedKey() {
            return selectedKey;
        }

        public RenderCache.Entry shown() {
            return shown;
        }

        public boolean isRemoving() {
            return pendingRemoval != null;
        }

        /** R-GEN-3：登记仍有效 = 代次未变、该 role 的 key 未变、没有待删除 */
        boolean isValid(int gen, boolean selected, String key) {
            return pendingRemoval == null && generation == gen
                    && key.equals(selected ? selectedKey : normalKey);
        }

        /** role 下标：0 普通态，1 选中态 */
        static int role(boolean selected) {
            return selected ? 1 : 0;
        }
    }

    private final Map<String, Entry> entries = new LinkedHashMap<>();
    /** 全局递增：同一 id 删除后重新加入，代次继续增大、不归零（§8.1） */
    private int nextGeneration = 0;

    public Entry get(String id) {
        return entries.get(id);
    }

    /** 整体替换期望快照（R-PROTO-2），代次 +1，清除待删除标记 */
    public Entry put(FullMarkerOptions desired) {
        Entry e = entries.get(desired.id);
        if (e == null) {
            e = new Entry(desired.id);
            entries.put(desired.id, e);
        }
        e.desired = desired;
        e.generation = ++nextGeneration;
        e.pendingRemoval = null;
        return e;
    }

    /** 期望快照不变但 key 需要重算（资源状态变化，R-RES-12）：代次 +1 */
    void touch(String id) {
        entries.get(id).generation = ++nextGeneration;
    }

    /** R-GEN-6：删除先递增代次得到 g 并标记待删除 */
    int beginRemoval(String id) {
        Entry e = entries.get(id);
        e.generation = ++nextGeneration;
        e.pendingRemoval = e.generation;
        return e.generation;
    }

    /** 删除到期时校验：代次仍为 g 才能执行，否则说明之后被重新加入 */
    boolean isRemovalCurrent(String id, int g) {
        Entry e = entries.get(id);
        return e != null && e.pendingRemoval != null && e.pendingRemoval == g && e.generation == g;
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

    public Collection<Entry> values() {
        return entries.values();
    }

    public void clear() {
        entries.clear();
    }
}
