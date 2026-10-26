package com.amap.flutter.map.overlays.marker.nativemarker;

/** 线程出口：后台执行与投递回主线程。JVM 测试用可控替身逐步执行 */
public interface TaskRunner {
    void background(Runnable r);

    void main(Runnable r);

    /** 主线程延迟执行（销毁后 10s 卡住检查，R-DISP-4） */
    void mainDelayed(Runnable r, long delayMillis);

    /**
     * 不再接受新的后台任务；已在执行的任务继续跑完。只相当于 ExecutorService.shutdown()，
     * 不等待、不中断（R-DISP-3），主线程投递仍然可用。
     */
    void shutdown();
}
