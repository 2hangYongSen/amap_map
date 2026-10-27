// S15 iOS 协议与资源：T-NAT-REJ-1、T-RES-12、T-PROTO-2/3、引用计数与握手
#import <XCTest/XCTest.h>
#import <Flutter/Flutter.h>
#import "AMapMarkerController.h"
#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapImageRegistry.h"
#import "AMapNativeEventLog.h"
#import "AMapNativeMarkerView.h"

/// 可控解码器：按 id 决定成功或失败；runner 手动执行，便于观察 pending
@interface FakeDecoding : NSObject
@property (nonatomic, strong) NSMutableSet<NSString *> *failing;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *queued;
@property (nonatomic) BOOL manual;
@end

@implementation FakeDecoding
- (instancetype)init {
    self = [super init];
    _failing = [NSMutableSet set];
    _queued = [NSMutableArray array];
    return self;
}
- (AMapImageDecoder)decoder {
    __weak typeof(self) weakSelf = self;
    return ^UIImage *(AMapImageSource *src, NSString **error) {
        if ([weakSelf.failing containsObject:src.id_]) {
            *error = @"模拟解码失败";
            return nil;
        }
        UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
        f.scale = src.pixelRatio;
        if ([src.id_ isEqualToString:@"R"]) {
            // 圆角气泡：逻辑 48×36、圆角 9，用于九宫格对称性测试
            return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 36) format:f]
                    imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [UIColor.orangeColor setFill];
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 48, 36) cornerRadius:9] fill];
            }];
        }
        // 20×10 像素、pixelRatio 2 → 逻辑 10×5
        return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(10, 5) format:f]
                imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [UIColor.orangeColor setFill];
            UIRectFill(CGRectMake(0, 0, 10, 5));
        }];
    };
}
- (AMapImageRunner)runner {
    __weak typeof(self) weakSelf = self;
    return ^(dispatch_block_t work, dispatch_block_t done) {
        dispatch_block_t all = ^{ work(); done(); };
        if (weakSelf.manual) {
            [weakSelf.queued addObject:all];
        } else {
            all();
        }
    };
}
- (void)drain {
    NSArray *q = [_queued copy];
    [_queued removeAllObjects];
    for (dispatch_block_t b in q) b();
}
@end

/// 事件记录（握手后 sink 收到的）
@interface NativeMarkerControllerTests : XCTestCase
@end

@implementation NativeMarkerControllerTests {
    FakeDecoding *_dec;
    AMapMarkerController *_c;
    NSMutableArray<NSArray *> *_sent;
}

- (void)setUp {
    _dec = [FakeDecoding new];
    AMapImageRegistry *reg = [[AMapImageRegistry alloc] initWithDecoder:[_dec decoder] runner:[_dec runner]
                                                                 budget:8 * 1024 * 1024];
    _c = [[AMapMarkerController alloc] init:nil mapView:nil registrar:nil registry:reg];
    _sent = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    _c.events.sink = ^(NSString *method, NSDictionary *args) {
        [weakSelf recordEvent:method args:args];
    };
}

- (void)recordEvent:(NSString *)method args:(NSDictionary *)args {
    [_sent addObject:@[method, args]];
}

- (void)tearDown {
    // 不变量：删除全部点位、释放全部资源、View 解绑后，注册表清空（引用计数全部归零）
    [_c nativeUpdate:@{@"protocolVersion": @2, @"syncId": @999,
                       @"markerIdsToRemove": _c.markerDict.allKeys,
                       @"imageIdsToRelease": @[@"A", @"B", @"I", @"R"]}];
    XCTAssertEqual(_c.registry.count, 0u, @"tearDown 后仍有资源条目，引用计数不成对");
}

// ---------- 载荷构造 ----------

static NSDictionary *Shape(NSString *text) {
    return @{@"content": @{@"text": text},
             @"style": @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFFFFFFF)},
                         @"padding": @[@4, @2, @4, @2]}};
}

static NSDictionary *ImageBg(NSString *imageId, NSString *text) {
    NSDictionary *style = @{@"background": @{@"type": @"image", @"imageId": imageId, @"size": @[@40, @20]},
                            @"fontSize": @12};
    return @{@"content": @{@"text": text}, @"style": style, @"selectedStyle": [NSNull null]};
}

static NSDictionary *NativeM(NSString *id_, NSDictionary *presentation) {
    return @{@"id": id_, @"renderMode": @"native", @"position": @[@39.9, @116.4], @"alpha": @1,
             @"visible": @YES, @"clickable": @YES, @"zIndex": @0, @"icon": [NSNull null],
             @"nativePresentation": presentation, @"selectable": @NO, @"selectedZIndex": [NSNull null]};
}

static NSDictionary *IconM(NSString *id_) {
    NSData *png = UIImagePNGRepresentation([[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)]
                                            imageWithActions:^(UIGraphicsImageRendererContext *c) {}]);
    return @{@"id": id_, @"renderMode": @"icon", @"position": @[@39.9, @116.4], @"alpha": @0.5,
             @"visible": @YES, @"clickable": @YES, @"zIndex": @0,
             @"icon": @[@"fromBytes", [FlutterStandardTypedData typedDataWithBytes:png]],
             @"nativePresentation": [NSNull null], @"selectable": @NO, @"selectedZIndex": [NSNull null]};
}

static NSDictionary *Asset(NSString *id_) {
    return @{@"id": id_, @"type": @"asset", @"asset": @"assets/x.png", @"package": [NSNull null], @"pixelRatio": @2};
}

- (NSDictionary *)update:(NSDictionary *)extra {
    NSMutableDictionary *m = [@{@"protocolVersion": @2, @"syncId": @1} mutableCopy];
    [m addEntriesFromDictionary:extra];
    return [_c nativeUpdate:m];
}

- (AMapNativeMarkerView *)viewFor:(NSString *)id_ {
    return (AMapNativeMarkerView *)[_c nativeViewForMarker:[_c markerForId:id_] mapView:nil];
}

// ---------- 测试 ----------

// T-NAT-REJ-1：同批 add(A)、add(B 非法)、change(C 非法)
- (void)testNatRej1PartialRejectKeepsState {
    [self update:@{@"markersToAdd": @[NativeM(@"C", Shape(@"c0"))]}];
    AMapMarker *c0 = [_c markerForId:@"C"];
    NSInteger gen = c0.generation;
    AMapNativeMarkerView *cv = [self viewFor:@"C"];
    NSString *shown = cv.textLabel.text;

    NSMutableDictionary *badB = [NativeM(@"B", Shape(@"b")) mutableCopy];
    badB[@"renderMode"] = [NSNull null];
    NSMutableDictionary *badStyle = [Shape(@"c1") mutableCopy];
    badStyle[@"style"] = @{@"background": @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @1},
                           @"fontSize": @(-1)};
    NSDictionary *r = [self update:@{@"syncId": @2,
                                     @"markersToAdd": @[NativeM(@"A", Shape(@"a")), badB],
                                     @"markersToChange": @[NativeM(@"C", badStyle)]}];

    XCTAssertEqualObjects(r[@"accepted"], @YES);
    XCTAssertEqualObjects([NSSet setWithArray:r[@"rejectedMarkerIds"]], ([NSSet setWithArray:@[@"B", @"C"]]));
    XCTAssertNotNil([_c markerForId:@"A"]);
    XCTAssertNil([_c markerForId:@"B"]);
    XCTAssertNil(_c.generations[@"B"], @"新增被拒绝的点不分配代次");
    AMapMarker *c1 = [_c markerForId:@"C"];
    XCTAssertEqual(c1, c0, @"修改被拒绝：模型对象不变");
    XCTAssertEqual(c1.generation, gen, @"代次不变");
    XCTAssertEqual(_c.generations[@"C"].integerValue, gen);
    XCTAssertEqualObjects(c1.spec.text, @"c0");
    XCTAssertEqualObjects(cv.textLabel.text, shown, @"显示内容不变");
    // 每个被拒绝的点各有一条 invalidConfig（握手前缓冲在 errors 中）
    NSArray *errs = [_c.events errorsSnapshot];
    XCTAssertEqual(errs.count, 2u);
    for (NSDictionary *e in errs) XCTAssertEqualObjects(e[@"code"], @"invalidConfig");
}

// 结构错误：整个请求 accepted=false，不做任何修改
- (void)testMalformedRequestNotAccepted {
    NSDictionary *r = [self update:@{@"markersToAdd": @[@{@"renderMode": @"native"}]}];
    XCTAssertEqualObjects(r[@"accepted"], @NO);
    XCTAssertEqual(_c.markerDict.count, 0u);
}

// T-RES-12：资源失败 → 降级背景（保留文字）→ 重试 ready → 背景 image 就是注册表中的 UIImage
- (void)testRes12FailedThenRecoveredRebindsView {
    [_dec.failing addObject:@"A"];
    [self update:@{@"imagesToAdd": @[Asset(@"A")],
                   @"markersToAdd": @[NativeM(@"p1", ImageBg(@"A", @"价")), NativeM(@"p2", ImageBg(@"A", @"格"))]}];
    XCTAssertEqual([_c.registry stateOf:@"A"], AMapImageStateFailed);
    AMapNativeMarkerView *v1 = [self viewFor:@"p1"];
    AMapNativeMarkerView *v2 = [self viewFor:@"p2"];
    for (AMapNativeMarkerView *v in @[v1, v2]) {
        XCTAssertTrue(v.backgroundImageView.hidden, @"失败时不显示图片背景");
        XCTAssertFalse(v.shapeLayer.hidden, @"失败时显示默认背景");
        XCTAssertFalse(v.textLabel.hidden);
        XCTAssertFalse(v.hidden);
        XCTAssertEqual(v.boundImageIds.count, 0u, @"降级外观不持有显示引用");
    }
    XCTAssertEqualObjects(v1.textLabel.text, @"价");
    NSString *fallbackKey = AMapNativeRenderKey([_c markerForId:@"p1"].spec, _c.screenScale, _c.registry, NO);

    // Dart 重新发送 failed 资源（R-RES-8）：重试成功后注册表通知并重新绑定
    [_dec.failing removeAllObjects];
    [self update:@{@"syncId": @2, @"imagesToAdd": @[Asset(@"A")]}];
    XCTAssertEqual([_c.registry stateOf:@"A"], AMapImageStateReady);
    UIImage *a = [_c.registry imageFor:@"A"];
    XCTAssertNotNil(a);
    for (AMapNativeMarkerView *v in @[v1, v2]) {
        XCTAssertFalse(v.backgroundImageView.hidden);
        XCTAssertTrue(v.shapeLayer.hidden);
        XCTAssertEqual(v.backgroundImageView.image, a, @"背景就是注册表中 A 的 UIImage");
        XCTAssertEqualObjects(v.boundImageIds, [NSSet setWithObject:@"A"]);
    }
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDisplay], 2);
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDesired], 2);
    NSString *readyKey = AMapNativeRenderKey([_c markerForId:@"p1"].spec, _c.screenScale, _c.registry, NO);
    XCTAssertNotEqualObjects(fallbackKey, readyKey, @"降级与正常 key 不同（R-RES-12）");
}

// R-RES-5 iOS：pending 期间按降级外观布局，ready 后 key 变化、View 重新绑定
- (void)testPendingThenReadyRebinds {
    _dec.manual = YES;
    NSDictionary *r = [self update:@{@"imagesToAdd": @[Asset(@"A")], @"markersToAdd": @[NativeM(@"p", ImageBg(@"A", @"x"))]}];
    XCTAssertEqualObjects(r[@"imagesPending"], @[@"A"]);
    AMapNativeMarkerView *v = [self viewFor:@"p"];
    XCTAssertTrue(v.backgroundImageView.hidden);
    NSString *pendingKey = AMapNativeRenderKey([_c markerForId:@"p"].spec, 3, _c.registry, NO);
    [_dec drain];
    XCTAssertEqual(v.backgroundImageView.image, [_c.registry imageFor:@"A"]);
    XCTAssertNotEqualObjects(pendingKey, AMapNativeRenderKey([_c markerForId:@"p"].spec, 3, _c.registry, NO));
}

// T-PROTO-2：native(A) → icon(X)：原生状态与资源引用全部清除，显示 icon
- (void)testProto2NativeToIconClearsNativeState {
    [self update:@{@"imagesToAdd": @[Asset(@"A")], @"markersToAdd": @[NativeM(@"m", ImageBg(@"A", @"n"))]}];
    AMapNativeMarkerView *v = [self viewFor:@"m"];
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDisplay], 1);
    NSDictionary *r = [self update:@{@"syncId": @2, @"markersToChange": @[IconM(@"m")]}];
    XCTAssertEqualObjects(r[@"rejectedMarkerIds"], @[]);
    AMapMarker *m = [_c markerForId:@"m"];
    XCTAssertFalse(m.isNative);
    XCTAssertNil(m.spec);
    XCTAssertNil(m.presentation);
    XCTAssertNotNil(m.image, @"显示的是 icon X");
    XCTAssertEqualWithAccuracy(m.alpha, 0.5, 1e-9, @"完整替换：alpha 取新值");
    XCTAssertNil(v.boundMarkerId, @"原 native View 已解绑");
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDisplay], 0);
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDesired], 0);
    XCTAssertEqual([_c.imageIndex[@"A"] count], 0u);
}

// T-PROTO-3：不带 protocolVersion 的旧载荷走旧路径；旧点按 icon 处理（R-PROTO-1a）
- (void)testProto3LegacyPayloadUntouched {
    NSMutableDictionary *legacy = [IconM(@"old") mutableCopy];
    [legacy removeObjectsForKeys:@[@"renderMode", @"nativePresentation", @"selectable", @"selectedZIndex"]];
    XCTAssertFalse([AMapMarkerController isV2Payload:@{@"markersToAdd": @[legacy]}]);
    XCTAssertTrue([AMapMarkerController isV2Payload:@{@"protocolVersion": @2}]);
    [_c addMarkers:@[legacy]];
    AMapMarker *m = [_c markerForId:@"old"];
    XCTAssertNil(m.renderMode);
    XCTAssertFalse(m.isNative);
    XCTAssertNotNil(m.image);
    XCTAssertEqual(_c.v2, NO, @"旧载荷不启用新协议");
}

// 握手：attach 前不发事件，attach 返回资源快照；之后状态变化实时发送（R-INIT-2/3/4）
- (void)testAttachSnapshotThenEvents {
    [_dec.failing addObject:@"B"];
    [_c applyCreationParams:@{@"protocolVersion": @2,
                              @"imagesToAdd": @[Asset(@"A"), Asset(@"B")],
                              @"markersToAdd": @[NativeM(@"ok", Shape(@"1")), @{@"id": @"bad", @"renderMode": @"x"}]}];
    XCTAssertEqual(_sent.count, 0u, @"握手前不发送");
    NSDictionary *snap = [_c attach];
    XCTAssertEqualObjects(snap[@"rejectedMarkerIds"], @[@"bad"]);
    XCTAssertEqualObjects(snap[@"images"][@"ready"], @[@"A"]);
    XCTAssertEqualObjects([snap[@"images"][@"failed"] firstObject][@"id"], @"B");
    NSInteger lastSeq = [snap[@"lastEventSeq"] integerValue];
    XCTAssertGreaterThan(lastSeq, 0);
    XCTAssertEqual([snap[@"errors"] count], 2u, @"bad 的 invalidConfig 与 B 的解码失败");

    [_dec.failing removeAllObjects];
    [self update:@{@"imagesToAdd": @[Asset(@"B")]}];
    XCTAssertEqual(_sent.count, 1u);
    XCTAssertEqualObjects(_sent[0][0], @"marker#imagesResult");
    XCTAssertEqualObjects(_sent[0][1][@"ready"], @[@"B"]);
    XCTAssertGreaterThan([_sent[0][1][@"eventSeq"] integerValue], lastSeq);
}

// R-RES-10：releasing 资源在仍被引用时保留，最后一个引用归还后移除
- (void)testReleaseWaitsForRefs {
    [self update:@{@"imagesToAdd": @[Asset(@"A")], @"markersToAdd": @[NativeM(@"p", ImageBg(@"A", @"x"))]}];
    [self viewFor:@"p"];
    [self update:@{@"syncId": @2, @"imageIdsToRelease": @[@"A"]}];
    XCTAssertTrue([_c.registry contains:@"A"], @"仍有期望与显示引用，不释放");
    NSInteger decodes = _c.registry.decodeCount;
    [self update:@{@"syncId": @3, @"imagesToAdd": @[Asset(@"A")]}];
    XCTAssertEqual(_c.registry.decodeCount, decodes, @"releasing 中重新加入的 ready 资源不重新解码");
    [self update:@{@"syncId": @4, @"markerIdsToRemove": @[@"p"], @"imageIdsToRelease": @[@"A"]}];
    XCTAssertFalse([_c.registry contains:@"A"]);
}

// 同一点位修改（同模式）：View 复用并按新快照重新绑定，旧资源引用归还
- (void)testChangeRebindsAndSwapsRefs {
    [self update:@{@"imagesToAdd": @[Asset(@"A"), Asset(@"B")],
                   @"markersToAdd": @[NativeM(@"p", ImageBg(@"A", @"x"))]}];
    AMapNativeMarkerView *v = [self viewFor:@"p"];
    [self update:@{@"syncId": @2, @"markersToChange": @[NativeM(@"p", ImageBg(@"B", @"y"))]}];
    XCTAssertEqualObjects(v.textLabel.text, @"y");
    XCTAssertEqual(v.backgroundImageView.image, [_c.registry imageFor:@"B"]);
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDesired], 0);
    XCTAssertEqual([_c.registry refsOf:@"A" kind:AMapImageRefDisplay], 0);
    XCTAssertEqual([_c.registry refsOf:@"B" kind:AMapImageRefDisplay], 1);
}

// R-IOS-1/R-IOS-2：复用 View 每次重设 zIndex、alpha、hidden、enabled
- (void)testBindSetsAllVisibleProperties {
    NSMutableDictionary *m = [NativeM(@"p", Shape(@"x")) mutableCopy];
    m[@"zIndex"] = @7;
    m[@"alpha"] = @0.4;
    m[@"visible"] = @NO;
    m[@"clickable"] = @NO;
    [self update:@{@"markersToAdd": @[m]}];
    AMapNativeMarkerView *v = [self viewFor:@"p"];
    XCTAssertEqual(v.zIndex, 7);
    XCTAssertEqualWithAccuracy(v.alpha, 0.4, 1e-6);
    XCTAssertTrue(v.hidden);
    XCTAssertFalse(v.enabled);
    XCTAssertEqualObjects(v.reuseIdentifier, AMapFlutterNativeMarkerViewIdentifier);
    XCTAssertTrue(v.isAccessibilityElement);
    XCTAssertEqualObjects(v.accessibilityLabel, @"x");
    XCTAssertFalse(v.accessibilityTraits & UIAccessibilityTraitButton, @"clickable = NO 不标按钮");
    // 带阴影的形状必须有 shadowPath（E-I3）
    NSMutableDictionary *p = [Shape(@"s") mutableCopy];
    NSMutableDictionary *st = [p[@"style"] mutableCopy];
    st[@"shadow"] = @{@"color": @(0x55000000), @"blurRadius": @4, @"offset": @[@0, @2]};
    p[@"style"] = st;
    // zIndex 同为 7：同一 annotation 上整体替换，原 View 重新绑定
    NSMutableDictionary *m2 = [NativeM(@"p", p) mutableCopy];
    m2[@"zIndex"] = @7;
    [self update:@{@"syncId": @2, @"markersToChange": @[m2]}];
    XCTAssertEqualObjects(v.boundMarkerId, @"p");
    XCTAssertFalse(v.hidden, @"visible 恢复为 YES");
    XCTAssertTrue(v.shapeLayer.shadowPath != NULL);
    XCTAssertFalse(v.shapeLayer.shouldRasterize);
    // zIndex 变化：运行中改 zIndex 无效（E-I0），换 annotation 重新添加，旧 View 解绑
    m2[@"zIndex"] = @9;
    [self update:@{@"syncId": @3, @"markersToChange": @[m2]}];
    XCTAssertNil(v.boundMarkerId);
    XCTAssertEqual([self viewFor:@"p"].zIndex, 9);
}

// 九宫格 + 阴影：阴影预渲染图里本体左右圆角必须对称（2 倍图在 3 倍屏上曾被切错）
- (void)testNinePatchShadowImageCornersSymmetric {
    NSDictionary *bg = @{@"type": @"image", @"imageId": @"R", @"size": @[@67, @30], @"capInsets": @[@10, @10, @10, @10]};
    NSDictionary *style = @{@"background": bg, @"fontSize": @12,
                            @"shadow": @{@"color": @(0x00000000), @"blurRadius": @0}};
    NSDictionary *pres = @{@"content": @{@"text": @"x"}, @"style": style, @"selectedStyle": [NSNull null]};
    [self update:@{@"imagesToAdd": @[Asset(@"R")], @"markersToAdd": @[NativeM(@"p", pres)]}];
    UIImage *img = [self viewFor:@"p"].shadowImageView.image;
    XCTAssertNotNil(img);
    // 逐行测量顶部几行左右两侧透明像素数
    CGImageRef cg = img.CGImage;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSMutableData *d = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(d.mutableBytes, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    const uint8_t *p = d.bytes;
    for (size_t y = 0; y < 6; y++) {
        int l = 0, r = 0;
        while (l < (int)w && p[(y * w + l) * 4 + 3] < 128) l++;
        while (r < (int)w && p[(y * w + (w - 1 - r)) * 4 + 3] < 128) r++;
        XCTAssertEqualWithAccuracy(l, r, 1, @"第 %zu 行左右圆角不对称", y);
    }
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
}

@end
