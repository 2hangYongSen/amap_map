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
    /** 后台同时执行的绘制任务数；生产为 1（单线程执行器），测试可调大验证计数 */
    public int maxRunning = 1;

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
