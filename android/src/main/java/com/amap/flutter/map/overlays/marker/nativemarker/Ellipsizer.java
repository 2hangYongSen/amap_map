package com.amap.flutter.map.overlays.marker.nativemarker;

import java.text.BreakIterator;
import java.util.ArrayList;
import java.util.List;

/**
 * 尾部省略（R-ELL-1）：宽度 ≤ avail 时完整显示（等于不省略）；
 * 超出时取能放下的最长前缀加“…”，以字形簇为单位截断；avail ≤ 0 或放不下“…”时不显示文字。
 */
public final class Ellipsizer {
    public static final String ELLIPSIS = "\u2026";

    private Ellipsizer() {
    }

    public static String ellipsize(String text, double avail, TextMeasurer m,
                                   double fontSize, int fontWeight) {
        if (text == null || text.isEmpty() || avail <= 0) {
            return "";
        }
        if (m.width(text, fontSize, fontWeight) <= avail) {
            return text;
        }
        // 从长到短尝试每个字形簇边界，保证不拆开代理对和组合字符
        List<Integer> bounds = graphemeBounds(text);
        for (int i = bounds.size() - 1; i >= 0; i--) {
            String candidate = text.substring(0, bounds.get(i)) + ELLIPSIS;
            if (m.width(candidate, fontSize, fontWeight) <= avail) {
                return candidate;
            }
        }
        return "";
    }

    /** 字形簇的结束位置（不含 0 和整串长度：整串已判断过放不下） */
    static List<Integer> graphemeBounds(String text) {
        List<Integer> out = new ArrayList<>();
        BreakIterator it = BreakIterator.getCharacterInstance();
        it.setText(text);
        for (int end = it.next(); end != BreakIterator.DONE; end = it.next()) {
            if (end < text.length()) {
                out.add(end);
            }
        }
        return out;
    }
}
