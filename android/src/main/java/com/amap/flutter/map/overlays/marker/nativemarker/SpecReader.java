package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.List;
import java.util.Map;

/**
 * 从通道载荷（Map/List/Number）读取并规范化字段；类型不符一律抛 InvalidMarkerException。
 * 字段路径写进异常信息，便于 marker#nativeError 定位。
 */
final class SpecReader {
    private SpecReader() {
    }

    static Map<?, ?> map(Map<?, ?> m, String key, boolean required) throws InvalidMarkerException {
        Object v = m.get(key);
        if (v == null && !required) {
            return null;
        }
        if (!(v instanceof Map)) {
            throw new InvalidMarkerException(key + " 必须是对象");
        }
        return (Map<?, ?>) v;
    }

    static double number(Object v, String path) throws InvalidMarkerException {
        if (!(v instanceof Number)) {
            throw new InvalidMarkerException(path + " 必须是数值");
        }
        return ((Number) v).doubleValue();
    }

    /** 必填长度 → 1/64 单位 */
    static int length(Map<?, ?> m, String key) throws InvalidMarkerException {
        return Norm.lengthUnits(number(m.get(key), key));
    }

    /** 可空长度：null 原样返回 */
    static Integer optLength(Map<?, ?> m, String key) throws InvalidMarkerException {
        Object v = m.get(key);
        return v == null ? null : Norm.lengthUnits(number(v, key));
    }

    /** 缺省时取默认值的长度 */
    static int lengthOr(Map<?, ?> m, String key, double def) throws InvalidMarkerException {
        Object v = m.get(key);
        return Norm.lengthUnits(v == null ? def : number(v, key));
    }

    /** 定长数值列表（size/offset/insets）→ 长度单位；null 返回 null */
    static int[] optLengths(Map<?, ?> m, String key, int n) throws InvalidMarkerException {
        Object v = m.get(key);
        if (v == null) {
            return null;
        }
        if (!(v instanceof List) || ((List<?>) v).size() != n) {
            throw new InvalidMarkerException(key + " 必须是长度为 " + n + " 的数组");
        }
        int[] out = new int[n];
        for (int i = 0; i < n; i++) {
            out[i] = Norm.lengthUnits(number(((List<?>) v).get(i), key));
        }
        return out;
    }

    /** ARGB 颜色：Dart 侧可能以 Long 传来（高位为 1 时），截成 32 位 */
    static Integer optColor(Map<?, ?> m, String key) throws InvalidMarkerException {
        Object v = m.get(key);
        if (v == null) {
            return null;
        }
        if (!(v instanceof Integer) && !(v instanceof Long)) {
            throw new InvalidMarkerException(key + " 必须是 ARGB 整数");
        }
        return (int) ((Number) v).longValue();
    }

    static int color(Map<?, ?> m, String key) throws InvalidMarkerException {
        Integer c = optColor(m, key);
        if (c == null) {
            throw new InvalidMarkerException(key + " 不能为空");
        }
        return c;
    }

    static String optString(Map<?, ?> m, String key) throws InvalidMarkerException {
        Object v = m.get(key);
        if (v != null && !(v instanceof String)) {
            throw new InvalidMarkerException(key + " 必须是字符串");
        }
        return (String) v;
    }

    static void require(boolean ok, String message) throws InvalidMarkerException {
        if (!ok) {
            throw new InvalidMarkerException(message);
        }
    }
}
