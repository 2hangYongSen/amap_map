package com.amap.flutter.map.overlays.marker.nativemarker;

import java.util.HashMap;
import java.util.Map;

/**
 * 原生单选状态（§11）：每张地图一份，主线程访问。
 * 只做状态与规则判断，外观由调用方按返回的变化重新调度。
 */
public final class SelectionState {
    public static final String MARKER_TAP = "markerTap";
    public static final String RETAP = "retap";
    public static final String MAP_TAP = "mapTap";
    public static final String API = "api";
    public static final String INVALIDATED = "invalidated";

    /** 一次选择变化（marker#selectionChanged 的业务字段） */
    public static final class Change {
        public final String selectedId;
        public final String previousId;
        public final String reason;
        public final int revision;

        Change(String selectedId, String previousId, String reason, int revision) {
            this.selectedId = selectedId;
            this.previousId = previousId;
            this.reason = reason;
            this.revision = revision;
        }

        Map<String, Object> toMap() {
            Map<String, Object> m = new HashMap<>();
            m.put("selectedId", selectedId);
            m.put("previousId", previousId);
            m.put("reason", reason);
            m.put("revision", revision);
            return m;
        }
    }

    private String selectedId;
    private int revision = 0;
    /** markerSelection 非空才启用自动选择（点击、地图单击） */
    private boolean autoEnabled = false;
    private boolean deselectOnMapTap = true;
    private boolean deselectOnRetap = true;

    public String selectedId() {
        return selectedId;
    }

    public int revision() {
        return revision;
    }

    public boolean autoEnabled() {
        return autoEnabled;
    }

    /** map#update.options.markerSelection：null 关闭自动选择，已有选择保留 */
    void configure(Object raw) {
        autoEnabled = raw instanceof Map;
        if (autoEnabled) {
            Map<?, ?> m = (Map<?, ?>) raw;
            deselectOnMapTap = !Boolean.FALSE.equals(m.get("deselectOnMapTap"));
            deselectOnRetap = !Boolean.FALSE.equals(m.get("deselectOnRetap"));
        }
    }

    /** R-SEL-1/4：id 相同返回 null（revision 不变、不发事件） */
    Change set(String id, String reason) {
        if (id == null ? selectedId == null : id.equals(selectedId)) {
            return null;
        }
        String prev = selectedId;
        selectedId = id;
        revision++;
        return new Change(id, prev, reason, revision);
    }

    /** R-SEL-2 点位点击；非 selectable 点不改变选择 */
    Change onMarkerTap(String id, boolean selectable) {
        if (!autoEnabled || !selectable) {
            return null;
        }
        if (!id.equals(selectedId)) {
            return set(id, MARKER_TAP);
        }
        return deselectOnRetap ? set(null, RETAP) : null;
    }

    /** R-SEL-2 地图空白处单击 */
    Change onMapTap() {
        return autoEnabled && deselectOnMapTap ? set(null, MAP_TAP) : null;
    }

    /** markers#attach 快照 */
    Map<String, Object> snapshot() {
        Map<String, Object> m = new HashMap<>();
        m.put("selectedId", selectedId);
        m.put("revision", revision);
        return m;
    }
}
