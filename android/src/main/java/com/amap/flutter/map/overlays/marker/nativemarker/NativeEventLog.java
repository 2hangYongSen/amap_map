package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 新协议事件出口：分配 eventSeq、握手前不发送、保留最近 64 条错误（R-INIT-2/4/5）。
 * 主线程访问。
 */
public final class NativeEventLog {
    public static final int MAX_ERRORS = 64;

    private final MarkerEventSink sink;
    private final ArrayDeque<Map<String, Object>> errors = new ArrayDeque<>();
    private int errorsDropped = 0;
    private int eventSeq = 0;
    private boolean open = false;
    private boolean closed = false;

    public NativeEventLog(MarkerEventSink sink) {
        this.sink = sink;
    }

    /** 握手：打开事件开关（与生成快照在同一次主线程调用内） */
    public void open() {
        if (!closed) {
            open = true;
        }
    }

    /** 销毁后不再发送任何事件 */
    public void close() {
        closed = true;
        open = false;
        errors.clear();
    }

    public int lastEventSeq() {
        return eventSeq;
    }

    /**
     * 状态类事件（如 marker#imagesResult）：握手前也分配序号，但只记录在注册表里、不发送
     * （R-INIT-2），状态由 attach 快照交付。
     */
    public void event(String method, Map<String, Object> args) {
        if (closed) {
            return;
        }
        args.put("eventSeq", ++eventSeq);
        if (open) {
            sink.emit(method, args);
        }
    }

    /** 记录 marker#nativeError；握手前只缓冲，握手后同时实时发送 */
    public void error(String code, String markerId, String imageId, String message) {
        if (closed) {
            return;
        }
        Map<String, Object> e = new HashMap<>();
        e.put("eventSeq", ++eventSeq);
        e.put("code", code);
        e.put("markerId", markerId);
        e.put("imageId", imageId);
        e.put("message", message);
        errors.addLast(e);
        if (errors.size() > MAX_ERRORS) {
            errors.removeFirst();
            errorsDropped++;
        }
        if (open) {
            sink.emit("marker#nativeError", e);
        }
    }

    /** 握手返回值中的历史错误（Dart 按 eventSeq 去重） */
    public List<Map<String, Object>> errorsSnapshot() {
        return new ArrayList<>(errors);
    }

    public int errorsDropped() {
        return errorsDropped;
    }
}
