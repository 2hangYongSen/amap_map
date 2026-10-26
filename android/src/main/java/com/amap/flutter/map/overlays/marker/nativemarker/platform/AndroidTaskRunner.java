package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.os.Handler;
import android.os.Looper;
import android.os.Process;

import com.amap.flutter.map.overlays.marker.nativemarker.TaskRunner;
import com.amap.flutter.map.utils.LogUtil;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadFactory;

/**
 * 单后台线程（THREAD_PRIORITY_BACKGROUND）加主线程 Handler（R-DISP-3）。
 * Handler 的 Runnable 只引用管理器内部对象，不持有 Activity 或 MapView。
 */
public final class AndroidTaskRunner implements TaskRunner {
    private static final String CLASS_NAME = "AndroidTaskRunner";
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
    public boolean background(Runnable r) {
        try {
            executor.execute(r);
            return true;
        } catch (RejectedExecutionException e) {
            // 不吞掉：交给调用方在主线程立即归还（running--），否则 terminated 永远等不到
            LogUtil.d(CLASS_NAME, "后台任务被拒绝，立即归还: " + e.getMessage());
            return false;
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
    public void cancelMainDelayed(Runnable r) {
        mainHandler.removeCallbacks(r);
    }

    /**
     * 不用 shutdownNow：它返回的未执行任务不会再投递归还，running 永不归零。
     * 排队中的任务由调用方的取消标记撤销：出队后不解码、不绘制，只走归还（§8.6）。
     */
    @Override
    public void shutdown() {
        executor.shutdown();
    }
}
