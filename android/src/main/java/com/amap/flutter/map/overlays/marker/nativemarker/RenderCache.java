package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 合成位图缓存（§8.5）：key → descriptor，三类引用，32MiB 软预算，LRU 淘汰。
 * 只保存 SDK descriptor，合成位图在 fromBitmap 后已回收（R-CACHE-3）。主线程访问。
 */
public final class RenderCache {
    public static final long DEFAULT_BUDGET = 32L * 1024 * 1024;

    public static final class Entry {
        public final String key;
        public final Object descriptor;
        public final float anchorU;
        public final float anchorV;
        public final long byteSize;
        int displayRefs;
        int pendingRefs;
        int retainedRefs;
        long lastUsed;

        Entry(String key, Object descriptor, float u, float v, long byteSize) {
            this.key = key;
            this.descriptor = descriptor;
            this.anchorU = u;
            this.anchorV = v;
            this.byteSize = byteSize;
        }

        public int displayRefs() { return displayRefs; }
        public int pendingRefs() { return pendingRefs; }
        public int retainedRefs() { return retainedRefs; }

        /** R-CACHE-2：三类引用都归零才可淘汰 */
        public boolean evictable() {
            return displayRefs == 0 && pendingRefs == 0 && retainedRefs == 0;
        }

        NativeIcon icon() {
            return new NativeIcon(descriptor, anchorU, anchorV);
        }
    }

    private final Map<String, Entry> entries = new LinkedHashMap<>();
    private final IconFactory factory;
    private final long budget;
    private long bytes = 0;
    private long clock = 0;
    private boolean overBudget = false;
    private int evictCount = 0;

    public RenderCache(IconFactory factory, long budgetBytes) {
        this.factory = factory;
        this.budget = budgetBytes;
    }

    public Entry get(String key) {
        Entry e = entries.get(key);
        if (e != null) {
            e.lastUsed = ++clock;
        }
        return e;
    }

    public boolean contains(String key) {
        return entries.containsKey(key);
    }

    /** 任务结果入缓存：此刻转成 descriptor 并回收合成位图（R-CACHE-3） */
    Entry put(String key, Object bitmap, float u, float v) {
        Object desc = factory.toDescriptor(bitmap);
        Entry e = new Entry(key, desc, u, v, factory.byteCount(desc));
        e.lastUsed = ++clock;
        entries.put(key, e);
        bytes += e.byteSize;
        return e;
    }

    // ---------- 引用（R-CACHE-1），成对调用，多还即不变量破坏 ----------

    void addPending(Entry e) { e.pendingRefs++; }

    void dropPending(Entry e) {
        check(e.pendingRefs > 0, e, "pendingRefs");
        e.pendingRefs--;
    }

    void addDisplay(Entry e) { e.displayRefs++; e.lastUsed = ++clock; }

    void dropDisplay(Entry e) {
        check(e.displayRefs > 0, e, "displayRefs");
        e.displayRefs--;
    }

    void addRetained(Entry e) { e.retainedRefs++; }

    void dropRetained(Entry e) {
        check(e.retainedRefs > 0, e, "retainedRefs");
        e.retainedRefs--;
    }

    /**
     * R-CACHE-4：超预算时按 LRU 淘汰满足 R-CACHE-2 的条目。
     * 调用方须在 setIcon/remove 返回、引用已转移之后再调用。
     */
    void enforceBudget() {
        if (bytes > budget) {
            List<Entry> victims = new ArrayList<>();
            for (Entry e : entries.values()) {
                if (e.evictable()) {
                    victims.add(e);
                }
            }
            victims.sort((a, b) -> Long.compare(a.lastUsed, b.lastUsed));
            for (Entry v : victims) {
                if (bytes <= budget) {
                    break;
                }
                evict(v);
            }
        }
        overBudget = bytes > budget;
    }

    /** 强制淘汰全部可淘汰条目（diag#clearCaches 与测试用） */
    void evictAllEvictable() {
        for (Entry e : new ArrayList<>(entries.values())) {
            if (e.evictable()) {
                evict(e);
            }
        }
        overBudget = bytes > budget;
    }

    /** R-CACHE-3：回收 SDK 副本，预算减去，条目不再被缓存引用 */
    private void evict(Entry e) {
        check(e.evictable(), e, "evict");
        entries.remove(e.key);
        bytes -= e.byteSize;
        factory.recycleCopy(e.descriptor);
        evictCount++;
    }

    // ---------- 查询 ----------

    /** R-PRI-3 条件 1：占用 ≥ 软预算 90% */
    public boolean nearBudget() {
        return bytes * 10 >= budget * 9;
    }

    /** 活动条目超出预算（memory.compositeOverBudget），不强制回收 */
    public boolean overBudget() { return overBudget; }

    public long bytes() { return bytes; }

    public int size() { return entries.size(); }

    public int evictCount() { return evictCount; }

    public Collection<Entry> entries() { return entries.values(); }

    private static void check(boolean ok, Entry e, String what) {
        if (!ok) {
            throw new IllegalStateException("缓存引用不成对: " + what + " " + e.key);
        }
    }
}
