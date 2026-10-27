//
//  AMapMarkerController+Private.h
//  amap_map
//
//  旧路径与新协议（+Native）共用的内部状态，仅供插件内部与 XCTest 使用。
//

#import "AMapMarkerController.h"
#import "AMapNativeMarkerLayout.h"
#import "AMapImageRegistry.h"

@class AMapMarker;

NS_ASSUME_NONNULL_BEGIN

@interface AMapMarkerController ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, AMapMarker *> *markerDict;
@property (nonatomic, strong, nullable) FlutterMethodChannel *methodChannel;
@property (nonatomic, strong, nullable) NSObject<FlutterPluginRegistrar> *registrar;
@property (nonatomic, strong, nullable) MAMapView *mapView;

/// 新协议已启用（单向锁存，R-PROTO-0）
@property (nonatomic, assign) BOOL v2;
@property (nonatomic, assign) BOOL disposed;
@property (nonatomic, assign) NSInteger lastSyncId;
/// 创建参数为新协议时的初始拒绝列表（R-INIT-3）
@property (nonatomic, strong) NSMutableArray<NSString *> *initialRejected;
/// markerId → 最近一次代次；删除后保留，重新加入继续递增
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *generations;
/// 反向索引 imageId → {markerId}，只含成功取得期望引用的点（R-RES-12）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *imageIndex;
/// R-NAT-REJ-2：已报过九宫格超限的 normalKey，同一 key 只报一次
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *capErrorKeys;
/// 布局缓存（§10.1），按 normalKey；key 含资源解析结果
@property (nonatomic, strong) NSCache<NSString *, AMapNativeMarkerLayout *> *layoutCache;
@property (nonatomic, assign) double screenScale;
@property (nonatomic, strong, readwrite) AMapImageRegistry *registry;
@property (nonatomic, strong, readwrite) AMapNativeEventLog *events;

@end

NS_ASSUME_NONNULL_END
