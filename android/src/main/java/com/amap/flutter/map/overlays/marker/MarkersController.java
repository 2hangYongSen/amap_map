package com.amap.flutter.map.overlays.marker;

import android.content.Context;
import android.text.TextUtils;

import androidx.annotation.NonNull;

import com.amap.api.maps.AMap;
import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;
import com.amap.api.maps.model.Poi;
import com.amap.flutter.map.MyMethodCallHandler;
import com.amap.flutter.map.overlays.AbstractOverlayController;
import com.amap.flutter.map.overlays.marker.nativemarker.FullMarkerOptions;
import com.amap.flutter.map.overlays.marker.nativemarker.MarkerEventSink;
import com.amap.flutter.map.overlays.marker.nativemarker.MarkerHost;
import com.amap.flutter.map.overlays.marker.nativemarker.NativeIcon;
import com.amap.flutter.map.overlays.marker.nativemarker.InvalidMarkerException;
import com.amap.flutter.map.overlays.marker.nativemarker.NativeMarkerManager;
import com.amap.flutter.map.overlays.marker.nativemarker.Norm;
import com.amap.flutter.map.overlays.marker.nativemarker.RenderDeps;
import com.amap.flutter.map.overlays.marker.nativemarker.platform.AndroidFrameClock;
import com.amap.flutter.map.overlays.marker.nativemarker.platform.AndroidIconFactory;
import com.amap.flutter.map.overlays.marker.nativemarker.platform.AndroidImageDecoder;
import com.amap.flutter.map.overlays.marker.nativemarker.platform.AndroidTaskRunner;
import com.amap.flutter.map.overlays.marker.nativemarker.platform.NativeMarkerPainter;
import com.amap.flutter.map.utils.Const;
import com.amap.flutter.map.utils.ConvertUtil;
import com.amap.flutter.map.utils.LogUtil;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.FlutterInjector;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * @author whm
 * @date 2020/11/6 5:38 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
public class MarkersController
        extends AbstractOverlayController<MarkerController>
        implements MyMethodCallHandler,
        AMap.OnMapClickListener,
        AMap.OnMarkerClickListener,
        AMap.OnMarkerDragListener,
        AMap.OnPOIClickListener {
    private static final String CLASS_NAME = "MarkersController";
    private String selectedMarkerDartId;
    /** 新协议状态；旧格式请求不经过它（R-PROTO-3） */
    private final NativeMarkerManager nativeManager;
    private boolean disposed = false;

    /** 协议桩模式（无渲染依赖）：native 点位显示占位图标，仅供测试与兜底 */
    public MarkersController(MethodChannel methodChannel, AMap amap) {
        this(methodChannel, amap, null);
    }

    /** 完整渲染模式：context 用于读取 asset 与屏幕密度 */
    public MarkersController(MethodChannel methodChannel, AMap amap, Context context) {
        super(methodChannel, amap);
        amap.addOnMarkerClickListener(this);
        amap.addOnMarkerDragListener(this);
        amap.addOnMapClickListener(this);
        amap.addOnPOIClickListener(this);
        RenderDeps deps = context == null ? null : renderDeps(context);
        nativeManager = new NativeMarkerManager(new SdkMarkerHost(), new MarkerEventSink() {
            @Override
            public void emit(String method, Map<String, Object> args) {
                if (!disposed) {
                    MarkersController.this.methodChannel.invokeMethod(method, args);
                }
            }
        }, deps);
    }

    /** 装配 Android 平台出口（解码、线程、绘制、SDK 图标、帧回调） */
    private static RenderDeps renderDeps(Context context) {
        int densityUnits;
        try {
            densityUnits = Norm.ratioUnits(context.getResources().getDisplayMetrics().density);
        } catch (InvalidMarkerException e) {
            throw new IllegalStateException(e); // 屏幕密度不可能非有限
        }
        RenderDeps deps = new RenderDeps(
                new AndroidImageDecoder(context.getAssets(),
                        new AndroidImageDecoder.AssetResolver() {
                            @Override
                            public String lookup(String asset, String assetPackage) {
                                return assetPackage == null
                                        ? FlutterInjector.instance().flutterLoader()
                                                .getLookupKeyForAsset(asset)
                                        : FlutterInjector.instance().flutterLoader()
                                                .getLookupKeyForAsset(asset, assetPackage);
                            }
                        }),
                new AndroidTaskRunner(), new NativeMarkerPainter(), new AndroidIconFactory(),
                new AndroidFrameClock(), densityUnits);
        deps.log = new RenderDeps.DiagLog() {
            @Override
            public void d(String message) {
                LogUtil.d(CLASS_NAME, message);
            }
        };
        return deps;
    }

    /** 创建参数为新协议时登记初始点位（R-SYNC-4），由 AMapOptionsBuilder 调用 */
    public void applyCreationParams(Map<?, ?> params) {
        nativeManager.applyCreation(params);
    }

    /**
     * 第一阶段销毁（§8.6）：移除监听与全部 Marker。
     * 必须在 mapView.onDestroy() 之前调用（R-DISP-2）；幂等。
     */
    public void dispose() {
        if (disposed) {
            return;
        }
        disposed = true;
        if (null != amap) {
            amap.removeOnMarkerClickListener(this);
            amap.removeOnMarkerDragListener(this);
            amap.removeOnMapClickListener(this);
            amap.removeOnPOIClickListener(this);
        }
        nativeManager.dispose();
        controllerMapByDartId.clear();
        idMapByOverlyId.clear();
    }

    @Override
    public String[] getRegisterMethodIdArray() {
        return Const.METHOD_ID_LIST_FOR_MARKER;
    }


    @Override
    public void doMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        LogUtil.i(CLASS_NAME, "doMethodCall===>" + call.method);
        switch (call.method) {
            case Const.METHOD_MARKER_UPDATE:
                // 按 protocolVersion 分流：不带即旧格式，行为与 1.0.15 相同
                if (NativeMarkerManager.isV2Payload(call.arguments)) {
                    Map<String, Object> r = nativeManager.update(call.arguments);
                    LogUtil.i(CLASS_NAME, "markers#update v2 result==>" + r);
                    result.success(r);
                } else if (disposed) {
                    result.success(null); // 已销毁：不再触碰地图
                } else {
                    invokeMarkerOptions(call, result);
                }
                break;
            case Const.METHOD_MARKER_ATTACH:
                if (disposed) {
                    result.error("disposed", "map disposed", null);
                } else {
                    Map<String, Object> r = nativeManager.attach();
                    LogUtil.i(CLASS_NAME, "markers#attach result==>" + r);
                    result.success(r);
                }
                break;
            case Const.METHOD_MARKER_RESYNC:
                Map<String, Object> r = nativeManager.resync(call.arguments);
                LogUtil.i(CLASS_NAME, "markers#resync result==>" + r);
                result.success(r);
                break;
            case Const.METHOD_MARKER_SET_SELECTED:
                if (disposed) {
                    result.error("disposed", "map disposed", null);
                } else {
                    result.success(nativeManager.setSelected(call.arguments));
                }
                break;
        }
    }


    /**
     * 执行主动方法更新marker
     *
     * @param methodCall
     * @param result
     */
    public void invokeMarkerOptions(MethodCall methodCall, MethodChannel.Result result) {
        if (null == methodCall) {
            return;
        }
        Object markersToAdd = methodCall.argument("markersToAdd");
        addByList((List<Object>) markersToAdd);
        Object markersToChange = methodCall.argument("markersToChange");
        updateByList((List<Object>) markersToChange);
        Object markerIdsToRemove = methodCall.argument("markerIdsToRemove");
        removeByIdList((List<Object>) markerIdsToRemove);
        result.success(null);
    }

    public void addByList(List<Object> markersToAdd) {
        if (markersToAdd != null) {
            for (Object markerToAdd : markersToAdd) {
                add(markerToAdd);
            }
        }
    }

    private void add(Object markerObj) {
        if (null != amap) {
            MarkerOptionsBuilder builder = new MarkerOptionsBuilder();
            String dartMarkerId = MarkerUtil.interpretMarkerOptions(markerObj, builder);
            if (!TextUtils.isEmpty(dartMarkerId)) {
                MarkerOptions markerOptions = builder.build();
                final Marker marker = amap.addMarker(markerOptions);
                Object clickable = ConvertUtil.getKeyValueFromMapObject(markerObj, "clickable");
                if (null != clickable) {
                    marker.setClickable(ConvertUtil.toBoolean(clickable));
                }
                MarkerController markerController = new MarkerController(marker);
                controllerMapByDartId.put(dartMarkerId, markerController);
                idMapByOverlyId.put(marker.getId(), dartMarkerId);
            }
        }

    }

    private void updateByList(List<Object> markersToChange) {
        if (markersToChange != null) {
            for (Object markerToChange : markersToChange) {
                update(markerToChange);
            }
        }
    }

    private void update(Object markerToChange) {
        Object dartMarkerId = ConvertUtil.getKeyValueFromMapObject(markerToChange, "id");
        if (null != dartMarkerId) {
            MarkerController markerController = controllerMapByDartId.get(dartMarkerId);
            if (null != markerController) {
                MarkerUtil.interpretMarkerOptions(markerToChange, markerController);
            }
        }
    }


    private void removeByIdList(List<Object> markerIdsToRemove) {
        if (markerIdsToRemove == null) {
            return;
        }
        for (Object rawMarkerId : markerIdsToRemove) {
            if (rawMarkerId == null) {
                continue;
            }
            String markerId = (String) rawMarkerId;
            final MarkerController markerController = controllerMapByDartId.remove(markerId);
            if (markerController != null) {

                idMapByOverlyId.remove(markerController.getMarkerId());
                markerController.remove();
            }
        }
    }

    private void showMarkerInfoWindow(String dartMarkId) {
        MarkerController markerController = controllerMapByDartId.get(dartMarkId);
        if (null != markerController) {
            markerController.showInfoWindow();
        }
    }

    private void hideMarkerInfoWindow(String dartMarkId, LatLng newPosition) {
        if (TextUtils.isEmpty(dartMarkId)) {
            return;
        }
        if (!controllerMapByDartId.containsKey(dartMarkId)) {
            return;
        }
        MarkerController markerController = controllerMapByDartId.get(dartMarkId);
        if (null != markerController) {
            if (null != newPosition && null != markerController.getPosition()) {
                if (markerController.getPosition().equals(newPosition)) {
                    return;
                }
            }
            markerController.hideInfoWindow();
        }
    }

    @Override
    public void onMapClick(LatLng latLng) {
        hideMarkerInfoWindow(selectedMarkerDartId, null);
        nativeManager.onMapTap(); // 未开启自动选择时无操作（R-SEL-9）
    }

    /** map#update.options 中的 markerSelection、markerTransition（由 MapController 转交） */
    public void applyMapOptions(Map<?, ?> options) {
        nativeManager.applyOptions(options);
    }

    /**
     * 对插件管理的所有点位（含非 selectable 与过渡点）一律返回 true，
     * SDK 就不会再补发 onMapClick / onPOIClick（R-SEL-8、E-A4）
     */
    @Override
    public boolean onMarkerClick(Marker marker) {
        String dartId = idMapByOverlyId.get(marker.getId());
        if (null == dartId) {
            return false;
        }
        selectedMarkerDartId = dartId;
        showMarkerInfoWindow(dartId);
        // R-SEL-3：先提交选择并发 selectionChanged，再发 marker#onTap，同一回调内顺序固定
        nativeManager.onMarkerTap(dartId);
        LogUtil.i(CLASS_NAME, "onMarkerClick==>" + dartId);
        return true;
    }

    @Override
    public void onMarkerDragStart(Marker marker) {

    }

    @Override
    public void onMarkerDrag(Marker marker) {

    }

    @Override
    public void onMarkerDragEnd(Marker marker) {
        String markerId = marker.getId();
        String dartId = idMapByOverlyId.get(markerId);
        LatLng latLng = marker.getPosition();
        if (null == dartId) {
            return;
        }
        final Map<String, Object> data = new HashMap<>(2);
        data.put("markerId", dartId);
        data.put("position", ConvertUtil.latLngToList(latLng));
        methodChannel.invokeMethod("marker#onDragEnd", data);

        LogUtil.i(CLASS_NAME, "onMarkerDragEnd==>" + data);
    }

    @Override
    public void onPOIClick(Poi poi) {
        hideMarkerInfoWindow(selectedMarkerDartId, null != poi ? poi.getCoordinate() : null);
    }

    /** NativeMarkerManager 的 SDK 出口，共用旧路径的两张 id 映射表 */
    private final class SdkMarkerHost implements MarkerHost {
        @Override
        public boolean hasMarker(String id) {
            return controllerMapByDartId.containsKey(id);
        }

        @Override
        public void addMarker(FullMarkerOptions o, Object icon) {
            if (null == amap) {
                return;
            }
            Marker marker = amap.addMarker(new MarkerOptions()
                    .position(new LatLng(o.latitude, o.longitude))
                    .icon((BitmapDescriptor) icon));
            MarkerController controller = new MarkerController(marker);
            controller.applyFull(o, null); // 其余字段走同一完整替换路径
            controllerMapByDartId.put(o.id, controller);
            idMapByOverlyId.put(marker.getId(), o.id);
        }

        @Override
        public void updateMarker(FullMarkerOptions o, Object icon) {
            MarkerController controller = controllerMapByDartId.get(o.id);
            if (null != controller) {
                controller.applyFull(o, (BitmapDescriptor) icon);
            }
        }

        @Override
        public void removeMarker(String id) {
            MarkerController controller = controllerMapByDartId.remove(id);
            if (null != controller) {
                idMapByOverlyId.remove(controller.getMarkerId());
                controller.remove();
            }
        }

        @Override
        public Iterable<String> markerIds() {
            return controllerMapByDartId.keySet();
        }

        @Override
        public Object decodeIcon(Object rawIcon) {
            return ConvertUtil.toBitmapDescriptor(rawIcon);
        }

        @Override
        public Object defaultIcon() {
            return BitmapDescriptorFactory.defaultMarker();
        }

        @Override
        public void addNativeMarker(FullMarkerOptions o, NativeIcon icon, boolean selected) {
            addMarker(o, icon.descriptor);
            MarkerController controller = controllerMapByDartId.get(o.id);
            // native 点位锚点来自合成画布（§9.2），覆盖 options.anchor
            controller.setAnchor(icon.anchorU, icon.anchorV);
            controller.setZIndex(o.zIndexFor(selected));
        }

        @Override
        public void updateNativeMarker(FullMarkerOptions o, NativeIcon icon, boolean selected) {
            MarkerController controller = controllerMapByDartId.get(o.id);
            if (null != controller) {
                controller.applyNative(o, icon == null ? null : (BitmapDescriptor) icon.descriptor,
                        icon == null ? -1 : icon.anchorU, icon == null ? -1 : icon.anchorV,
                        selected);
            }
        }
    }
}
