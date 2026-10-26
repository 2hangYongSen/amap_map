package com.amap.flutter.map.overlays.marker.nativemarker;

/** 线程出口：后台执行与投递回主线程。JVM 测试用可控替身逐步执行 */
public interface TaskRunner {
    /**
     * 提交后台任务。执行器已关闭而拒绝时返回 false，任务不会执行，
     * 调用方必须在当前（主）线程立即完成归还（running--、检查 terminated）。
     */
    boolean background(Runnable r);

    void main(Runnable r);

    /** 主线程延迟执行（销毁后 10s 卡住检查，R-DISP-4） */
    void mainDelayed(Runnable r, long delayMillis);

    /** 撤销 mainDelayed 投递、尚未执行的任务（Handler.removeCallbacks），r 须为同一实例 */
    void cancelMainDelayed(Runnable r);

    /**
     * 不再接受新的后台任务；已在执行的任务继续跑完。只相当于 ExecutorService.shutdown()，
     * 不等待、不中断（R-DISP-3），主线程投递仍然可用。
     */
    void shutdown();
}
