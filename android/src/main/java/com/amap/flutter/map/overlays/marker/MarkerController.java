package com.amap.flutter.map.overlays.marker;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.flutter.map.overlays.marker.nativemarker.FullMarkerOptions;

/**
 * @author whm
 * @date 2020/11/6 6:18 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
class MarkerController implements MarkerOptionsSink {
    private final Marker marker;
    private final String markerId;

    MarkerController(Marker marker) {
        this.marker = marker;
        markerId = marker.getId();
    }

    public String getMarkerId() {
        return markerId;
    }

    public void remove() {
        if (null != marker) {
            marker.remove();
        }
    }

    public LatLng getPosition() {
        if (null != marker) {
            return marker.getPosition();
        }
        return null;
    }

    @Override
    public void setPosition(LatLng position) {
        marker.setPosition(position);
    }

    @Override
    public void setAlpha(float alpha) {
        marker.setAlpha(alpha);
    }

    @Override
    public void setAnchor(float u, float v) {
        marker.setAnchor(u, v);
    }

    @Override
    public void setDraggable(boolean draggable) {
        marker.setDraggable(draggable);
    }

    @Override
    public void setFlat(boolean flat) {
        marker.setFlat(flat);
    }

    @Override
    public void setIcon(BitmapDescriptor bitmapDescriptor) {
        marker.setIcon(bitmapDescriptor);
    }

    @Override
    public void setTitle(String title) {
        marker.setTitle(title);
    }

    @Override
    public void setSnippet(String snippet) {
        marker.setSnippet(snippet);
    }

    @Override
    public void setRotation(float rotation) {
        marker.setRotateAngle(rotation);
    }

    @Override
    public void setVisible(boolean visible) {
        marker.setVisible(visible);
    }

    @Override
    public void setZIndex(float zIndex) {
        marker.setZIndex(zIndex);
    }

    @Override
    public void setInfoWindowEnable(boolean enable) {
        marker.setInfoWindowEnable(enable);
    }

    @Override
    public void setClickable(boolean clickable) {
        marker.setClickable(clickable);
    }

    /**
     * 新协议完整替换（R-PROTO-2/3）：每个字段都应用，null 已在解析时换成默认值。
     * icon 为 null 表示保留当前图标（icon→native 绘制完成前，R-PROTO-4）。
     */
    void applyFull(FullMarkerOptions o, BitmapDescriptor icon) {
        marker.setPosition(new LatLng(o.latitude, o.longitude));
        marker.setAlpha(o.alpha);
        marker.setAnchor(o.anchorU, o.anchorV);
        marker.setClickable(o.clickable);
        marker.setDraggable(o.draggable);
        marker.setInfoWindowEnable(o.infoWindowEnable);
        marker.setTitle(o.title);
        marker.setSnippet(o.snippet);
        marker.setRotateAngle(o.rotation);
        marker.setVisible(o.visible);
        marker.setZIndex(o.zIndex);
        if (icon != null) {
            marker.setIcon(icon);
        }
    }

    /**
     * native 点位：属性按完整替换应用，锚点不读 options（来自合成画布）。
     * icon 为 null 时只改属性、保留当前图标与锚点（R-GEN-5）。
     */
    void applyNative(FullMarkerOptions o, BitmapDescriptor icon, float u, float v) {
        float oldU = marker.getAnchorU();
        float oldV = marker.getAnchorV();
        applyFull(o, icon);
        if (icon != null) {
            marker.setAnchor(u, v);
        } else {
            marker.setAnchor(oldU, oldV);
        }
    }

    public void showInfoWindow() {
        marker.showInfoWindow();
    }

    public void hideInfoWindow() {
        marker.hideInfoWindow();
    }
}
