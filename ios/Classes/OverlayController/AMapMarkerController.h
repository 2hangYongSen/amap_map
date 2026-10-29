//
//  AMapMarkerController.h
//  amap_map
//
//  Created by lly on 2020/11/3.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <MAMapKit/MAMapKit.h>
#import "AMapImageRegistry.h"

NS_ASSUME_NONNULL_BEGIN

@class AMapMarker;
@class AMapNativeEventLog;
@class AMapNativeMarkerView;
@class AMapNativeMarkerLayout;
@class AMapMarkerDiagnostics;

@interface AMapMarkerController : NSObject

- (instancetype)init:(FlutterMethodChannel*)methodChannel
             mapView:(MAMapView*)mapView
           registrar:(NSObject<FlutterPluginRegistrar>*)registrar;

/// 可注入资源注册表（XCTest 用同步解码）；channel、mapView 可为替身或 nil
- (instancetype)init:(nullable FlutterMethodChannel*)methodChannel
             mapView:(nullable MAMapView*)mapView
           registrar:(nullable NSObject<FlutterPluginRegistrar>*)registrar
            registry:(nullable AMapImageRegistry *)registry;

- (nullable AMapMarker *)markerForId:(NSString *)markerId;

- (void)addMarkers:(NSArray*)markersToAdd;

- (void)changeMarkers:(NSArray*)markersToChange;

- (void)removeMarkerIds:(NSArray*)markerIdsToRemove;

//MARK: Marker的回调

- (BOOL)onMarkerTap:(NSString*)markerId;

- (BOOL)onMarker:(NSString *)markerId endPostion:(CLLocationCoordinate2D)position;

//- (BOOL)onInfoWindowTap:(NSString *)markerId;

/// 载荷是否为新协议；不带 protocolVersion 的请求走旧逻辑（R-PROTO-3）
+ (BOOL)isV2Payload:(nullable id)args;

@property (nonatomic, strong, readonly) AMapImageRegistry *registry;
@property (nonatomic, strong, readonly) AMapNativeEventLog *events;
/// 诊断与计时（§13）；标记方块由 AMapViewController 设置
@property (nonatomic, strong, readonly) AMapMarkerDiagnostics *diag;
/// 文字测量，默认 UIFont；测试替换为确定性测量器
@property (nonatomic, strong) id<AMapTextMeasurer> measurer;

@end

/// 新协议（§6），实现在 AMapMarkerController+Native.m；
/// 资源变为 ready / failed 时由注册表回调，发 imagesResult 并重新绑定 View（R-RES-12）
@interface AMapMarkerController (Native) <AMapImageRegistryListener>

- (void)setUpNative;
- (NSDictionary *)nativeUpdate:(nullable id)args;
- (NSDictionary *)nativeResync:(nullable id)args;

/// 创建参数为新协议：先登记资源再登记点位，拒绝结果留给 attach（R-SYNC-4）
- (void)applyCreationParams:(NSDictionary *)params;

/// markers#attach：幂等启用新协议并返回状态快照（R-INIT-3）
- (NSDictionary *)attach;

/// native 点位的 View（独立复用标识，§10.1），在 viewForAnnotation: 中调用
- (MAAnnotationView *)nativeViewForMarker:(AMapMarker *)marker mapView:(nullable MAMapView *)mapView;

/// 按当前期望快照重新绑定（R-IOS-1）
- (void)bindNativeView:(AMapNativeMarkerView *)view marker:(AMapMarker *)marker;

/// 当前普通态布局（按渲染 key 缓存）
- (AMapNativeMarkerLayout *)layoutForMarker:(AMapMarker *)marker;

/// 地图销毁：关闭事件、丢弃之后的解码结果；幂等
- (void)dispose;

/// diag#ping：{nativeMs}；诊断未开启返回 nil（§13）
- (nullable NSDictionary *)diagPing;
/// diag#clearCaches：清空布局缓存；诊断未开启返回 NO
- (BOOL)diagClearCaches;

@end

@class AMapSelectionAnnotation;

/// 原生单选（§11）与选中置顶（§10.2），实现在 AMapMarkerController+Selection.m
@interface AMapMarkerController (Selection)

/// markers#setSelected：返回 {revision}；id 相同不发事件（R-SEL-4）
- (NSDictionary *)setSelectedFromArgs:(nullable id)args;

/// 地图空白处单击（didSingleTappedAtCoordinate:）
- (void)onMapTap;

/// map#update.options / 创建参数中的 markerSelection、markerTransition
- (void)applyMarkerOptions:(nullable id)options;

/// 高层 Annotation 的 View（viewForAnnotation:）；已过期的返回 nil
- (nullable MAAnnotationView *)nativeViewForSelectionAnnotation:(AMapSelectionAnnotation *)annotation
                                                        mapView:(nullable MAMapView *)mapView;

/// didAddAnnotationViews: 中再绑定一次（R-IOS-2）
- (void)rebindSelectionView:(AMapNativeMarkerView *)view;

@end

NS_ASSUME_NONNULL_END
