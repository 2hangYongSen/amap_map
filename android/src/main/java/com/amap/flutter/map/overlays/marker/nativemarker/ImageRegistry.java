package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 资源注册表（§7.1、§7.4）：状态机、epoch、三类引用计数、8MiB 解码软预算。
 * 全部公开方法在主线程调用；后台线程只读不可变的 ImageSource。
 */
public final class ImageRegistry implements ImageResolver {
    public static final String ERR_DECODE_FAILED = "imageDecodeFailed";

    /** 状态变化通知（R-RES-7/12）：由管理器转成 imagesResult / nativeError 并重新调度 */
    public interface Listener {
        void onReady(ImageEntry e);

        void onFailed(ImageEntry e);

        /** 被淘汰的解码结果重新解码完成，等待它的任务可以继续（R-RES-11） */
        void onRedecoded(ImageEntry e);
    }

    private final Map<String, ImageEntry> entries = new LinkedHashMap<>();
    private final ImageDecoder decoder;
    private final TaskRunner runner;
    private final long budget;
    private Listener listener;
    /** 全局递增：同一 id 释放后重新登记也不会与旧解码撞 epoch */
    private int nextEpoch = 0;
    private long clock = 0;
    private int decodeCount = 0;
    private boolean disposed = false;
    /** 后台线程读取：销毁后排队中的解码不再执行 */
    private volatile boolean decodeCancelled = false;
    private boolean decodedOverBudget = false;

    public ImageRegistry(ImageDecoder decoder, TaskRunner runner, long budgetBytes) {
        this.decoder = decoder;
        this.runner = runner;
        this.budget = budgetBytes;
    }

    public ImageRegistry(ImageDecoder decoder, TaskRunner runner) {
        this(decoder, runner, DecodeBudget.DEFAULT_BYTES);
    }

    public void setListener(Listener l) {
        this.listener = l;
    }

    /** imagesToAdd：新登记进入 pending；releasing 中再次加入按原状态恢复（§7.1） */
    public void register(ImageSource src) {
        if (disposed) {
            return;
        }
        ImageEntry e = entries.get(src.id);
        if (e == null) {
            e = new ImageEntry(src.id, src);
            entries.put(src.id, e);
            startDecode(e);
            return;
        }
        e.releasing = false;
        // ready 不重新解码；failed 是重试：回到 pending、换 epoch 重新解码
        if (e.state == ImageEntry.State.FAILED) {
            e.state = ImageEntry.State.PENDING;
            e.source = src; // 用最新来源重试
            startDecode(e);
        }
    }

    /** imageIdsToRelease：进入 releasing，是否真正释放由引用计数决定（R-RES-10） */
    public void release(String id) {
        ImageEntry e = entries.get(id);
        if (e != null) {
            e.releasing = true;
            tryFree(e);
        }
    }

    /** resync：不在集合内的资源全部进入 releasing（R-RES-9） */
    public void releaseAllExcept(Set<String> keep) {
        for (ImageEntry e : new ArrayList<>(entries.values())) {
            if (!keep.contains(e.id)) {
                release(e.id);
            }
        }
    }

    /** 取得一个引用；任务引用遇到已淘汰的结果时直接从原始数据重新解码，不找 Dart（R-RES-11） */
    public boolean acquire(String id, ImageEntry.Ref kind) {
        ImageEntry e = entries.get(id);
        if (e == null) {
            return false;
        }
        e.refs[kind.ordinal()]++;
        e.lastUsed = ++clock;
        if (kind != ImageEntry.Ref.DESIRED && e.isEvicted() && !e.decoding) {
            startDecode(e);
        }
        return true;
    }

    /** 归还引用，必须与 acquire 成对；多还视为不变量破坏 */
    public void unref(String id, ImageEntry.Ref kind) {
        ImageEntry e = entries.get(id);
        if (e == null || e.refs[kind.ordinal()] == 0) {
            throw new IllegalStateException("资源引用不成对: " + id + " " + kind);
        }
        e.refs[kind.ordinal()]--;
        if (!tryFree(e)) {
            enforceBudget();
        }
    }

    /** 后台解码；结果按 epoch 校验后在主线程落地 */
    private void startDecode(ImageEntry e) {
        final int epoch = ++nextEpoch;
        e.epoch = epoch;
        e.decoding = true;
        decodeCount++;
        final ImageSource src = e.source;
        boolean accepted = runner.background(() -> {
            DecodedImage img = null;
            Throwable err = null;
            // 销毁后仍在执行器队列里的解码直接跳过（§8.6 第一阶段撤销 queued）
            if (!decodeCancelled) {
                try {
                    img = decoder.decode(src);
                } catch (Exception | Error ex) {
                    err = ex; // OOM 等 Error 也按 imageDecodeFailed 处理，不让后台线程崩溃
                }
            }
            final DecodedImage out = img;
            final Throwable fail = err;
            runner.main(() -> onDecoded(src.id, epoch, out, fail));
        });
        if (!accepted) {
            onDecoded(src.id, epoch, null, new IllegalStateException("后台执行器已关闭"));
        }
    }

    private void onDecoded(String id, int epoch, DecodedImage img, Throwable err) {
        ImageEntry e = entries.get(id);
        // 已释放、已销毁或 epoch 变化（又重试或重新登记）：结果过期，直接丢弃
        if (disposed || e == null || e.epoch != epoch) {
            if (img != null) {
                img.recycle();
            }
            return;
        }
        e.decoding = false;
        boolean wasEvicted = e.state == ImageEntry.State.READY;
        if (err != null || img == null) {
            e.state = ImageEntry.State.FAILED;
            e.failCode = ERR_DECODE_FAILED;
            e.failMessage = err == null ? "解码结果为空" : String.valueOf(err.getMessage());
            if (listener != null) {
                listener.onFailed(e);
            }
            tryFree(e);
            return;
        }
        e.decoded = img;
        e.pixelWidth = img.width();
        e.pixelHeight = img.height();
        e.state = ImageEntry.State.READY;
        e.lastUsed = ++clock;
        if (listener != null) {
            if (wasEvicted) {
                listener.onRedecoded(e);
            } else {
                listener.onReady(e);
            }
        }
        if (!tryFree(e)) {
            enforceBudget();
        }
    }

    /** R-RES-10：releasing 且 refs == 0 才释放；资源 Bitmap 从不交给 SDK，可直接 recycle */
    private boolean tryFree(ImageEntry e) {
        if (!e.releasing || e.totalRefs() > 0) {
            return false;
        }
        entries.remove(e.id);
        if (e.decoded != null) {
            e.decoded.recycle();
            e.decoded = null;
        }
        // 解码中的条目被移除后，迟到结果因 entries 中没有它而被丢弃
        e.epoch = -1;
        return true;
    }

    /** R-RES-11：超预算时按 LRU 淘汰无任务需要的解码结果，状态保持 ready(evicted) */
    private void enforceBudget() {
        for (ImageEntry v : DecodeBudget.victims(entries.values(), budget)) {
            v.decoded.recycle();
            v.decoded = null;
        }
        decodedOverBudget = DecodeBudget.decodedBytes(entries.values()) > budget;
    }

    /** 第一阶段销毁（§8.6）：无引用的立即释放，仍被引用的进入 releasing 等最后一次 unref */
    public void dispose() {
        disposed = true;
        decodeCancelled = true;
        for (ImageEntry e : new ArrayList<>(entries.values())) {
            e.releasing = true;
            tryFree(e);
        }
    }

    // ---------- 查询 ----------

    /** pending 按 ready 解析 key（R-RES-12）；failed 或未登记为 fallback */
    @Override
    public boolean usable(String imageId) {
        ImageEntry e = entries.get(imageId);
        return e != null && e.state != ImageEntry.State.FAILED;
    }

    /** 逻辑尺寸 = 像素 / pixelRatio；首次解码完成前返回 null，淘汰后仍可用 */
    @Override
    public double[] logicalSize(String imageId) {
        ImageEntry e = entries.get(imageId);
        if (e == null || e.pixelWidth < 0) {
            return null;
        }
        return new double[]{e.pixelWidth / e.source.pixelRatio, e.pixelHeight / e.source.pixelRatio};
    }

    public ImageEntry entry(String id) {
        return entries.get(id);
    }

    public Collection<ImageEntry> entries() {
        return entries.values();
    }

    public int size() {
        return entries.size();
    }

    /** 累计发起的解码次数（测试与诊断用） */
    public int decodeCount() {
        return decodeCount;
    }

    public long decodedBytes() {
        return DecodeBudget.decodedBytes(entries.values());
    }

    /** 原始字节单独统计，不计入 8MiB（R-RES-11） */
    public long rawBytes() {
        return DecodeBudget.rawBytes(entries.values());
    }

    public boolean decodedOverBudget() {
        return decodedOverBudget;
    }

    /** markers#attach 返回值中的 images 段（R-INIT-3）；releasing 的不再列出 */
    public Map<String, Object> snapshot() {
        List<String> ready = new ArrayList<>();
        List<Map<String, Object>> failed = new ArrayList<>();
        List<String> pending = new ArrayList<>();
        for (ImageEntry e : entries.values()) {
            if (e.releasing) {
                continue;
            }
            if (e.state == ImageEntry.State.READY) {
                ready.add(e.id);
            } else if (e.state == ImageEntry.State.PENDING) {
                pending.add(e.id);
            } else {
                failed.add(failure(e));
            }
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("ready", ready);
        m.put("failed", failed);
        m.put("pending", pending);
        return m;
    }

    /** 当前 pending 的 id（markers#update 返回值 imagesPending，§6.5） */
    public List<String> pendingIds() {
        List<String> out = new ArrayList<>();
        for (ImageEntry e : entries.values()) {
            if (!e.releasing && e.state == ImageEntry.State.PENDING) {
                out.add(e.id);
            }
        }
        return out;
    }

    /** imagesResult.failed 的单项 {id, code, message} */
    public static Map<String, Object> failure(ImageEntry e) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("id", e.id);
        f.put("code", e.failCode);
        f.put("message", e.failMessage);
        return f;
    }
}
