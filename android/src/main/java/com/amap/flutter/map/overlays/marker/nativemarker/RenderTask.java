package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.List;

/** TaskTable 的一项（§8.2）：按渲染 key 共享，按点位登记等待者（R-GEN-1）。主线程读写 */
final class RenderTask {
    enum State { QUEUED, RUNNING, CANCELLED, DONE }

    /** §8.3 优先级，数值越小越先执行 */
    static final int P0 = 0;
    static final int P1 = 1;
    static final int P2 = 2;

    final String key;
    final NativeMarkerSpec spec;
    final boolean selected;
    /** 创建顺序，同优先级先来先做 */
    final long seq;
    /** 取得了 QUEUED（执行后改为 RUNNING）引用的资源 id */
    final List<String> images = new ArrayList<>();
    /** key 中解析为 ready 的资源；开始前必须已解码，绘制只用它们 */
    final List<String> expectReady = new ArrayList<>();
    final List<Waiter> waiters = new ArrayList<>();
    int priority;
    State state = State.QUEUED;
    PaintJob job;
    RenderTask(String key, NativeMarkerSpec spec, boolean selected, int priority, long seq) {
        this.key = key;
        this.spec = spec;
        this.selected = selected;
        this.priority = priority;
        this.seq = seq;
    }

    /** 同优先级按 seq；用于从排队集合中挑下一个 */
    boolean before(RenderTask o) {
        return priority != o.priority ? priority < o.priority : seq < o.seq;
    }
}
