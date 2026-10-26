package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.view.Choreographer;

import com.amap.flutter.map.overlays.marker.nativemarker.FrameClock;

import java.util.HashMap;
import java.util.Map;

/** Choreographer 帧回调；必须在主线程创建与使用 */
public final class AndroidFrameClock implements FrameClock {
    private final Choreographer choreographer = Choreographer.getInstance();
    private final Map<Runnable, Choreographer.FrameCallback> callbacks = new HashMap<>();

    @Override
    public void postFrame(final Runnable r) {
        Choreographer.FrameCallback cb = new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long frameTimeNanos) {
                callbacks.remove(r);
                r.run();
            }
        };
        callbacks.put(r, cb);
        choreographer.postFrameCallback(cb);
    }

    @Override
    public void removeFrame(Runnable r) {
        Choreographer.FrameCallback cb = callbacks.remove(r);
        if (cb != null) {
            choreographer.removeFrameCallback(cb);
        }
    }

    @Override
    public long nanoTime() {
        return System.nanoTime();
    }
}
