package com.amap.flutter.map.overlays.marker.nativemarker;

/** 任务的一条等待登记 (markerId, generation, role)（§8.2）；按对象身份增删 */
final class Waiter {
    final String markerId;
    final int generation;
    final boolean selected;
    final RenderTask task;

    Waiter(String markerId, int generation, boolean selected, RenderTask task) {
        this.markerId = markerId;
        this.generation = generation;
        this.selected = selected;
        this.task = task;
    }
}
