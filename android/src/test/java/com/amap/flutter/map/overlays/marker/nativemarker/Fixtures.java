package com.amap.flutter.map.overlays.marker.nativemarker;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** 读取仓库根目录的共享夹具 test/fixtures/native_marker_layout.json */
final class Fixtures {
    private static Map<String, Object> cached;

    private Fixtures() {
    }

    @SuppressWarnings("unchecked")
    static synchronized Map<String, Object> layout() {
        if (cached == null) {
            try {
                byte[] raw = Files.readAllBytes(locate().toPath());
                cached = (Map<String, Object>) MiniJson.parse(new String(raw, StandardCharsets.UTF_8));
            } catch (IOException e) {
                throw new IllegalStateException(e);
            }
        }
        return cached;
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> section(String name) {
        return (Map<String, Object>) layout().get(name);
    }

    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> cases(String section) {
        return (List<Map<String, Object>>) section(section).get("cases");
    }

    static double num(Object o) {
        return ((Number) o).doubleValue();
    }

    /** Gradle 的测试工作目录是插件 android/，向上逐级查找夹具 */
    private static File locate() {
        File dir = new File("").getAbsoluteFile();
        for (int k = 0; k < 5 && dir != null; k++) {
            File f = new File(dir, "test/fixtures/native_marker_layout.json");
            if (f.isFile()) {
                return f;
            }
            dir = dir.getParentFile();
        }
        throw new IllegalStateException("找不到共享夹具 native_marker_layout.json");
    }

    /** 夹具约定的确定性测量器：宽 = UTF-16 长度 × 字号 × widthFactor */
    static TextMeasurer measurer() {
        Map<String, Object> m = section("measurer");
        double wf = num(m.get("widthFactor"));
        double hf = num(m.get("lineHeightFactor"));
        return new TextMeasurer() {
            @Override
            public double width(String text, double fontSize, int fontWeight) {
                return text.length() * fontSize * wf;
            }

            @Override
            public double lineHeight(double fontSize, int fontWeight) {
                return fontSize * hf;
            }
        };
    }

    /** 可控的资源解析替身：failed 集合内为 fallback，其余按 ready */
    static final class FakeResolver implements ImageResolver {
        final Set<String> failed = new HashSet<>();
        final Map<String, double[]> sizes = new HashMap<>();

        @Override
        public boolean usable(String imageId) {
            return !failed.contains(imageId);
        }

        @Override
        public double[] logicalSize(String imageId) {
            return sizes.get(imageId);
        }
    }
}
