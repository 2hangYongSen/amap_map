//
//  AMapImageRegistry.m
//  amap_map
//

#import "AMapImageRegistry.h"
#import "AMapSpecReader.h"
#import <Flutter/Flutter.h>

static NSString *const kDecodeFailed = @"imageDecodeFailed";

@implementation AMapImageSource

+ (instancetype)parse:(id)raw error:(NSString **)error {
    AMapSpecReader *r = [AMapSpecReader new];
    [r require:[raw isKindOfClass:[NSDictionary class]] message:@"imagesToAdd 项必须是对象"];
    if (r.error) {
        if (error) *error = r.error;
        return nil;
    }
    NSDictionary *m = raw;
    AMapImageSource *s = [self new];
    s->_id_ = [r optString:m key:@"id"];
    [r require:s->_id_.length > 0 message:@"资源缺少 id"];
    id pr = AMapNonNull(m[@"pixelRatio"]);
    s->_pixelRatio = pr == nil ? 1 : [r number:pr path:@"pixelRatio"];
    [r require:s->_pixelRatio > 0 && isfinite(s->_pixelRatio) message:@"pixelRatio 必须大于 0"];
    id type = m[@"type"];
    if ([@"bytes" isEqual:type]) {
        id data = m[@"data"];
        BOOL typed = [data isKindOfClass:[FlutterStandardTypedData class]];
        [r require:typed || [data isKindOfClass:[NSData class]] message:@"bytes 资源缺少 data"];
        s->_type = @"bytes";
        s->_data = typed ? ((FlutterStandardTypedData *)data).data : data;
    } else {
        [r require:[@"asset" isEqual:type] message:[NSString stringWithFormat:@"资源 type 非法: %@", type]];
        s->_type = @"asset";
        s->_asset = [r optString:m key:@"asset"];
        [r require:s->_asset.length > 0 message:@"asset 资源缺少 asset"];
        s->_assetPackage = [r optString:m key:@"package"];
    }
    if (r.error) {
        if (error) *error = r.error;
        return nil;
    }
    return s;
}

+ (instancetype)bytesWithId:(NSString *)id_ data:(NSData *)data pixelRatio:(double)ratio {
    AMapImageSource *s = [self new];
    s->_id_ = [id_ copy];
    s->_type = @"bytes";
    s->_data = data;
    s->_pixelRatio = ratio;
    return s;
}

@end

/// 单个资源条目（§7.1）
@interface AMapImageEntry : NSObject
@property (nonatomic, strong) AMapImageSource *source;
@property (nonatomic) AMapImageState state;
@property (nonatomic, strong, nullable) UIImage *decoded;
/// 首次解码后记录的逻辑尺寸，驱逐后仍可用
@property (nonatomic) CGSize logicalSize;
@property (nonatomic) BOOL sizeKnown;
@property (nonatomic) NSInteger epoch;
@property (nonatomic) BOOL releasing;
@property (nonatomic) NSInteger desiredRefs, displayRefs;
@property (nonatomic) uint64_t lastUsed;
@property (nonatomic, copy, nullable) NSString *failMessage;
@end

@implementation AMapImageEntry
- (NSInteger)totalRefs {
    return _desiredRefs + _displayRefs;
}
@end

@implementation AMapImageRegistry {
    NSMutableDictionary<NSString *, AMapImageEntry *> *_entries;
    AMapImageDecoder _decoder;
    AMapImageRunner _runner;
    NSUInteger _budget;
    NSInteger _nextEpoch;
    NSInteger _decodeCount;
    uint64_t _clock;
    BOOL _disposed;
    BOOL _overBudget;
}

- (instancetype)initWithDecoder:(AMapImageDecoder)decoder runner:(AMapImageRunner)runner budget:(NSUInteger)bytes {
    self = [super init];
    _entries = [NSMutableDictionary dictionary];
    _decoder = [decoder copy];
    _runner = [runner copy];
    _budget = bytes;
    return self;
}

+ (AMapImageRunner)defaultRunner {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("amap_map.native_marker.decode", DISPATCH_QUEUE_SERIAL);
    });
    return ^(dispatch_block_t work, dispatch_block_t done) {
        dispatch_async(queue, ^{
            work();
            dispatch_async(dispatch_get_main_queue(), done);
        });
    };
}

// ---------- 状态机 ----------

- (void)registerSource:(AMapImageSource *)source {
    if (_disposed) {
        return;
    }
    AMapImageEntry *e = _entries[source.id_];
    if (e == nil) {
        e = [AMapImageEntry new];
        e.source = source;
        e.state = AMapImageStatePending;
        _entries[source.id_] = e;
        [self startDecode:e];
        return;
    }
    e.releasing = NO;
    // ready 不重新解码；failed 是重试：回到 pending、换 epoch
    if (e.state == AMapImageStateFailed) {
        e.state = AMapImageStatePending;
        e.source = source;
        [self startDecode:e];
    }
}

- (void)releaseId:(NSString *)imageId {
    AMapImageEntry *e = _entries[imageId];
    if (e) {
        e.releasing = YES;
        [self tryFree:e];
    }
}

- (void)releaseAllExcept:(NSSet<NSString *> *)keep {
    for (NSString *id_ in _entries.allKeys) {
        if (![keep containsObject:id_]) {
            [self releaseId:id_];
        }
    }
}

- (BOOL)acquire:(NSString *)imageId kind:(AMapImageRef)kind {
    AMapImageEntry *e = _entries[imageId];
    if (e == nil) {
        return NO;
    }
    if (kind == AMapImageRefDesired) {
        e.desiredRefs++;
    } else {
        e.displayRefs++;
    }
    e.lastUsed = ++_clock;
    return YES;
}

- (void)unref:(NSString *)imageId kind:(AMapImageRef)kind {
    if (_disposed) {
        return; // 销毁时条目已清空，View 释放时的归还直接忽略
    }
    AMapImageEntry *e = _entries[imageId];
    NSInteger current = kind == AMapImageRefDesired ? e.desiredRefs : e.displayRefs;
    NSAssert(e != nil && current > 0, @"资源引用不成对: %@ %ld", imageId, (long)kind);
    if (e == nil || current == 0) {
        return;
    }
    if (kind == AMapImageRefDesired) {
        e.desiredRefs--;
    } else {
        e.displayRefs--;
    }
    if (![self tryFree:e]) {
        [self enforceBudget];
    }
}

- (void)startDecode:(AMapImageEntry *)e {
    NSInteger epoch = ++_nextEpoch;
    e.epoch = epoch;
    _decodeCount++;
    AMapImageSource *src = e.source;
    AMapImageDecoder decoder = _decoder;
    __block UIImage *img = nil;
    __block NSString *err = nil;
    __weak typeof(self) weakSelf = self;
    _runner(^{
        NSString *msg = nil;
        @try {
            img = decoder(src, &msg);
        } @catch (NSException *ex) {
            img = nil;
            msg = ex.reason;
        }
        err = msg;
    }, ^{
        [weakSelf onDecoded:src.id_ epoch:epoch image:img error:err];
    });
}

- (void)onDecoded:(NSString *)imageId epoch:(NSInteger)epoch image:(UIImage *)img error:(NSString *)err {
    AMapImageEntry *e = _entries[imageId];
    // 已释放、已销毁或 epoch 变化：结果过期，丢弃
    if (_disposed || e == nil || e.epoch != epoch) {
        return;
    }
    if (img == nil) {
        e.state = AMapImageStateFailed;
        e.failMessage = err ?: @"解码结果为空";
    } else {
        e.decoded = img;
        e.logicalSize = [self logicalSizeOfImage:img ratio:e.source.pixelRatio];
        e.sizeKnown = YES;
        e.state = AMapImageStateReady;
        e.lastUsed = ++_clock;
    }
    [self.listener imageRegistryDidResolve:imageId];
    if (![self tryFree:e]) {
        [self enforceBudget];
    }
}

/// 逻辑尺寸 = 像素 / pixelRatio
- (CGSize)logicalSizeOfImage:(UIImage *)img ratio:(double)ratio {
    CGFloat px = img.size.width * img.scale, py = img.size.height * img.scale;
    return CGSizeMake(px / ratio, py / ratio);
}

/// R-RES-10：releasing 且 refs == 0 才移除；UIImage 由 ARC 管理
- (BOOL)tryFree:(AMapImageEntry *)e {
    if (!e.releasing || e.totalRefs > 0) {
        return NO;
    }
    [_entries removeObjectForKey:e.source.id_];
    e.decoded = nil;
    e.epoch = -1;
    return YES;
}

static NSUInteger ByteSize(UIImage *img) {
    return (NSUInteger)(img.size.width * img.size.height * 4 * img.scale * img.scale);
}

/// R-RES-11：超预算时按 LRU 淘汰没有 View 显示的解码结果，状态保持 ready
- (void)enforceBudget {
    NSUInteger total = self.decodedBytes;
    if (total > _budget) {
        NSArray<AMapImageEntry *> *candidates = [[_entries.allValues filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(AMapImageEntry *e, id b) {
                return e.state == AMapImageStateReady && e.decoded && !e.releasing && e.displayRefs == 0;
            }]] sortedArrayUsingComparator:^NSComparisonResult(AMapImageEntry *a, AMapImageEntry *b) {
                return a.lastUsed < b.lastUsed ? NSOrderedAscending : (a.lastUsed > b.lastUsed ? NSOrderedDescending : NSOrderedSame);
            }];
        for (AMapImageEntry *e in candidates) {
            if (total <= _budget) {
                break;
            }
            total -= ByteSize(e.decoded);
            e.decoded = nil;
        }
    }
    _overBudget = total > _budget;
}

- (void)dispose {
    _disposed = YES;
    [_entries removeAllObjects];
}

// ---------- 查询 ----------

- (UIImage *)imageFor:(NSString *)imageId {
    AMapImageEntry *e = _entries[imageId];
    if (e == nil || e.state != AMapImageStateReady) {
        return nil;
    }
    e.lastUsed = ++_clock;
    if (e.decoded == nil) {
        // 已被淘汰：从保留的原始数据同步重新解码，不找 Dart（R-RES-11）
        NSString *err = nil;
        _decodeCount++;
        e.decoded = _decoder(e.source, &err);
    }
    return e.decoded;
}

- (AMapImageResolution)resolutionOf:(NSString *)imageId {
    AMapImageEntry *e = _entries[imageId];
    if (e == nil || e.state == AMapImageStateFailed) {
        return AMapImageResolutionFallback;
    }
    return e.state == AMapImageStateReady ? AMapImageResolutionReady : AMapImageResolutionPending;
}

- (BOOL)logicalSizeOf:(NSString *)imageId size:(CGSize *)size {
    AMapImageEntry *e = _entries[imageId];
    if (e == nil || !e.sizeKnown) {
        return NO;
    }
    *size = e.logicalSize;
    return YES;
}

- (BOOL)contains:(NSString *)imageId {
    return _entries[imageId] != nil;
}

- (AMapImageState)stateOf:(NSString *)imageId {
    return _entries[imageId].state;
}

- (NSInteger)refsOf:(NSString *)imageId kind:(AMapImageRef)kind {
    AMapImageEntry *e = _entries[imageId];
    return kind == AMapImageRefDesired ? e.desiredRefs : e.displayRefs;
}

- (NSDictionary *)failureOf:(NSString *)imageId {
    AMapImageEntry *e = _entries[imageId];
    if (e.state != AMapImageStateFailed) {
        return nil;
    }
    return @{@"id": imageId, @"code": kDecodeFailed, @"message": e.failMessage ?: @""};
}

- (NSUInteger)count {
    return _entries.count;
}

- (NSInteger)decodeCount {
    return _decodeCount;
}

- (NSUInteger)decodedBytes {
    NSUInteger sum = 0;
    for (AMapImageEntry *e in _entries.allValues) {
        if (e.decoded) sum += ByteSize(e.decoded);
    }
    return sum;
}

- (BOOL)decodedOverBudget {
    return _overBudget;
}

- (NSDictionary *)snapshot {
    NSMutableArray *ready = [NSMutableArray array], *failed = [NSMutableArray array], *pending = [NSMutableArray array];
    for (NSString *id_ in _entries) {
        AMapImageEntry *e = _entries[id_];
        if (e.releasing) continue;
        if (e.state == AMapImageStateReady) {
            [ready addObject:id_];
        } else if (e.state == AMapImageStatePending) {
            [pending addObject:id_];
        } else {
            [failed addObject:[self failureOf:id_]];
        }
    }
    return @{@"ready": ready, @"failed": failed, @"pending": pending};
}

- (NSArray<NSString *> *)pendingIds {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *id_ in _entries) {
        AMapImageEntry *e = _entries[id_];
        if (!e.releasing && e.state == AMapImageStatePending) [out addObject:id_];
    }
    return out;
}

@end
