package com.amap.flutter.amap_map_example.experiments;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Point;
import android.view.Choreographer;

import java.util.Arrays;
import java.util.List;

/** 实验基类：生命周期钩子 + 取色、等待绘制等工具。 */
abstract class Experiment {
    ExpHost h;

    static Experiment create(String id, Intent i) {
        switch (id) {
            case "A1": return new ExpA1(i);
            case "A2": return new ExpA2();
            case "A3": return new ExpA3();
            case "A4": return new ExpA4();
            case "A5": return new ExpA5();
            case "A6": return new ExpA6(i);
            case "X1": return new ExpX1();
            default: throw new IllegalArgumentException("unknown exp " + id);
        }
    }

    abstract void start();

    void onResumed() {}

    void onStep(String step) {}

    void onTrim() {}

    void beforeMapDestroy() {}

    void afterMapDestroy() {}

    /** 实心圆点图标，边长 sizePx，四角透明。纯色便于在截图里取色。 */
    static Bitmap dot(int color, int sizePx) {
        Bitmap b = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(color);
        new Canvas(b).drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f - 1, p);
        return b;
    }

    /**
     * 等地图真正画出新帧：至少 minFrames 个 vsync，且 TextureView 至少收到 minTex 次更新；
     * 超时 timeoutMs 后照常回调（并在 timedOut 里标记）。
     */
    void waitDraw(int minFrames, int minTex, long timeoutMs, Runnable next) {
        final long f0 = h.frameNo, t0 = h.texUpdates, s0 = System.nanoTime();
        h.amap.runOnDrawFrame();
        Choreographer.getInstance().postFrameCallback(new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long ft) {
                boolean ok = h.frameNo - f0 >= minFrames && h.texUpdates - t0 >= minTex;
                boolean late = (System.nanoTime() - s0) / 1e6 > timeoutMs;
                if (ok || late) {
                    lastWaitTimedOut = !ok;
                    h.after(0, next);
                } else {
                    h.amap.runOnDrawFrame();
                    Choreographer.getInstance().postFrameCallback(this);
                }
            }
        });
    }

    boolean lastWaitTimedOut;

    /** 取点 p 周围 3x3 中最接近 target 的颜色距离（容忍抗锯齿与缩放）。 */
    static int colorDist(Bitmap f, Point p, int target) {
        int best = Integer.MAX_VALUE;
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
                int x = p.x + dx, y = p.y + dy;
                if (x < 0 || y < 0 || x >= f.getWidth() || y >= f.getHeight()) continue;
                int c = f.getPixel(x, y);
                int d = Math.abs(Color.red(c) - Color.red(target))
                        + Math.abs(Color.green(c) - Color.green(target))
                        + Math.abs(Color.blue(c) - Color.blue(target));
                best = Math.min(best, d);
            }
        }
        return best;
    }

    static boolean isColor(Bitmap f, Point p, int target) {
        return colorDist(f, p, target) <= 60;
    }

    static String hex(int c) {
        return String.format("#%08X", c);
    }

    /** 返回 [n, p50, p95, max, mean]，单位与输入一致。 */
    static double[] stats(List<Double> v) {
        if (v.isEmpty()) return new double[]{0, 0, 0, 0, 0};
        double[] a = new double[v.size()];
        double sum = 0;
        for (int i = 0; i < a.length; i++) {
            a[i] = v.get(i);
            sum += a[i];
        }
        Arrays.sort(a);
        return new double[]{a.length, a[(int) (a.length * 0.5)],
                a[Math.min(a.length - 1, (int) Math.ceil(a.length * 0.95) - 1)],
                a[a.length - 1], sum / a.length};
    }

    static String fmt(double[] s) {
        return String.format("n=%d p50=%.3f p95=%.3f max=%.3f mean=%.3f",
                (int) s[0], s[1], s[2], s[3], s[4]);
    }

    void result(String key, String value) {
        h.log("RESULT " + key + " " + value);
    }

    void done() {
        h.log("DONE");
    }
}
