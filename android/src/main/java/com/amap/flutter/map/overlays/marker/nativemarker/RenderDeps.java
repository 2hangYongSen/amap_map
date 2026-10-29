package com.amap.flutter.map.overlays.marker.nativemarker;

/**
 * 完整渲染模式所需的平台出口。NativeMarkerManager 没拿到它时保持 S5 协议桩行为（占位图标），
 * 保证半成品不对业务暴露；S10 由 MarkersController 提供 Android 实现。
 */
public final class RenderDeps {
    public final ImageDecoder decoder;
    public final TaskRunner runner;
    public final MarkerPainter painter;
    public final IconFactory icons;
    public final FrameClock clock;
    /** 设备密度的 1/1024 单位：Norm.ratioUnits(ConvertUtil.density) */
    public final int densityUnits;
    public long decodeBudget = DecodeBudget.DEFAULT_BYTES;
    public long cacheBudget = RenderCache.DEFAULT_BUDGET;
    public long frameBudgetNanos = FrameApplier.DEFAULT_BUDGET_NANOS;
    /**
     * 同时派发到后台队列的绘制任务数（在途上限）。后台线程画完一个直接取下一个，不等主线程；
     * 派发后再提升优先级的任务最多排在这么多个之后，所以不宜过大（§8.2）
     */
    public int maxRunning = DEFAULT_MAX_RUNNING;
    public static final int DEFAULT_MAX_RUNNING = 8;
    /** 调试日志出口；默认丢弃 */
    public DiagLog log = msg -> { };
    /** 销毁后等待 running 任务归还的时限（R-DISP-4） */
    public long stuckCheckMillis = 10_000;

    /** 日志出口，Android 实现转 LogUtil.d */
    public interface DiagLog {
        void d(String message);
    }

    public RenderDeps(ImageDecoder decoder, TaskRunner runner, MarkerPainter painter,
                      IconFactory icons, FrameClock clock, int densityUnits) {
        this.decoder = decoder;
        this.runner = runner;
        this.painter = painter;
        this.icons = icons;
        this.clock = clock;
        this.densityUnits = densityUnits;
    }
}
