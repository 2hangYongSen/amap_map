//
//  AMapMarkerController+Private.h
//  amap_map
//
//  旧路径与新协议（+Native）共用的内部状态，仅供插件内部与 XCTest 使用。
//

#import "AMapMarkerController.h"
#import "AMapNativeMarkerLayout.h"
#import "AMapImageRegistry.h"
#import "AMapSelectionState.h"
#import "AMapSelectionAnnotation.h"
#import "AMapMarkerDiagnostics.h"

@class AMapMarker;
@class AMapNativeMarkerView;

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

// ---- S16 选择与置顶（+Selection.m） ----
@property (nonatomic, strong) AMapSelectionState *selection;
/// 当前高层 Annotation（§10.2），最多一个
@property (nonatomic, strong, nullable) AMapSelectionAnnotation *topAnnotation;
/// 高层 View（弱引用）；mapView 为 nil 的测试中也能找到它
@property (nonatomic, weak, nullable) AMapNativeMarkerView *topView;
/// markerTransition.mode == replaceWhenReady；iOS 删除仍在本次调用完成，只多发 markers#removed（R-DEL-6）
@property (nonatomic, assign) BOOL replaceTransition;
/// 非空时 applyOne 只收集要新增的 annotation，请求末尾一次 addAnnotations:。
/// SDK 每次添加调用有一笔随已有点数增长的固定开销，1000 点逐个添加约 600ms，一次添加约 380ms（iPhone 12 mini）
@property (nonatomic, strong, nullable) NSMutableArray<id<MAAnnotation>> *pendingAdds;

// ---- S17 诊断与计时（§13） ----
@property (nonatomic, strong, readwrite) AMapMarkerDiagnostics *diag;
/// 当前请求的计时记录；不在请求内或未开启时为 nil
@property (nonatomic, strong, nullable) AMapDiagSync *diagSync;
/// 当前点击的 tapId，随 selectionChanged 下发（R-TIME-2）
@property (nonatomic, strong, nullable) NSNumber *currentTapId;

@end

/// +Native.m 中实现、供 +Selection.m 使用的内部方法
@interface AMapMarkerController (NativeInternal)
- (NSHashTable<AMapNativeMarkerView *> *)boundViews;
- (void)refreshViewsOf:(AMapMarker *)m;
@end

/// +Selection.m 中实现、供 +Native.m 与旧路径使用的内部方法
@interface AMapMarkerController (SelectionInternal)
- (void)commitSelection:(nullable AMapSelectionChange *)change;
- (void)syncTopAnnotation;
- (void)selectionOnMarkerTap:(NSString *)markerId;
- (void)emitRemoved:(NSArray<NSString *> *)ids syncId:(NSInteger)syncId;
- (void)applyTopRules:(AMapNativeMarkerView *)view marker:(AMapMarker *)marker isTop:(BOOL)isTop;
@end

NS_ASSUME_NONNULL_END
