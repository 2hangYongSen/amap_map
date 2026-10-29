// S15 共享夹具：T-NORM-1、T-ELL-1、T-GEO-1、T-GEO-3（与 Dart、JVM 读同一份 JSON）
#import <XCTest/XCTest.h>
#import "AMapSpecReader.h"
#import "AMapNativeMarkerSpec.h"
#import "AMapNativeMarkerLayout.h"

/// 夹具里的确定性测量器：宽 = UTF-16 长度 × fontSize × widthFactor
@interface FixtureMeasurer : NSObject <AMapTextMeasurer>
@property (nonatomic) double widthFactor, lineHeightFactor;
@end

@implementation FixtureMeasurer
- (double)widthOf:(NSString *)text fontSize:(double)fontSize weight:(NSInteger)weight {
    return text.length * fontSize * _widthFactor;
}
- (double)lineHeightForFontSize:(double)fontSize weight:(NSInteger)weight {
    return fontSize * _lineHeightFactor;
}
@end

/// 夹具几何用例只有形状背景，资源一律视为不存在
@interface NoImages : NSObject <AMapImageResolver>
@end

@implementation NoImages
- (AMapImageResolution)resolutionOf:(NSString *)imageId {
    return AMapImageResolutionFallback;
}
- (BOOL)logicalSizeOf:(NSString *)imageId size:(CGSize *)size {
    return NO;
}
@end

@interface NativeMarkerFixtureTests : XCTestCase
@end

@implementation NativeMarkerFixtureTests {
    NSDictionary *_fx;
}

/// 模拟器可直接读宿主文件：按本源文件位置定位仓库根目录下的夹具
- (void)setUp {
    NSString *here = [NSString stringWithUTF8String:__FILE__];
    NSString *root = [[[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                       stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *path = [root stringByAppendingPathComponent:@"test/fixtures/native_marker_layout.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"夹具不存在: %@", path);
    _fx = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (FixtureMeasurer *)measurer {
    FixtureMeasurer *m = [FixtureMeasurer new];
    m.widthFactor = [_fx[@"measurer"][@"widthFactor"] doubleValue];
    m.lineHeightFactor = [_fx[@"measurer"][@"lineHeightFactor"] doubleValue];
    return m;
}

static NSInteger ScaleOf(NSString *kind) {
    return [kind isEqualToString:@"length"] ? AMapNormLengthScale : AMapNormRatioScale;
}

// T-NORM-1：临界值舍入（远离零），同组输入规范化结果相同
- (void)testNorm1RoundingMatchesFixture {
    for (NSDictionary *c in _fx[@"normalization"][@"cases"]) {
        int32_t units = 0;
        XCTAssertTrue(AMapNormUnits([c[@"input"] doubleValue], ScaleOf(c[@"kind"]), &units), @"%@", c[@"name"]);
        XCTAssertEqual(units, [c[@"units"] intValue], @"%@", c[@"name"]);
    }
    for (NSDictionary *g in _fx[@"normalization"][@"sameGroups"]) {
        NSMutableSet *seen = [NSMutableSet set];
        for (NSNumber *v in g[@"inputs"]) {
            int32_t units = 0;
            AMapNormUnits(v.doubleValue, ScaleOf(g[@"kind"]), &units);
            [seen addObject:@(units)];
        }
        XCTAssertEqual(seen.count, 1u, @"%@", g[@"name"]);
    }
    int32_t out = 0;
    XCTAssertFalse(AMapNormUnits(NAN, 64, &out));
    XCTAssertFalse(AMapNormUnits(INFINITY, 64, &out));
}

// T-ELL-1：等于不省略、超出加“…”、不拆字形簇、avail ≤ 0 不显示
- (void)testEll1EllipsisMatchesFixture {
    FixtureMeasurer *m = [self measurer];
    double font = [_fx[@"ellipsis"][@"fontSize"] doubleValue];
    for (NSDictionary *c in _fx[@"ellipsis"][@"cases"]) {
        double avail = [c[@"avail"] doubleValue];
        NSString *got = AMapEllipsize(c[@"text"], avail, m, font, 400);
        XCTAssertEqualObjects(got, c[@"expected"], @"%@", c[@"name"]);
        XCTAssertLessThanOrEqual([m widthOf:got fontSize:font weight:400], MAX(avail, 0), @"%@", c[@"name"]);
    }
}

// T-GEO-1：两态对齐后并集 U、省略文字，以及 R-GEO-2 iOS 等式
- (void)testGeo1UnionMatchesFixture {
    FixtureMeasurer *m = [self measurer];
    double tolPx = [_fx[@"geometry"][@"tolerancePx"] doubleValue];
    for (NSDictionary *c in _fx[@"geometry"][@"cases"]) {
        NSString *name = c[@"name"];
        double d = [c[@"density"] doubleValue];
        NSString *err = nil;
        AMapNativeMarkerSpec *spec = [AMapNativeMarkerSpec parse:c[@"presentation"] error:&err];
        XCTAssertNotNil(spec, @"%@ %@", name, err);
        AMapNativeMarkerLayout *l = [AMapNativeMarkerLayout layoutWithSpec:spec measurer:m resolver:[NoImages new]];
        NSArray *u = c[@"union"];
        double t = tolPx / d;
        CGRect U = l.unionRect;
        XCTAssertEqualWithAccuracy(CGRectGetMinX(U), [u[0] doubleValue], t, @"%@ left", name);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(U), [u[1] doubleValue], t, @"%@ top", name);
        XCTAssertEqualWithAccuracy(CGRectGetMaxX(U), [u[2] doubleValue], t, @"%@ right", name);
        XCTAssertEqualWithAccuracy(CGRectGetMaxY(U), [u[3] doubleValue], t, @"%@ bottom", name);
        if (c[@"normalText"]) {
            XCTAssertEqualObjects(l.normal.displayText, c[@"normalText"], @"%@", name);
        }
        // 同一夹具的像素化结果与 Android 画布一致
        NSInteger p[4];
        [AMapNativeMarkerLayout pixelize:U density:d out:p];
        XCTAssertEqual(p[0], [c[@"px"] integerValue], @"%@ px", name);
        XCTAssertEqual(p[1], [c[@"py"] integerValue], @"%@ py", name);
        XCTAssertEqual(p[2], [c[@"width"] integerValue], @"%@ W", name);
        XCTAssertEqual(p[3], [c[@"height"] integerValue], @"%@ H", name);
        [self assertGeoPointCoincides:l name:name];
    }
}

/// R-GEO-2 iOS：View 尺寸 = U.size；View 内 (-U.left, -U.top) 落在地理点；两态锚点都映射到这里
- (void)assertGeoPointCoincides:(AMapNativeMarkerLayout *)l name:(NSString *)name {
    CGRect U = l.unionRect;
    CGSize size = l.viewSize;
    XCTAssertEqualWithAccuracy(size.width, CGRectGetWidth(U), 1e-9, @"%@", name);
    XCTAssertEqualWithAccuracy(size.height, CGRectGetHeight(U), 1e-9, @"%@", name);
    // MAAnnotationView 中心落在 坐标 + centerOffset；地理点在 View 内的位置 = 尺寸/2 - centerOffset
    CGPoint off = l.centerOffset;
    CGPoint geo = CGPointMake(size.width / 2 - off.x, size.height / 2 - off.y);
    XCTAssertEqualWithAccuracy(geo.x, -CGRectGetMinX(U), 1e-9, @"%@", name);
    XCTAssertEqualWithAccuracy(geo.y, -CGRectGetMinY(U), 1e-9, @"%@", name);
    for (NSNumber *sel in @[@NO, @YES]) {
        AMapNativeStateLayout *st = [l state:sel.boolValue];
        CGPoint o = [l originForState:sel.boolValue];
        XCTAssertEqualWithAccuracy(st.anchor.x + o.x, geo.x, 1e-9, @"%@", name);
        XCTAssertEqualWithAccuracy(st.anchor.y + o.y, geo.y, 1e-9, @"%@", name);
        // 该状态可见范围完整落在 View 内
        CGRect v = CGRectOffset(st.visible, o.x, o.y);
        XCTAssertTrue(CGRectGetMinX(v) >= -1e-9 && CGRectGetMinY(v) >= -1e-9, @"%@", name);
        XCTAssertTrue(CGRectGetMaxX(v) <= size.width + 1e-9 && CGRectGetMaxY(v) <= size.height + 1e-9, @"%@", name);
    }
}

// T-GEO-3：像素化公式（iOS 不做像素化，这里核对与 Android 同一实现，供截图测试换算）
- (void)testGeo3PixelizationMatchesFixture {
    for (NSDictionary *c in _fx[@"pixelization"][@"cases"]) {
        NSArray *u = c[@"union"];
        CGRect r = CGRectMake([u[0] doubleValue], [u[1] doubleValue],
                              [u[2] doubleValue] - [u[0] doubleValue], [u[3] doubleValue] - [u[1] doubleValue]);
        NSInteger p[4];
        [AMapNativeMarkerLayout pixelize:r density:[c[@"density"] doubleValue] out:p];
        XCTAssertEqual(p[0], [c[@"px"] integerValue], @"%@", c[@"name"]);
        XCTAssertEqual(p[1], [c[@"py"] integerValue], @"%@", c[@"name"]);
        XCTAssertEqual(p[2], [c[@"width"] integerValue], @"%@", c[@"name"]);
        XCTAssertEqual(p[3], [c[@"height"] integerValue], @"%@", c[@"name"]);
    }
}

// R-VAL-10 原生防御：规范化后为 0 的字号、非法字重、圆形带宽度都被拒绝
- (void)testSpecRejectsInvalidAfterNormalization {
    NSDictionary *bg = @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFFFFFFF)};
    NSArray *bad = @[
        @{@"content": @{@"text": @"a"}, @"style": @{@"background": bg, @"fontSize": @0.001}},
        @{@"content": @{@"text": @"a"}, @"style": @{@"background": bg, @"fontWeight": @450}},
        @{@"content": @{@"text": @"a\nb"}, @"style": @{@"background": bg}},
        @{@"content": @{}, @"style": @{@"background": bg}},
        @{@"content": @{@"text": @"a"}, @"style": @{@"background": bg}, @"anchorType": @"arrowTip"},
        @{@"content": @{@"text": @"a"}, @"style": @{@"background": @{@"type": @"shape", @"kind": @"circle",
                                                                       @"diameter": @10, @"fillColor": @1}, @"width": @5}},
    ];
    for (NSDictionary *p in bad) {
        NSString *err = nil;
        XCTAssertNil([AMapNativeMarkerSpec parse:p error:&err], @"%@", p);
        XCTAssertNotNil(err);
    }
}

// T-KEY-3：浮点相差 1e-9 的两份样式 key 相同；T-KEY-5：资源 ready / pending / fallback 的 key 互不相同
- (void)testRenderKeyNormalizedAndResolutionAware {
    NSDictionary *(^p)(double, NSString *) = ^(double w, NSString *img) {
        NSDictionary *bg = img ? @{@"type": @"image", @"imageId": img, @"size": @[@40, @20]}
                               : @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(0xFFFFFFFF)};
        return @{@"content": @{@"text": @"x"}, @"style": @{@"background": bg, @"width": @(w)}};
    };
    NoImages *none = [NoImages new];
    AMapNativeMarkerSpec *a = [AMapNativeMarkerSpec parse:p(0.3, nil) error:nil];
    AMapNativeMarkerSpec *b = [AMapNativeMarkerSpec parse:p(0.1 + 0.2, nil) error:nil];
    XCTAssertEqualObjects(AMapNativeRenderKey(a, 3, none, NO), AMapNativeRenderKey(b, 3, none, NO));
    XCTAssertNotEqualObjects(AMapNativeRenderKey(a, 3, none, NO), AMapNativeRenderKey(a, 3, none, YES));
    XCTAssertNotEqualObjects(AMapNativeRenderKey(a, 3, none, NO), AMapNativeRenderKey(a, 2, none, NO));
}

@end
