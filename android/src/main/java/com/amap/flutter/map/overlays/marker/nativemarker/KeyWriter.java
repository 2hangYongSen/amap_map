package com.amap.flutter.map.overlays.marker.nativemarker;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * 渲染 key 的规范化写入器（R-KEY-1/3）：只接受整数、布尔和字符串，
 * 每个字段带类型前缀与分隔符，字符串带长度前缀，避免拼接歧义。
 */
final class KeyWriter {
    private final StringBuilder b = new StringBuilder(256);

    KeyWriter i(int v) {
        b.append('i').append(v).append(',');
        return this;
    }

    /** 可空整数：null 与任何数值都不同 */
    KeyWriter n(Integer v) {
        if (v == null) {
            b.append("~,");
        } else {
            i(v);
        }
        return this;
    }

    KeyWriter b(boolean v) {
        b.append(v ? "T," : "F,");
        return this;
    }

    KeyWriter s(String v) {
        if (v == null) {
            b.append("~,");
        } else {
            b.append('s').append(v.length()).append(':').append(v).append(',');
        }
        return this;
    }

    KeyWriter a(int[] vs) {
        if (vs == null) {
            b.append("~,");
            return this;
        }
        b.append('[');
        for (int v : vs) {
            b.append(v).append(' ');
        }
        b.append("],");
        return this;
    }

    /** 分段标记，便于调试时阅读 */
    KeyWriter tag(String t) {
        b.append('|').append(t).append('|');
        return this;
    }

    /** 未哈希的规范串（测试用于断言） */
    String raw() {
        return b.toString();
    }

    /** SHA-256 前 32 个十六进制字符 */
    String hash() {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256")
                    .digest(b.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(32);
            for (int k = 0; k < 16; k++) {
                hex.append(Character.forDigit((d[k] >> 4) & 0xF, 16))
                        .append(Character.forDigit(d[k] & 0xF, 16));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            // 所有 JVM/Android 都必须提供 SHA-256
            throw new IllegalStateException(e);
        }
    }
}
