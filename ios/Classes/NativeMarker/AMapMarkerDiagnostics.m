//
//  AMapMarkerDiagnostics.m
//  amap_map
//

#import "AMapMarkerDiagnostics.h"
#import "AMapNativeEventLog.h"
#import <QuartzCore/QuartzCore.h>

static const NSUInteger kMaxTaps = 32;

@interface AMapDiagSync ()
@property (nonatomic, assign) NSInteger syncId;
@property (nonatomic, assign) double t2;
@property (nonatomic, strong, nullable) NSNumber *t2v;
@property (nonatomic, strong, nullable) NSNumber *color;
@property (nonatomic, assign) NSInteger applied;
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger misses0;
@property (nonatomic, assign) NSInteger hits0;
@end

@implementation AMapDiagSync
@end

/// 一次点击：c1 在点击回调里记录
@interface AMapDiagTap : NSObject
@property (nonatomic, assign) NSInteger tapId;
@property (nonatomic, copy) NSString *markerId;
@property (nonatomic, assign) double c1;
/// c1 时的布局未命中计数；c2 时回报差值（iOS 按布局未命中计绘制）
@property (nonatomic, assign) NSInteger misses0;
@end

@implementation AMapDiagTap
@end

@implementation AMapMarkerDiagnostics {
    AMapNativeEventLog *_events;
    NSInteger _tapSeq;
    NSMutableArray<AMapDiagTap *> *_taps;
    /// 当前请求中的 diagTapId（旧路径），只在 begin~end 之间有效
    AMapDiagTap *_requestTap;
}

- (instancetype)initWithEvents:(AMapNativeEventLog *)events {
    self = [super init];
    _events = events;
    _taps = [NSMutableArray array];
    _clock = ^double { return CACurrentMediaTime() * 1000.0; };
    return self;
}

+ (NSArray<NSNumber *> *)palette {
    // 与 Android Diagnostics.PALETTE 一致，录屏中按颜色关联 syncId
    return @[@0xFFFF0000, @0xFF00C853, @0xFF2962FF, @0xFFFFD600,
             @0xFFD500F9, @0xFF00E5FF, @0xFFFF6D00, @0xFF000000];
}

- (double)nowMs {
    return self.clock();
}

- (void)setEnabled:(BOOL)on {
    if (_enabled == on) {
        return;
    }
    _enabled = on;
    if (!on) {
        [_taps removeAllObjects];
        _requestTap = nil;
        [self.square hide];
    }
}

// ---------- 更新回执（R-TIME-4/6） ----------

- (AMapDiagSync *)begin:(NSInteger)syncId args:(id)args {
    if (!_enabled) {
        return nil;
    }
    AMapDiagSync *s = [AMapDiagSync new];
    s.syncId = syncId;
    s.t2 = [self nowMs];
    if (self.square) {
        NSArray *p = [AMapMarkerDiagnostics palette];
        NSInteger i = ((syncId % (NSInteger)p.count) + (NSInteger)p.count) % (NSInteger)p.count;
        s.color = p[i];
        [self.square showColor:(uint32_t)[p[i] unsignedIntValue]];
        s.t2v = @([self nowMs]); // 标记已提交（不等于上屏，R-TIME-6）
    }
    s.bytes = [AMapMarkerDiagnostics countBytes:args];
    s.misses0 = self.layoutMisses;
    s.hits0 = self.layoutHits;
    [self armFromRequest:args];
    return s;
}

- (void)touched:(AMapDiagSync *)sync markerId:(NSString *)markerId isNative:(BOOL)isNative {
    if (sync == nil) {
        return;
    }
    sync.applied++;
    // 旧路径：Dart 重发图标，本次请求中该点 image 已设置即为 c2（R-TIME-7）
    if (_requestTap && [_requestTap.markerId isEqualToString:markerId]) {
        AMapDiagTap *t = _requestTap;
        _requestTap = nil;
        [self finishTap:t path:isNative ? @"native" : @"icon"];
    }
}

- (void)end:(AMapDiagSync *)s {
    _requestTap = nil;
    if (s == nil) {
        return;
    }
    double t4 = [self nowMs]; // 布局与绑定在本次调用内已完成
    double t3 = [self nowMs];
    NSInteger misses = self.layoutMisses - s.misses0;
    NSInteger hits = self.layoutHits - s.hits0;
    NSUInteger decoded = self.decodedBytes ? self.decodedBytes() : 0;
    BOOL decodedOver = self.decodedOverBudget ? self.decodedOverBudget() : NO;
    [_events event:@"markers#applied" args:@{
        @"syncId": @(s.syncId),
        @"nativeT2Ms": @(s.t2),
        @"nativeT2vMs": s.t2v ?: [NSNull null],
        @"markerColor": s.color ?: [NSNull null],
        @"nativeT4Ms": @(t4),
        @"t2ToT3Ms": @(t3 - s.t2),
        @"t2ToT4Ms": @(t4 - s.t2),
        @"appliedCount": @(s.applied),
        @"drawCount": @(misses),
        @"cacheHits": @(hits),
        @"cacheMisses": @(misses),
        @"bytesReceived": @(s.bytes),
        @"pendingTasks": @0,
        @"memory": @{@"compositeBytes": @0, @"decodedBytes": @(decoded),
                     @"compositeOverBudget": @NO, @"decodedOverBudget": @(decodedOver)},
    }];
}

// ---------- 点击计时（R-TIME-2/7） ----------

- (NSNumber *)tapBegin:(NSString *)markerId {
    if (!_enabled) {
        return nil;
    }
    AMapDiagTap *t = [AMapDiagTap new];
    t.tapId = ++_tapSeq;
    t.markerId = markerId;
    t.c1 = [self nowMs];
    t.misses0 = self.layoutMisses;
    [_taps addObject:t];
    if (_taps.count > kMaxTaps) {
        [_taps removeObjectAtIndex:0];
    }
    return @(t.tapId);
}

- (void)tapAppliedNative:(NSNumber *)tapId {
    AMapDiagTap *t = [self tapFor:tapId];
    if (t) {
        [self finishTap:t path:@"native"];
    }
}

- (AMapDiagTap *)tapFor:(id)tapId {
    if (![tapId isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    for (AMapDiagTap *t in _taps) {
        if (t.tapId == [tapId integerValue]) {
            return t;
        }
    }
    return nil;
}

- (void)armFromRequest:(id)args {
    _requestTap = nil;
    id raw = [args isKindOfClass:[NSDictionary class]] ? args[@"diagTapId"] : nil;
    if (![raw isKindOfClass:[NSDictionary class]]) {
        return;
    }
    AMapDiagTap *t = [self tapFor:raw[@"tapId"]];
    if (t && [t.markerId isEqual:raw[@"markerId"]]) {
        _requestTap = t;
    }
}

- (void)finishTap:(AMapDiagTap *)t path:(NSString *)path {
    [_taps removeObject:t];
    [_events event:@"markers#tapApplied" args:@{
        @"tapId": @(t.tapId), @"markerId": t.markerId,
        @"c1Ms": @(t.c1), @"c2Ms": @([self nowMs]), @"path": path,
        @"drawCount": @(self.layoutMisses - t.misses0),
    }];
}

// ---------- 时钟校准（R-TIME-3） ----------

- (NSDictionary *)ping {
    return _enabled ? @{@"nativeMs": @([self nowMs])} : nil;
}

/// 请求中所有字节数据的总长（bytes 资源与旧 fromBytes 图标）
+ (long long)countBytes:(id)obj {
    if ([obj isKindOfClass:[NSData class]]) {
        return (long long)[obj length];
    }
    if ([obj isKindOfClass:NSClassFromString(@"FlutterStandardTypedData")]) {
        return (long long)[[obj valueForKey:@"data"] length];
    }
    long long n = 0;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id v in [obj allValues]) {
            n += [self countBytes:v];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id v in obj) {
            n += [self countBytes:v];
        }
    }
    return n;
}

@end
