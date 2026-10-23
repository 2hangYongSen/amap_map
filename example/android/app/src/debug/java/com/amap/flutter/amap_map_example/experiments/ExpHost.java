package com.amap.flutter.amap_map_example.experiments;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Point;
import android.graphics.SurfaceTexture;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Choreographer;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;

import com.amap.api.maps.AMap;
import com.amap.api.maps.AMapOptions;
import com.amap.api.maps.MapsInitializer;
import com.amap.api.maps.TextureMapView;
import com.amap.api.maps.model.CameraPosition;
import com.amap.api.maps.model.LatLng;

import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;

/**
 * S6 SDK 实验宿主（仅 debug 包）。按 intent 参数 exp 选择实验，结果写 logcat（tag S6EXP）
 * 和 files/s6/&lt;exp&gt;.log。不属于插件代码。
 */
public class ExpHost extends Activity {
    static final String TAG = "S6EXP";
    static final LatLng CENTER = new LatLng(39.917998, 116.397164);
    // 与 example/lib/const_config.dart 相同的示例 key
    private static final String KEY = "900f72eeee0f21e435cebb0ef155582a";

    final Handler main = new Handler(Looper.getMainLooper());
    TextureMapView mapView;
    AMap amap;
    String expId;
    long frameNo;          // 主线程 vsync 计数
    long texUpdates;       // TextureView 收到 GL 新帧的次数
    private TextView status;
    private PrintWriter out;
    private Experiment exp;
    private TextureView textureView;
    private boolean started;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        expId = getIntent().getStringExtra("exp");
        if (expId == null) expId = "A1";
        MapsInitializer.updatePrivacyShow(this, true, true);
        MapsInitializer.updatePrivacyAgree(this, true);
        MapsInitializer.setApiKey(KEY);
        float zoom = getIntent().getFloatExtra("zoom", 16f);
        mapView = new TextureMapView(this, new AMapOptions()
                .camera(new CameraPosition(CENTER, zoom, 0, 0))
                .zoomControlsEnabled(false));
        mapView.onCreate(savedInstanceState);
        amap = mapView.getMap();
        FrameLayout root = new FrameLayout(this);
        root.addView(mapView);
        status = new TextView(this);
        status.setBackgroundColor(0xAAFFFFFF);
        status.setTextColor(Color.BLACK);
        status.setTextSize(11);
        root.addView(status, new FrameLayout.LayoutParams(-1, -2));
        setContentView(root);
        openLog();
        exp = Experiment.create(expId, getIntent());
        exp.h = this;
        tickFrames();
        amap.setOnMapLoadedListener(() -> startOnce("mapLoaded"));
        // 底图网络异常时 OnMapLoaded 可能不来，兜底
        main.postDelayed(() -> startOnce("loadTimeout"), 8000);
    }

    private void startOnce(String why) {
        if (started) return;
        started = true;
        hookTexture();
        log("start exp=" + expId + " by=" + why + " sdk=" + MapsInitializer.getVersion()
                + " api=" + android.os.Build.VERSION.SDK_INT
                + " model=" + android.os.Build.MODEL + " density=" + density());
        after(800, exp::start);
    }

    private void tickFrames() {
        Choreographer.getInstance().postFrameCallback(t -> {
            frameNo++;
            tickFrames();
        });
    }

    /** 包一层 SurfaceTextureListener，统计 GL 线程真正产出的帧（候选 2 的“完成一次绘制”信号）。 */
    private void hookTexture() {
        textureView = findTexture(mapView);
        if (textureView == null) {
            log("WARN no TextureView");
            return;
        }
        final TextureView.SurfaceTextureListener inner = textureView.getSurfaceTextureListener();
        textureView.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            public void onSurfaceTextureAvailable(SurfaceTexture s, int w, int h) {
                log("surfaceTextureAvailable");
                if (inner != null) inner.onSurfaceTextureAvailable(s, w, h);
            }

            public void onSurfaceTextureSizeChanged(SurfaceTexture s, int w, int h) {
                if (inner != null) inner.onSurfaceTextureSizeChanged(s, w, h);
            }

            public boolean onSurfaceTextureDestroyed(SurfaceTexture s) {
                log("surfaceTextureDestroyed"); // 证明前后台切换确实销毁了 GL 表面
                return inner == null || inner.onSurfaceTextureDestroyed(s);
            }

            public void onSurfaceTextureUpdated(SurfaceTexture s) {
                texUpdates++;
                if (inner != null) inner.onSurfaceTextureUpdated(s);
            }
        });
    }

    private static TextureView findTexture(View v) {
        if (v instanceof TextureView) return (TextureView) v;
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) {
                TextureView t = findTexture(g.getChildAt(i));
                if (t != null) return t;
            }
        }
        return null;
    }

    // ---- 供实验使用的工具 ----

    float density() {
        return getResources().getDisplayMetrics().density;
    }

    /** 当前 GL 画面（设备侧截图，等价于屏幕上看到的地图与点位）。 */
    Bitmap frame() {
        return textureView == null ? null : textureView.getBitmap();
    }

    /** 缩小 1/scale 的画面，逐帧采样时用，减少主线程开销。 */
    Bitmap frame(int scale) {
        if (textureView == null) return null;
        return textureView.getBitmap(textureView.getWidth() / scale, textureView.getHeight() / scale);
    }

    Point toScreen(LatLng ll) {
        return amap.getProjection().toScreenLocation(ll);
    }

    LatLng fromScreen(int x, int y) {
        return amap.getProjection().fromScreenLocation(new Point(x, y));
    }

    /** 地图坐标转成 adb input tap 用的屏幕坐标。 */
    Point toDisplay(LatLng ll) {
        int[] loc = new int[2];
        mapView.getLocationOnScreen(loc);
        Point p = toScreen(ll);
        return new Point(p.x + loc[0], p.y + loc[1]);
    }

    void after(long ms, Runnable r) {
        main.postDelayed(() -> {
            try {
                r.run();
            } catch (Throwable e) {
                log("EXC " + Log.getStackTraceString(e).replace('\n', '|'));
            }
        }, ms);
    }

    void log(String msg) {
        Log.i(TAG, expId + " " + msg);
        if (out != null) {
            out.println(System.currentTimeMillis() + " " + msg);
            out.flush();
        }
        String old = status.getText().toString();
        String text = msg + "\n" + old;
        status.setText(text.length() > 600 ? text.substring(0, 600) : text);
    }

    File outDir() {
        File d = new File(getExternalFilesDir(null), "s6");
        d.mkdirs();
        return d;
    }

    void savePng(Bitmap b, String name) {
        if (b == null) return;
        try (FileOutputStream fo = new FileOutputStream(new File(outDir(), name))) {
            b.compress(Bitmap.CompressFormat.PNG, 100, fo);
        } catch (Exception e) {
            log("EXC savePng " + e);
        }
    }

    private void openLog() {
        try {
            out = new PrintWriter(new FileOutputStream(new File(outDir(), expId + ".log"), false));
        } catch (Exception e) {
            Log.e(TAG, "openLog", e);
        }
    }

    // ---- 生命周期转给地图和实验 ----

    /** 主机脚本用 am start --es step xxx 推进多阶段实验（Activity 为 singleTop）。 */
    @Override
    protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        String step = intent.getStringExtra("step");
        if ("detach".equals(step) && started) {
            // 摘下再挂回 MapView：TextureView 离开窗口会销毁 SurfaceTexture，强制 GL 表面重建
            ViewGroup root = (ViewGroup) mapView.getParent();
            root.removeView(mapView);
            log("detached");
            after(800, () -> {
                root.addView(mapView, 0);
                log("reattached");
                after(1500, exp::onResumed);
            });
            return;
        }
        if (step != null && started) {
            log("STEP " + step);
            after(0, () -> exp.onStep(step));
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        mapView.onResume();
        if (started) {
            log("onResume");
            exp.onResumed();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        mapView.onPause();
        if (started) log("onPause");
    }

    @Override
    public void onLowMemory() {
        super.onLowMemory();
        mapView.onLowMemory();
        log("onLowMemory");
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        mapView.onLowMemory();
        log("onTrimMemory level=" + level);
        exp.onTrim();
    }

    @Override
    protected void onDestroy() {
        log("onDestroy begin");
        exp.beforeMapDestroy();
        mapView.onDestroy();
        log("mapView.onDestroy done");
        exp.afterMapDestroy();
        super.onDestroy();
    }
}
