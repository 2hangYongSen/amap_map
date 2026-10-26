package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.os.Handler;
import android.os.Looper;
import android.os.Process;

import com.amap.flutter.map.overlays.marker.nativemarker.TaskRunner;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadFactory;

/**
 * 单后台线程（THREAD_PRIORITY_BACKGROUND）加主线程 Handler（R-DISP-3）。
 * Handler 的 Runnable 只引用管理器内部对象，不持有 Activity 或 MapView。
 */
public final class AndroidTaskRunner implements TaskRunner {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor(new ThreadFactory() {
        @Override
        public Thread newThread(final Runnable r) {
            return new Thread(new Runnable() {
                @Override
                public void run() {
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND);
                    r.run();
                }
            }, "amap-native-marker");
        }
    });

    @Override
    public void background(Runnable r) {
        try {
            executor.execute(r);
        } catch (RejectedExecutionException ignored) {
            // shutdown 之后不会再有新任务（调度器已停止），到这里说明竞态，忽略即可
        }
    }

    @Override
    public void main(Runnable r) {
        mainHandler.post(r);
    }

    @Override
    public void mainDelayed(Runnable r, long delayMillis) {
        mainHandler.postDelayed(r, delayMillis);
    }

    @Override
    public void shutdown() {
        executor.shutdown(); // 不用 shutdownNow：中断停不下 Canvas 绘制，且会丢弃已排队任务的归还
    }
}
