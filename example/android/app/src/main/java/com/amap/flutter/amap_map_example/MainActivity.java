package com.amap.flutter.amap_map_example;

import android.content.Context;
import android.os.Build;
import android.os.PowerManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        // 对照测试用：发热状态 0～6（PowerManager.THERMAL_STATUS_*），API 29 以下返回 null
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "amap_example/thermal")
                .setMethodCallHandler((call, result) -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(null);
                        return;
                    }
                    PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
                    result.success(pm.getCurrentThermalStatus());
                });
    }
}
