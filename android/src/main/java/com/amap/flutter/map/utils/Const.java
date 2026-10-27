package com.amap.flutter.map.utils;

/**
 * @author kuloud
 * @author whm
 * @date 2020/11/10 9:44 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
public class Const {
    /**
     * map
     */
    public static final String METHOD_MAP_WAIT_FOR_MAP = "map#waitForMap";
    public static final String METHOD_MAP_CONTENT_APPROVAL_NUMBER = "map#contentApprovalNumber";
    public static final String METHOD_MAP_SATELLITE_IMAGE_APPROVAL_NUMBER = "map#satelliteImageApprovalNumber";
    public static final String METHOD_MAP_UPDATE = "map#update";
    public static final String METHOD_MAP_MOVE_CAMERA = "camera#move";
    public static final String METHOD_MAP_SET_RENDER_FPS = "map#setRenderFps";
    public static final String METHOD_MAP_TAKE_SNAPSHOT = "map#takeSnapshot";
    public static final String METHOD_MAP_CLEAR_DISK = "map#clearDisk";
    public static final String METHOD_MAP_TO_SCREEN_COORDINATE = "map#toScreenCoordinate";
    public static final String METHOD_MAP_FROM_SCREEN_COORDINATE = "map#fromScreenCoordinate";

    public static final String METHOD_SET_TERRAIN_ENABLE = "#setTerrainEnable";

    public static final String[] METHOD_ID_LIST_FOR_MAP = {
            METHOD_MAP_CONTENT_APPROVAL_NUMBER,
            METHOD_MAP_SATELLITE_IMAGE_APPROVAL_NUMBER,
            METHOD_MAP_WAIT_FOR_MAP,
            METHOD_MAP_UPDATE,
            METHOD_MAP_MOVE_CAMERA,
            METHOD_MAP_SET_RENDER_FPS,
            METHOD_MAP_TAKE_SNAPSHOT,
            METHOD_MAP_CLEAR_DISK,
            METHOD_MAP_TO_SCREEN_COORDINATE,
            METHOD_MAP_FROM_SCREEN_COORDINATE
    };


    /**
     * markers
     */
    public static final String METHOD_MARKER_UPDATE = "markers#update";
    /** 新协议握手（§6.8） */
    public static final String METHOD_MARKER_ATTACH = "markers#attach";
    /** 新协议全量恢复（R-RES-9） */
    public static final String METHOD_MARKER_RESYNC = "markers#resync";
    /** 原生单选（§11） */
    public static final String METHOD_MARKER_SET_SELECTED = "markers#setSelected";
    /** 诊断（§13），只在 markerDiagnostics 开启时可用 */
    public static final String METHOD_DIAG_PING = "diag#ping";
    public static final String METHOD_DIAG_CLEAR_CACHES = "diag#clearCaches";
    public static final String[] METHOD_ID_LIST_FOR_MARKER = {
            METHOD_MARKER_UPDATE,
            METHOD_MARKER_ATTACH,
            METHOD_MARKER_RESYNC,
            METHOD_MARKER_SET_SELECTED,
            METHOD_DIAG_PING,
            METHOD_DIAG_CLEAR_CACHES
    };

    /**
     * polygons
     */
    public static final String METHOD_POLYGON_UPDATE = "polygons#update";
    public static final String[] METHOD_ID_LIST_FOR_POLYGON = {METHOD_POLYGON_UPDATE};

    /**
     * polylines
     */
    public static final String METHOD_POLYLINE_UPDATE = "polylines#update";
    public static final String[] METHOD_ID_LIST_FOR_POLYLINE = {METHOD_POLYLINE_UPDATE};
}
