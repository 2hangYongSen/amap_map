// S17 iOS 诊断与计时：T-TIME-1/3/4/5（§13），时钟用可控替身
#import <XCTest/XCTest.h>
#import <MAMapKit/MAMapKit.h>
#import "AMapMarkerController.h"
#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapImageRegistry.h"
#import "AMapNativeEventLog.h"
#import "AMapMarkerDiagnostics.h"

/// 地图替身：只记录 annotation 增删
@interface DiagFakeMap : NSObject
@end

@implementation DiagFakeMap
- (void)addAnnotation:(id<MAAnnotation>)a {}
- (void)addAnnotations:(NSArray *)as {}
- (void)removeAnnotation:(id<MAAnnotation>)a {}
- (MAAnnotationView *)viewForAnnotation:(id<MAAnnotation>)a { return nil; }
- (MAAnnotationView *)dequeueReusableAnnotationViewWithIdentifier:(NSString *)i { return nil; }
@end

/// 标记方块替身：提交本身耗时 0.25ms（推进假时钟）
@interface DiagFakeSquare : NSObject <AMapDiagnosticsSquare>
@property (nonatomic, strong) NSMutableArray<NSNumber *> *colors;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *shownAt;
@property (nonatomic, assign) NSInteger hides;
@property (nonatomic, copy) void (^tick)(void);
@property (nonatomic, copy) double (^now)(void);
@end

@implementation DiagFakeSquare
- (instancetype)init {
    self = [super init];
    _colors = [NSMutableArray array];
    _shownAt = [NSMutableArray array];
    return self;
}
- (void)showColor:(uint32_t)argb {
    self.tick();
    [_colors addObject:@(argb)];
    [_shownAt addObject:@(self.now())];
}
- (void)hide { _hides++; }
@end

@interface NativeDiagnosticsTests : XCTestCase
@end

@implementation NativeDiagnosticsTests {
    DiagFakeMap *_map;
    AMapMarkerController *_c;
    DiagFakeSquare *_square;
    NSMutableArray<NSArray *> *_sent;
    double _now;
}

- (void)setUp {
    _map = [DiagFakeMap new];
    AMapImageRegistry *reg = [[AMapImageRegistry alloc]
        initWithDecoder:^UIImage *(AMapImageSource *s, NSString **e) { return nil; }
                 runner:^(dispatch_block_t w, dispatch_block_t d) { w(); d(); }
                 budget:1024];
    _c = [[AMapMarkerController alloc] init:nil mapView:(MAMapView *)_map registrar:nil registry:reg];
    _sent = [NSMutableArray array];
    __weak typeof(self) ws = self;
    _c.events.sink = ^(NSString *method, NSDictionary *args) { [ws record:method args:args]; };
    _now = 0;
    _c.diag.clock = ^double { return ws ? [ws now] : 0; };
    _square = [DiagFakeSquare new];
    _square.tick = ^{ [ws advance:0.25]; };
    _square.now = ^double { return [ws now]; };
    _c.diag.square = _square;
    [_c attach];
}

- (double)now { return _now; }
- (void)advance:(double)ms { _now += ms; }
- (void)record:(NSString *)m args:(NSDictionary *)a { [_sent addObject:@[m, a]]; }

- (NSArray<NSDictionary *> *)events:(NSString *)method {
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *e in _sent) {
        if ([e[0] isEqualToString:method]) [out addObject:e[1]];
    }
    return out;
}

- (void)enable:(BOOL)on {
    [_c applyMarkerOptions:@{@"markerDiagnostics": @(on),
                             @"markerSelection": @{@"deselectOnMapTap": @YES, @"deselectOnRetap": @YES}}];
}

static NSDictionary *Native(NSString *id_, BOOL selectable) {
    NSDictionary *pres = @{@"content": @{@"text": id_},
                           @"style": @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFFFFFFF)}},
                           @"selectedStyle": @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFE53935)}}};
    return @{@"id": id_, @"renderMode": @"native", @"position": @[@39.9, @116.4], @"alpha": @1,
             @"visible": @YES, @"clickable": @YES, @"zIndex": @1, @"icon": [NSNull null],
             @"nativePresentation": pres, @"selectable": @(selectable), @"selectedZIndex": @99};
}

static NSDictionary *Icon(NSString *id_, NSString *asset) {
    return @{@"id": id_, @"renderMode": @"icon", @"position": @[@39.9, @116.4], @"alpha": @1,
             @"visible": @YES, @"clickable": @YES, @"zIndex": @1, @"icon": @[@"defaultMarker"],
             @"nativePresentation": [NSNull null], @"selectable": @NO, @"selectedZIndex": [NSNull null]};
}

- (NSDictionary *)update:(NSInteger)syncId add:(NSArray *)adds change:(NSArray *)changes extra:(NSDictionary *)extra {
    NSMutableDictionary *m = [@{@"protocolVersion": @2, @"syncId": @(syncId),
                                @"markersToAdd": adds ?: @[], @"markersToChange": changes ?: @[]} mutableCopy];
    [m addEntriesFromDictionary:extra ?: @{}];
    return [_c nativeUpdate:m];
}

// T-TIME-1：字段齐全；同一时钟 t3≥t2、t4≥t2；iOS 同步路径 t4≤t3，回执在返回前发出
- (void)testTTime1ReceiptFields {
    [self enable:YES];
    _now = 5;
    [self update:1 add:@[Native(@"A", NO), Native(@"B", NO)] change:nil extra:nil];
    NSArray *rs = [self events:@"markers#applied"];
    XCTAssertEqual(rs.count, 1u);
    NSDictionary *r = rs[0];
    for (NSString *k in @[@"syncId", @"nativeT2Ms", @"nativeT2vMs", @"markerColor", @"nativeT4Ms",
                          @"t2ToT3Ms", @"t2ToT4Ms", @"appliedCount", @"drawCount", @"cacheHits",
                          @"cacheMisses", @"bytesReceived", @"pendingTasks", @"memory", @"eventSeq"]) {
        XCTAssertNotNil(r[k], @"缺少 %@", k);
    }
    XCTAssertEqualObjects(r[@"syncId"], @1);
    XCTAssertEqualObjects(r[@"appliedCount"], @2);
    XCTAssertEqualWithAccuracy([r[@"nativeT2Ms"] doubleValue], 5, 1e-9);
    XCTAssertGreaterThanOrEqual([r[@"t2ToT3Ms"] doubleValue], 0);
    XCTAssertGreaterThanOrEqual([r[@"t2ToT4Ms"] doubleValue], 0);
    XCTAssertLessThanOrEqual([r[@"t2ToT4Ms"] doubleValue], [r[@"t2ToT3Ms"] doubleValue]);
}

// T-TIME-3：关闭时不发回执、不显示方块、点击不带 tapId、ping 与清缓存不可用
- (void)testTTime3DisabledEmitsNothing {
    [self enable:NO];
    [self update:1 add:@[Native(@"A", YES)] change:nil extra:nil];
    [_c onMarkerTap:@"A"];
    XCTAssertEqual([self events:@"markers#applied"].count, 0u);
    XCTAssertEqual([self events:@"markers#tapApplied"].count, 0u);
    XCTAssertEqual(_square.colors.count, 0u);
    XCTAssertNil([self events:@"marker#selectionChanged"][0][@"tapId"]);
    XCTAssertNil([_c diagPing]);
    XCTAssertFalse([_c diagClearCaches]);
    [self enable:YES];
    [self enable:NO];
    XCTAssertEqual(_square.hides, 1);
}

// T-TIME-4：方块提交与 t2 在同一次调用内，回执记录真实 t2v；颜色按 syncId 轮换，与 Android 相同
- (void)testTTime4MarkerSquare {
    [self enable:YES];
    _now = 10;
    [self update:1 add:@[Icon(@"I", nil)] change:nil extra:nil];
    [self update:2 add:@[Icon(@"J", nil)] change:nil extra:nil];
    NSDictionary *r = [self events:@"markers#applied"][0];
    XCTAssertEqualWithAccuracy([r[@"nativeT2Ms"] doubleValue], 10, 1e-9);
    XCTAssertEqualWithAccuracy([r[@"nativeT2vMs"] doubleValue], 10.25, 1e-9);
    XCTAssertEqualObjects(r[@"nativeT2vMs"], _square.shownAt[0]);
    XCTAssertEqualObjects(r[@"markerColor"], [AMapMarkerDiagnostics palette][1]);
    XCTAssertEqualObjects(_square.colors[1], [AMapMarkerDiagnostics palette][2]);
    XCTAssertEqualWithAccuracy([[_c diagPing][@"nativeMs"] doubleValue], _now, 1e-9);
    XCTAssertTrue([_c diagClearCaches]);
}

// T-TIME-5（新路径）：selectionChanged 与 onTap 带同一 tapId；外观同步绑定，c2 ≥ c1
- (void)testTTime5NativePath {
    [self enable:YES];
    [self update:1 add:@[Native(@"A", YES)] change:nil extra:nil];
    _now = 200;
    [_c onMarkerTap:@"A"];
    NSDictionary *sel = [self events:@"marker#selectionChanged"][0];
    NSDictionary *t = [self events:@"markers#tapApplied"][0];
    XCTAssertNotNil(sel[@"tapId"]);
    XCTAssertEqualObjects(t[@"tapId"], sel[@"tapId"]);
    XCTAssertEqualObjects(t[@"path"], @"native");
    XCTAssertEqualObjects(t[@"markerId"], @"A");
    XCTAssertGreaterThanOrEqual([t[@"c2Ms"] doubleValue], [t[@"c1Ms"] doubleValue]);
    XCTAssertNotNil(_c.topAnnotation, @"c2 时选中外观已提交");
    XCTAssertNotNil(t[@"drawCount"], @"点击回报带 drawCount");
}

// T-TIME-5（旧路径）：非 selectable 点的 tapId 由 Dart 随 diagTapId 带回，图标更新后记 c2
- (void)testTTime5LegacyPath {
    [self enable:YES];
    [self update:1 add:@[Icon(@"I", nil)] change:nil extra:nil];
    _now = 100;
    [_c onMarkerTap:@"I"];
    XCTAssertEqual([self events:@"markers#tapApplied"].count, 0u, @"非选择点不自动记 c2");
    _now = 160;
    // markerId 不符时忽略
    [self update:2 add:nil change:@[Icon(@"I", nil)] extra:@{@"diagTapId": @{@"tapId": @1, @"markerId": @"X"}}];
    XCTAssertEqual([self events:@"markers#tapApplied"].count, 0u);
    [self update:3 add:nil change:@[Icon(@"I", nil)] extra:@{@"diagTapId": @{@"tapId": @1, @"markerId": @"I"}}];
    NSArray *ts = [self events:@"markers#tapApplied"];
    XCTAssertEqual(ts.count, 1u);
    XCTAssertEqualObjects(ts[0][@"path"], @"icon");
    XCTAssertEqualWithAccuracy([ts[0][@"c1Ms"] doubleValue], 100, 1e-9);
    XCTAssertGreaterThanOrEqual([ts[0][@"c2Ms"] doubleValue], 160);
    [self update:4 add:nil change:@[Icon(@"I", nil)] extra:@{@"diagTapId": @{@"tapId": @1, @"markerId": @"I"}}];
    XCTAssertEqual([self events:@"markers#tapApplied"].count, 1u, @"同一 tapId 不重复");
}

// bytes 资源计入 bytesReceived
- (void)testBytesReceived {
    [self enable:YES];
    NSDictionary *img = @{@"id": @"b", @"type": @"bytes", @"pixelRatio": @2,
                          @"data": [FlutterStandardTypedData typedDataWithBytes:[NSData dataWithBytes:"abc" length:3]]};
    [self update:1 add:nil change:nil extra:@{@"imagesToAdd": @[img]}];
    XCTAssertEqualObjects([self events:@"markers#applied"][0][@"bytesReceived"], @3);
    [self update:2 add:nil change:nil extra:@{@"imageIdsToRelease": @[@"b"]}];
}
@end
