package com.amap.flutter.map.overlays.marker.nativemarker;

/** 注册表中的一个资源条目（§7.1）。只在主线程读写 */
public final class ImageEntry {
    public enum State { PENDING, READY, FAILED }

    /** 引用来源（R-RES-1 中 Android 资源条目持有的三类） */
    public enum Ref { DESIRED, QUEUED, RUNNING }

    public final String id;
    public final ImageSource source;
    State state = State.PENDING;
    /** release 或 resync 不在集合内后置位；再次 imagesToAdd 时清除 */
    boolean releasing = false;
    /** 每次发起解码换新值，迟到的过期结果按 epoch 丢弃（R-RES-12） */
    int epoch;
    /** 是否有解码正在进行 */
    boolean decoding = false;
    DecodedImage decoded;
    /** 首次解码得到的像素尺寸；驱逐后仍保留，布局不受影响 */
    int pixelWidth = -1;
    int pixelHeight = -1;
    String failCode;
    String failMessage;
    long lastUsed;
    final int[] refs = new int[Ref.values().length];

    ImageEntry(String id, ImageSource source) {
        this.id = id;
        this.source = source;
    }

    public State state() {
        return state;
    }

    public boolean isReleasing() {
        return releasing;
    }

    public int epoch() {
        return epoch;
    }

    public int refs(Ref kind) {
        return refs[kind.ordinal()];
    }

    public int totalRefs() {
        int n = 0;
        for (int r : refs) {
            n += r;
        }
        return n;
    }

    /** 排队或执行中任务需要它（淘汰时必须跳过） */
    public boolean neededByTask() {
        return refs(Ref.QUEUED) > 0 || refs(Ref.RUNNING) > 0;
    }

    public DecodedImage decoded() {
        return decoded;
    }

    /** ready 但解码结果已被预算淘汰（ready(evicted)） */
    public boolean isEvicted() {
        return state == State.READY && decoded == null;
    }
}
