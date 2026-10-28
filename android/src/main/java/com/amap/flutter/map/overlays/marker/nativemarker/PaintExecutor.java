package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.concurrent.PriorityBlockingQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 后台执行器：固定 N 个线程共用一个优先级队列（§8.2）。
 * 调度器一次派发多个任务（maxRunning 个在途），线程画完一个直接取下一个，不必等主线程。
 * 队列按 (优先级, 提交顺序) 出队：P0（选中态）插到已排队的 P1/P2 前面；
 * 非 {@link Prioritized} 的任务（图片解码）排最前，它们会解除绘制任务的等待。
 * 纯 Java，JVM 测试可直接使用。
 */
public final class PaintExecutor {
    /** 带优先级的后台任务；数值越小越先执行 */
    public interface Prioritized extends Runnable {
        int priority();
    }

    /** 图片解码等普通任务的优先级：排在所有绘制任务之前 */
    static final int UNPRIORITIZED = -1;

    private final AtomicLong seq = new AtomicLong();
    private final ThreadPoolExecutor pool;

    public PaintExecutor(int threads, ThreadFactory factory) {
        pool = new ThreadPoolExecutor(threads, threads, 0L, TimeUnit.MILLISECONDS,
                new PriorityBlockingQueue<Runnable>(), factory);
    }

    /** 提交；已关闭时抛 RejectedExecutionException（与 ExecutorService.execute 一致） */
    public void execute(Runnable r) {
        int p = r instanceof Prioritized ? ((Prioritized) r).priority() : UNPRIORITIZED;
        pool.execute(new Entry(p, seq.getAndIncrement(), r));
    }

    /** 不再接受新任务；已排队的照常执行完（它们会检查取消标记，只走归还） */
    public void shutdown() {
        pool.shutdown();
    }

    /** 队列中的元素：先比优先级，同级按提交顺序 */
    private static final class Entry implements Runnable, Comparable<Entry> {
        final int priority;
        final long seq;
        final Runnable r;

        Entry(int priority, long seq, Runnable r) {
            this.priority = priority;
            this.seq = seq;
            this.r = r;
        }

        @Override
        public void run() {
            r.run();
        }

        @Override
        public int compareTo(Entry o) {
            return priority != o.priority ? Integer.compare(priority, o.priority)
                    : Long.compare(seq, o.seq);
        }
    }
}
