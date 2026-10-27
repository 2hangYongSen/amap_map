//
//  AMapNativeEventLog.m
//  amap_map
//

#import "AMapNativeEventLog.h"

static const NSUInteger kMaxErrors = 64;

@implementation AMapNativeEventLog {
    NSMutableArray<NSDictionary *> *_errors;
    BOOL _open;
    BOOL _closed;
}

- (instancetype)initWithSink:(AMapEventSink)sink {
    self = [super init];
    _sink = [sink copy];
    _errors = [NSMutableArray array];
    return self;
}

- (void)open {
    if (!_closed) {
        _open = YES;
    }
}

- (void)close {
    _closed = YES;
    _open = NO;
    [_errors removeAllObjects];
}

- (void)event:(NSString *)method args:(NSDictionary *)args {
    if (_closed) {
        return;
    }
    NSMutableDictionary *m = [args mutableCopy];
    m[@"eventSeq"] = @(++_lastEventSeq);
    if (_open && _sink) {
        _sink(method, m);
    }
}

- (void)error:(NSString *)code markerId:(NSString *)markerId imageId:(NSString *)imageId message:(NSString *)message {
    if (_closed) {
        return;
    }
    NSDictionary *e = @{
        @"eventSeq": @(++_lastEventSeq),
        @"code": code,
        @"markerId": markerId ?: [NSNull null],
        @"imageId": imageId ?: [NSNull null],
        @"message": message ?: @"",
    };
    [_errors addObject:e];
    if (_errors.count > kMaxErrors) {
        [_errors removeObjectAtIndex:0];
        _errorsDropped++;
    }
#ifdef DEBUG
    NSLog(@"[amap_map] marker#nativeError %@ %@ %@ %@", code, markerId, imageId, message);
#endif
    if (_open && _sink) {
        _sink(@"marker#nativeError", e);
    }
}

- (NSArray<NSDictionary *> *)errorsSnapshot {
    return [_errors copy];
}

@end
