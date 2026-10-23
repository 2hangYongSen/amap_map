package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.List;

/**
 * 解码软预算（R-RES-11）的纯计算部分：统计占用并挑选可淘汰条目。
 * 只淘汰 ready、未释放、没有排队/执行中任务需要的解码结果，按最近使用时间从旧到新。
 */
final class DecodeBudget {
    static final long DEFAULT_BYTES = 8L * 1024 * 1024;

    private DecodeBudget() {
    }

    static long decodedBytes(Collection<ImageEntry> entries) {
        long sum = 0;
        for (ImageEntry e : entries) {
            if (e.decoded != null) {
                sum += e.decoded.byteCount();
            }
        }
        return sum;
    }

    static long rawBytes(Collection<ImageEntry> entries) {
        long sum = 0;
        for (ImageEntry e : entries) {
            sum += e.source.rawBytes();
        }
        return sum;
    }

    static boolean evictable(ImageEntry e) {
        return e.state == ImageEntry.State.READY && e.decoded != null && !e.releasing
                && !e.neededByTask();
    }

    /** 返回需要淘汰的条目（LRU）；淘汰完仍超预算时，剩余部分都是被引用的，不强制回收 */
    static List<ImageEntry> victims(Collection<ImageEntry> entries, long budget) {
        long over = decodedBytes(entries) - budget;
        if (over <= 0) {
            return Collections.emptyList();
        }
        List<ImageEntry> candidates = new ArrayList<>();
        for (ImageEntry e : entries) {
            if (evictable(e)) {
                candidates.add(e);
            }
        }
        Collections.sort(candidates, (a, b) -> Long.compare(a.lastUsed, b.lastUsed));
        List<ImageEntry> out = new ArrayList<>();
        for (ImageEntry e : candidates) {
            if (over <= 0) {
                break;
            }
            out.add(e);
            over -= e.decoded.byteCount();
        }
        return out;
    }
}
