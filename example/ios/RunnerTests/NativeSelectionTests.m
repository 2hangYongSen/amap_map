// S16 iOS 选择与高层置顶：T-SEL-1～5 状态机、T-TOP-1/2/3、R-TOP 其余规则、markers#removed
#import <XCTest/XCTest.h>
#import <MAMapKit/MAMapKit.h>
#import "AMapMarkerController.h"
#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapImageRegistry.h"
#import "AMapNativeEventLog.h"
#import "AMapNativeMarkerView.h"
#import "AMapSelectionState.h"
#import "AMapSelectionAnnotation.h"
#import "MAPointAnnotation+Flutter.h"

/// 地图替身（不创建真实 MAMapView）：只记录 annotation 的增删，viewForAnnotation 返回测试登记的 View
@interface FakeMapView : NSObject
@property (nonatomic, strong) NSMutableArray<id<MAAnnotation>> *added;
@property (nonatomic, strong) NSMapTable<id<MAAnnotation>, MAAnnotationView *> *views;
@end

@implementation FakeMapView
- (instancetype)init {
    self = [super init];
    _added = [NSMutableArray array];
    _views = [NSMapTable strongToStrongObjectsMapTable];
    return self;
}
- (void)addAnnotation:(id<MAAnnotation>)a { [_added addObject:a]; }
- (void)removeAnnotation:(id<MAAnnotation>)a {
    [_added removeObject:a];
    [_views removeObjectForKey:a];
}
- (MAAnnotationView *)viewForAnnotation:(id<MAAnnotation>)a { return [_views objectForKey:a]; }
- (MAAnnotationView *)dequeueReusableAnnotationViewWithIdentifier:(NSString *)i { return nil; }
- (NSArray<AMapSelectionAnnotation *> *)tops {
    return [_added filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, id b) {
        return [o isKindOfClass:[AMapSelectionAnnotation class]];
    }]];
}
@end

@interface NativeSelectionTests : XCTestCase
@end

@implementation NativeSelectionTests {
    FakeMapView *_map;
    AMapMarkerController *_c;
    NSMutableArray<NSArray *> *_sent;
}

- (void)setUp {
    _map = [FakeMapView new];
    _c = [[AMapMarkerController alloc] init:nil mapView:(MAMapView *)_map registrar:nil registry:NewRegistry()];
    _sent = [NSMutableArray array];
    __weak typeof(self) ws = self;
    _c.events.sink = ^(NSString *method, NSDictionary *args) { [ws record:method args:args]; };
    [_c attach];
}

- (void)record:(NSString *)method args:(NSDictionary *)args {
    [_sent addObject:@[method, args]];
}

- (void)tearDown {
    [_c nativeUpdate:@{@"protocolVersion": @2, @"syncId": @999, @"markerIdsToRemove": _c.markerDict.allKeys}];
    XCTAssertEqual(_map.tops.count, 0u, @"删除全部点后不应残留高层 Annotation");
    XCTAssertEqual(_c.registry.count, 0u);
}

// ---------- 载荷与工具 ----------

/// 本文件只用形状点，解码器不会被调用
static AMapImageRegistry *NewRegistry(void) {
    return [[AMapImageRegistry alloc] initWithDecoder:^UIImage *(AMapImageSource *s, NSString **e) { return nil; }
                                               runner:^(dispatch_block_t w, dispatch_block_t d) { w(); d(); }
                                               budget:1024];
}

static NSDictionary *P(NSString *id_, double lat, BOOL selectable) {
    NSDictionary *pres = @{@"content": @{@"text": id_},
                           @"style": @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFFFFFFF)}},
                           @"selectedStyle": @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFE53935)},
                                               @"textColor": @(0xFFFFFFFF)}};
    return @{@"id": id_, @"renderMode": @"native", @"position": @[@(lat), @116.4], @"alpha": @1,
             @"visible": @YES, @"clickable": @YES, @"zIndex": @1, @"icon": [NSNull null],
             @"nativePresentation": pres, @"selectable": @(selectable), @"selectedZIndex": @99};
}

static NSDictionary *With(NSDictionary *m, NSString *k, id v) {
    NSMutableDictionary *d = [m mutableCopy];
    d[k] = v;
    return d;
}

- (void)update:(NSDictionary *)extra {
    NSMutableDictionary *m = [@{@"protocolVersion": @2, @"syncId": @1} mutableCopy];
    [m addEntriesFromDictionary:extra];
    XCTAssertEqualObjects([_c nativeUpdate:m][@"accepted"], @YES);
}

- (void)enableAuto {
    [_c applyMarkerOptions:@{@"markerSelection": @{@"deselectOnMapTap": @YES, @"deselectOnRetap": @YES}}];
}

/// 模拟 SDK：为源点创建 View（viewForAnnotation:）并登记到替身地图
- (AMapNativeMarkerView *)sourceViewOf:(NSString *)id_ {
    AMapMarker *m = [_c markerForId:id_];
    AMapNativeMarkerView *v = (AMapNativeMarkerView *)[_c nativeViewForMarker:m mapView:(MAMapView *)_map];
    [_map.views setObject:v forKey:m.annotation];
    return v;
}

- (AMapNativeMarkerView *)topView {
    AMapSelectionAnnotation *a = _map.tops.firstObject;
    if (a == nil) return nil;
    AMapNativeMarkerView *v = (AMapNativeMarkerView *)[_map.views objectForKey:a];
    if (v == nil) {
        v = (AMapNativeMarkerView *)[_c nativeViewForSelectionAnnotation:a mapView:(MAMapView *)_map];
        if (v) [_map.views setObject:v forKey:a];
    }
    return v;
}

- (NSArray<NSDictionary *> *)selectionEvents {
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *e in _sent) {
        if ([e[0] isEqualToString:@"marker#selectionChanged"]) [out addObject:e[1]];
    }
    return out;
}

// ---------- T-SEL 状态机 ----------

// T-SEL-1：A → B → 取消，revision 1、2、3，previousId 正确；事件发出时外观已同步（iOS 同步布局）
- (void)testSel1RevisionsAndPreviousIds {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES), P(@"B", 39.91, YES)]}];
    [self enableAuto];
    [_c onMarkerTap:@"A"];
    [_c onMarkerTap:@"B"];
    [_c setSelectedFromArgs:@{@"markerId": [NSNull null]}];
    NSArray *ev = [self selectionEvents];
    XCTAssertEqual(ev.count, 3u);
    XCTAssertEqualObjects([ev valueForKey:@"revision"], (@[@1, @2, @3]));
    XCTAssertEqualObjects(ev[0][@"previousId"], [NSNull null]);
    XCTAssertEqualObjects(ev[1][@"previousId"], @"A");
    XCTAssertEqualObjects(ev[1][@"selectedId"], @"B");
    XCTAssertEqualObjects(ev[2][@"previousId"], @"B");
    XCTAssertEqualObjects(ev[2][@"selectedId"], [NSNull null]);
    XCTAssertEqualObjects([ev valueForKey:@"reason"], (@[@"markerTap", @"markerTap", @"api"]));
    XCTAssertEqual(_map.tops.count, 0u);
    XCTAssertEqualObjects([_c attach][@"selection"], (@{@"selectedId": [NSNull null], @"revision": @3}));
}

// T-SEL-1 iOS 部分：A 的高层 View 在改选 B 后不再被复用到 A（迟到外观不会应用）
- (void)testSel1StaleTopAnnotationIgnored {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES), P(@"B", 39.91, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    AMapSelectionAnnotation *staleA = _map.tops.firstObject;
    [_c setSelectedFromArgs:@{@"markerId": @"B"}];
    // SDK 在移除前才回调旧 Annotation 的 viewForAnnotation:
    XCTAssertNil([_c nativeViewForSelectionAnnotation:staleA mapView:(MAMapView *)_map]);
    XCTAssertEqualObjects(_map.tops.firstObject.sourceMarkerId, @"B");
}

// T-SEL-2：相同 id 不发事件、revision 不变
- (void)testSel2SameIdNoEvent {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    XCTAssertEqualObjects([_c setSelectedFromArgs:@{@"markerId": @"A"}][@"revision"], @1);
    for (int i = 0; i < 5; i++) {
        XCTAssertEqualObjects([_c setSelectedFromArgs:@{@"markerId": @"A"}][@"revision"], @1);
    }
    XCTAssertEqualObjects([_c setSelectedFromArgs:@{}][@"revision"], @2);
    XCTAssertEqualObjects([_c setSelectedFromArgs:@{@"markerId": [NSNull null]}][@"revision"], @2);
    XCTAssertEqual([self selectionEvents].count, 2u);
}

// T-SEL-3：选中点被删除后重新加入，选中态恢复，期间不发选择事件（R-SEL-6）
- (void)testSel3RemoveAndReAddKeepsSelection {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    [_sent removeAllObjects];
    [self update:@{@"syncId": @2, @"markerIdsToRemove": @[@"A"]}];
    XCTAssertEqual(_map.tops.count, 0u, @"R-TOP-4：删除时移除高层 Annotation");
    XCTAssertEqualObjects(_c.selection.selectedId, @"A", @"选择保留");
    [self update:@{@"syncId": @3, @"markersToAdd": @[P(@"A", 39.9, YES)]}];
    XCTAssertEqual(_map.tops.count, 1u);
    XCTAssertEqualObjects([self selectionEvents], @[]);
    XCTAssertEqual(_c.selection.revision, 1);
}

// T-SEL-4：选中点改为 selectable = false → invalidated
- (void)testSel4BecomesUnselectableInvalidates {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [self enableAuto];
    [_c onMarkerTap:@"A"];
    [self update:@{@"syncId": @2, @"markersToChange": @[P(@"A", 39.9, NO)]}];
    NSDictionary *last = [self selectionEvents].lastObject;
    XCTAssertEqualObjects(last[@"reason"], @"invalidated");
    XCTAssertEqualObjects(last[@"selectedId"], [NSNull null]);
    XCTAssertEqual(_map.tops.count, 0u);
    // API 选中的非 selectable 点不受影响：只有“可选中 → 不可选中”才取消
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    [self update:@{@"syncId": @3, @"markersToChange": @[With(P(@"A", 39.95, NO), @"alpha", @0.5)]}];
    XCTAssertEqualObjects(_c.selection.selectedId, @"A");
}

// T-SEL-5：点击非 selectable 点，选择不变，onTap 照常（R-SEL-3 顺序由 sink 与通道同一回调保证）
- (void)testSel5UnselectableTapKeepsSelection {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES), P(@"d", 39.91, NO)]}];
    [self enableAuto];
    [_c onMarkerTap:@"A"];
    XCTAssertTrue([_c onMarkerTap:@"d"], @"onTap 照常发出");
    XCTAssertEqualObjects(_c.selection.selectedId, @"A");
    XCTAssertEqual([self selectionEvents].count, 1u);
}

// R-SEL-2：重复点击、地图单击、关闭开关、未启用自动选择（R-SEL-9）
- (void)testSel2AutoRules {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c onMarkerTap:@"A"];
    [_c onMapTap];
    XCTAssertEqual([self selectionEvents].count, 0u, @"未开启 markerSelection 时点击不改变选择");
    [self enableAuto];
    [_c onMarkerTap:@"A"];
    [_c onMarkerTap:@"A"];
    XCTAssertEqualObjects([self selectionEvents].lastObject[@"reason"], @"retap");
    [_c onMarkerTap:@"A"];
    [_c onMapTap];
    XCTAssertEqualObjects([self selectionEvents].lastObject[@"reason"], @"mapTap");
    [_c applyMarkerOptions:@{@"markerSelection": @{@"deselectOnMapTap": @NO, @"deselectOnRetap": @NO}}];
    [_c onMarkerTap:@"A"];
    [_c onMarkerTap:@"A"];
    [_c onMapTap];
    XCTAssertEqualObjects(_c.selection.selectedId, @"A");
    // markerSelection 置空只关闭自动选择，已有选择保留
    [_c applyMarkerOptions:@{@"markerSelection": [NSNull null]}];
    XCTAssertFalse(_c.selection.autoEnabled);
    XCTAssertEqualObjects(_c.selection.selectedId, @"A");
}

// ---------- T-TOP ----------

// R-TOP-1：高层 Annotation 坐标、选中态外观、zIndex，源点 View 隐藏
- (void)testTop1ShowsSelectedOnTop {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    AMapNativeMarkerView *src = [self sourceViewOf:@"A"];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    XCTAssertTrue(src.hidden, @"源点 View 隐藏");
    AMapSelectionAnnotation *a = _map.tops.firstObject;
    XCTAssertEqualObjects(a.sourceMarkerId, @"A");
    XCTAssertNil(a.markerId, @"内部 Annotation 不带 markerId，不进入旧路径");
    XCTAssertEqualWithAccuracy(a.coordinate.latitude, 39.9, 1e-9);
    AMapNativeMarkerView *top = [self topView];
    XCTAssertEqual(top.zIndex, 99, @"selectedZIndex");
    XCTAssertFalse(top.hidden);
    XCTAssertEqualObjects(top.boundMarkerId, @"A");
    const CGFloat *rgb = CGColorGetComponents(top.shapeLayer.fillColor);
    XCTAssertEqualWithAccuracy(rgb[1], 0x39 / 255.0, 1e-3, @"按选中态绑定（红底）");
    XCTAssertEqualWithAccuracy(CGColorGetComponents(src.shapeLayer.fillColor)[1], 1, 1e-3, @"源点普通态（白底）");
    XCTAssertTrue(top.accessibilityTraits & UIAccessibilityTraitSelected, @"高层 View 无障碍标为选中");
    XCTAssertFalse(src.accessibilityTraits & UIAccessibilityTraitSelected);
    XCTAssertEqual(src.bounds.size.width, top.bounds.size.width, @"两态共用画布");
    XCTAssertTrue(CGPointEqualToPoint(src.centerOffset, top.centerOffset), @"锚点不跳");
    XCTAssertNil([_c markerForId:@"sel"]);
    XCTAssertEqual(_c.markerDict.count, 1u, @"不进入 markerDict");
}

// T-TOP-1：选中 → 修改坐标 → 高层 Annotation 坐标同步，内容变化重新绑定
- (void)testTop1PositionSync {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    AMapSelectionAnnotation *a = _map.tops.firstObject;
    AMapNativeMarkerView *top = [self topView];
    NSDictionary *moved = P(@"A", 39.95, YES);
    NSMutableDictionary *pres = [moved[@"nativePresentation"] mutableCopy];
    pres[@"content"] = @{@"text": @"新"};
    [self update:@{@"syncId": @2, @"markersToChange": @[With(moved, @"nativePresentation", pres)]}];
    XCTAssertEqual(_map.tops.firstObject, a, @"只改坐标与内容时复用同一个高层 Annotation");
    XCTAssertEqualWithAccuracy(a.coordinate.latitude, 39.95, 1e-9);
    XCTAssertEqualObjects(top.textLabel.text, @"新");
}

// T-TOP-2：visible = NO 的选中点取消选中后，源点 View 仍为 hidden
- (void)testTop2InvisibleStaysHiddenAfterDeselect {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    AMapNativeMarkerView *src = [self sourceViewOf:@"A"];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    [self update:@{@"syncId": @2, @"markersToChange": @[With(P(@"A", 39.9, YES), @"visible", @NO)]}];
    XCTAssertEqual(_map.tops.count, 0u, @"visible 变为 NO：移除高层 Annotation");
    XCTAssertTrue(src.hidden);
    [_c setSelectedFromArgs:@{@"markerId": [NSNull null]}];
    XCTAssertTrue(src.hidden, @"按期望 visible 恢复，不一律取消隐藏");
    // 对照：可见点取消选中后恢复显示
    [self update:@{@"syncId": @3, @"markersToChange": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    XCTAssertTrue(src.hidden);
    [_c setSelectedFromArgs:@{@"markerId": [NSNull null]}];
    XCTAssertFalse(src.hidden);
}

// T-TOP-3：选中点被删除后重新加入，高层展示恢复（新坐标）
- (void)testTop3RemoveAndReAddRestoresTop {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    [self topView];
    [self update:@{@"syncId": @2, @"markerIdsToRemove": @[@"A"]}];
    XCTAssertEqual(_map.tops.count, 0u);
    XCTAssertEqual([_c.registry count], 0u);
    [self update:@{@"syncId": @3, @"markersToAdd": @[P(@"A", 39.97, YES)]}];
    XCTAssertEqual(_map.tops.count, 1u);
    XCTAssertEqualWithAccuracy(_map.tops.firstObject.coordinate.latitude, 39.97, 1e-9);
    AMapNativeMarkerView *src = [self sourceViewOf:@"A"];
    XCTAssertTrue(src.hidden, @"重新创建的源点 View 也要隐藏（R-TOP-6）");
}

// R-TOP-2：selectedZIndex 变化 → 换一个高层 Annotation；模式变为 icon → 移除
- (void)testTop2ZIndexChangeReAddsAndIconRemoves {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    AMapSelectionAnnotation *first = _map.tops.firstObject;
    [self update:@{@"syncId": @2, @"markersToChange": @[With(P(@"A", 39.9, YES), @"selectedZIndex", @120)]}];
    XCTAssertNotEqual(_map.tops.firstObject, first);
    XCTAssertEqual(_map.tops.count, 1u);
    XCTAssertEqual(_map.tops.firstObject.zIndex, 120);
    // selectedZIndex 为空时沿用 zIndex
    [self update:@{@"syncId": @3, @"markersToChange": @[With(P(@"A", 39.9, YES), @"selectedZIndex", [NSNull null])]}];
    XCTAssertEqual(_map.tops.firstObject.zIndex, 1);
}

// R-TOP-5：高层 View 的点击按源点 id 进入正常流程；R-TOP-6：重建的源点 View 保持隐藏
- (void)testTop5TapMapsToSourceAndTop6Rehide {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [self enableAuto];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    AMapNativeMarkerView *recreated = [self sourceViewOf:@"A"];
    XCTAssertTrue(recreated.hidden);
    // 源点 View 被回收后复用给另一个点：解绑并按那个点重新绑定，不受隐藏影响
    [self update:@{@"syncId": @2, @"markersToAdd": @[P(@"B", 39.91, YES)]}];
    [recreated prepareForReuse];
    recreated.annotation = [_c markerForId:@"B"].annotation;
    [_c bindNativeView:recreated marker:[_c markerForId:@"B"]];
    XCTAssertFalse(recreated.hidden);
    // 高层点击（AMapViewController 以 sourceMarkerId 调用）→ 重复点击取消
    XCTAssertTrue([_c onMarkerTap:_map.tops.firstObject.sourceMarkerId]);
    XCTAssertEqualObjects([self selectionEvents].lastObject[@"reason"], @"retap");
}

// 资源恢复时高层 View 一并重新绑定（R-RES-12），删除时归还显示引用
- (void)testTopViewRebindsAndReleasesRefs {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES)]}];
    [_c setSelectedFromArgs:@{@"markerId": @"A"}];
    AMapNativeMarkerView *top = [self topView];
    XCTAssertTrue([[_c boundViews] containsObject:top]);
    [_c setSelectedFromArgs:@{@"markerId": [NSNull null]}];
    XCTAssertNil(top.boundMarkerId, @"移除时解绑");
    XCTAssertFalse([[_c boundViews] containsObject:top]);
}

// ---------- R-DEL-6：markers#removed ----------

- (void)testReplaceWhenReadyEmitsRemoved {
    [self update:@{@"markersToAdd": @[P(@"A", 39.9, YES), P(@"B", 39.91, YES)]}];
    [self update:@{@"syncId": @2, @"markerIdsToRemove": @[@"A"]}];
    XCTAssertEqual(_sent.count, 0u, @"immediate 不发 markers#removed");
    [_c applyMarkerOptions:@{@"markerTransition": @{@"mode": @"replaceWhenReady", @"timeoutMs": @1000}}];
    // 同一请求中删除后又加回的 id 不算删除
    [self update:@{@"syncId": @7, @"markerIdsToRemove": @[@"B", @"X"], @"markersToAdd": @[P(@"C", 39.92, NO)]}];
    XCTAssertNil([_c markerForId:@"B"], @"iOS 删除仍在本次调用完成");
    XCTAssertEqual(_sent.count, 1u);
    XCTAssertEqualObjects(_sent[0][0], @"markers#removed");
    XCTAssertEqualObjects(_sent[0][1][@"markerIds"], @[@"B"]);
    XCTAssertEqualObjects(_sent[0][1][@"removeSyncIds"], @[@7]);
    [self update:@{@"syncId": @8, @"markerIdsToRemove": @[@"C"], @"markersToAdd": @[P(@"C", 39.93, NO)]}];
    XCTAssertEqual(_sent.count, 1u, @"重新加入的不发");
}

// 创建参数带选项：先配置再登记点位
- (void)testCreationParamsApplyOptions {
    AMapMarkerController *c = [[AMapMarkerController alloc] init:nil mapView:(MAMapView *)_map registrar:nil
                                                        registry:NewRegistry()];
    [c applyCreationParams:@{@"protocolVersion": @2, @"markersToAdd": @[P(@"A", 39.9, YES)],
                             @"markerSelection": @{}, @"markerTransition": @{@"mode": @"replaceWhenReady"}}];
    XCTAssertTrue(c.selection.autoEnabled);
    XCTAssertTrue(c.replaceTransition);
    [c nativeUpdate:@{@"protocolVersion": @2, @"syncId": @2, @"markerIdsToRemove": @[@"A"]}];
}

// AMapSelectionState 纯逻辑
- (void)testSelectionStateUnit {
    AMapSelectionState *s = [AMapSelectionState new];
    XCTAssertNil([s onMarkerTap:@"A" selectable:YES], @"未启用");
    [s configure:@{}];
    XCTAssertNil([s onMarkerTap:@"A" selectable:NO]);
    AMapSelectionChange *c = [s onMarkerTap:@"A" selectable:YES];
    XCTAssertEqualObjects([c toMap], (@{@"selectedId": @"A", @"previousId": [NSNull null],
                                        @"reason": @"markerTap", @"revision": @1}));
    XCTAssertNil([s set:@"A" reason:AMapSelectionReasonApi]);
    XCTAssertEqualObjects([s snapshot], (@{@"selectedId": @"A", @"revision": @1}));
}

@end
