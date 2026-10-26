// S13 旧 icon 路径修复：T-FIX-1（F-1 字节比较）、T-FIX-2（F-2 didAddAnnotationViews）
#import <XCTest/XCTest.h>
#import <Flutter/Flutter.h>
#import <MAMapKit/MAMapKit.h>
#import "AMapConvertUtil.h"
#import "AMapViewController.h"
#import "AMapMarkerController.h"
#import "AMapMarker.h"
#import "MAPointAnnotation+Flutter.h"
#import "MAAnnotationView+Flutter.h"

// 替身：按 id 直接返回预置 marker，不依赖地图和通道
@interface FakeMarkerController : AMapMarkerController
@property (nonatomic, strong) NSDictionary<NSString *, AMapMarker *> *markers;
@end

@implementation FakeMarkerController
- (AMapMarker *)markerForId:(NSString *)markerId {
    return self.markers[markerId];
}
@end

// 记录 updateViewWithMarker: 收到的 marker
@interface CountingAnnotationView : MAAnnotationView
@property (nonatomic, strong) NSMutableArray<AMapMarker *> *updates;
@end

@implementation CountingAnnotationView
- (void)updateViewWithMarker:(AMapMarker *)marker {
    if (self.updates == nil) {
        self.updates = [NSMutableArray array];
    }
    [self.updates addObject:marker];
}
@end

// 非 MAPointAnnotation 的 annotation，用于让第一个 View 不满足条件
@interface PlainAnnotation : NSObject <MAAnnotation>
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@end

@implementation PlainAnnotation
@end

@interface AMapLegacyFixTests : XCTestCase
@end

@implementation AMapLegacyFixTests

static NSArray *BytesIcon(const char *bytes, NSUInteger length) {
    NSData *data = [NSData dataWithBytes:bytes length:length];
    return @[@"fromBytes", [FlutterStandardTypedData typedDataWithBytes:data]];
}

// T-FIX-1：内容不同 → YES；内容相同（不同实例）→ NO
- (void)testFix1BytesIconComparedByContent {
    NSArray *a = BytesIcon("\x01\x02\x03", 3);
    NSArray *sameAsA = BytesIcon("\x01\x02\x03", 3);
    NSArray *b = BytesIcon("\x01\x02\x04", 3);
    NSArray *longer = BytesIcon("\x01\x02\x03\x04", 4);

    XCTAssertFalse([AMapConvertUtil checkIconDescriptionChangedFrom:a to:sameAsA]);
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:a to:b]);
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:a to:longer]);
}

// T-FIX-1 补充：bytes 与 asset 互换、原有字符串/数字比较不变
- (void)testFix1OtherDescriptorsUnchanged {
    NSArray *bytes = BytesIcon("\x01", 1);
    NSArray *asset = @[@"fromAsset", @"assets/start.png"];
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:bytes to:asset]);
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:asset to:bytes]);
    // 宏参数里不能直接写含逗号的数组字面量，先放进局部变量
    NSArray *sameAsset = @[@"fromAsset", @"assets/start.png"];
    NSArray *otherAsset = @[@"fromAsset", @"assets/end.png"];
    XCTAssertFalse([AMapConvertUtil checkIconDescriptionChangedFrom:asset to:sameAsset]);
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:asset to:otherAsset]);
    NSArray *scaled = @[@"fromAssetImage", @"a.png", @2.0];
    NSArray *sameScaled = @[@"fromAssetImage", @"a.png", @2.0];
    NSArray *otherScaled = @[@"fromAssetImage", @"a.png", @3.0];
    XCTAssertFalse([AMapConvertUtil checkIconDescriptionChangedFrom:scaled to:sameScaled]);
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:scaled to:otherScaled]);
}

// T-FIX-1 补充：无法比较的类型强制更新
- (void)testFix1UnknownTypeForcesUpdate {
    NSArray *odd = @[@"custom", @{@"k": @1}];
    NSArray *sameOdd = @[@"custom", @{@"k": @1}];
    XCTAssertTrue([AMapConvertUtil checkIconDescriptionChangedFrom:odd to:sameOdd]);
}

// T-FIX-2：第一个 View 不满足条件（非点标注、无 markerId）时，后续 View 仍各更新一次
- (void)testFix2EveryValidViewUpdatedOnce {
    AMapMarker *m1 = [[AMapMarker alloc] init];
    m1.id_ = @"m1";
    AMapMarker *m2 = [[AMapMarker alloc] init];
    m2.id_ = @"m2";

    // 不走 initWithFrame（需要真实地图与隐私授权），只注入替身控制器
    AMapViewController *vc = [AMapViewController alloc];
    FakeMarkerController *fake = [FakeMarkerController alloc];
    fake.markers = @{@"m1": m1, @"m2": m2};
    [vc setValue:fake forKey:@"markerController"];

    CountingAnnotationView *plain = [[CountingAnnotationView alloc] initWithAnnotation:[PlainAnnotation new]
                                                                       reuseIdentifier:@"t"];
    CountingAnnotationView *noId = [[CountingAnnotationView alloc] initWithAnnotation:[MAPointAnnotation new]
                                                                      reuseIdentifier:@"t"];
    CountingAnnotationView *v1 = [[CountingAnnotationView alloc] initWithAnnotation:m1.annotation
                                                                    reuseIdentifier:@"t"];
    CountingAnnotationView *v2 = [[CountingAnnotationView alloc] initWithAnnotation:m2.annotation
                                                                    reuseIdentifier:@"t"];

    [(id<MAMapViewDelegate>)vc mapView:nil didAddAnnotationViews:@[plain, noId, v1, v2]];

    XCTAssertEqual(plain.updates.count, 0u);
    XCTAssertEqual(noId.updates.count, 0u);
    XCTAssertEqual(v1.updates.count, 1u);
    XCTAssertEqual(v1.updates.firstObject, m1);
    XCTAssertEqual(v2.updates.count, 1u);
    XCTAssertEqual(v2.updates.firstObject, m2);
}

@end
