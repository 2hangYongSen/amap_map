//
//  AMapSelectionState.m
//  amap_map
//

#import "AMapSelectionState.h"

NSString *const AMapSelectionReasonMarkerTap = @"markerTap";
NSString *const AMapSelectionReasonRetap = @"retap";
NSString *const AMapSelectionReasonMapTap = @"mapTap";
NSString *const AMapSelectionReasonApi = @"api";
NSString *const AMapSelectionReasonInvalidated = @"invalidated";

@implementation AMapSelectionChange

- (instancetype)initWithSelected:(NSString *)s previous:(NSString *)p reason:(NSString *)r revision:(NSInteger)rev {
    self = [super init];
    _selectedId = [s copy];
    _previousId = [p copy];
    _reason = [r copy];
    _revision = rev;
    return self;
}

- (NSDictionary *)toMap {
    return @{@"selectedId": _selectedId ?: [NSNull null], @"previousId": _previousId ?: [NSNull null],
             @"reason": _reason, @"revision": @(_revision)};
}

@end

@implementation AMapSelectionState {
    BOOL _deselectOnMapTap;
    BOOL _deselectOnRetap;
}

- (instancetype)init {
    self = [super init];
    _deselectOnMapTap = YES;
    _deselectOnRetap = YES;
    return self;
}

- (void)configure:(id)raw {
    _autoEnabled = [raw isKindOfClass:[NSDictionary class]];
    if (_autoEnabled) {
        // 缺省为 true，只有显式 false 才关闭
        _deselectOnMapTap = ![@NO isEqual:raw[@"deselectOnMapTap"]];
        _deselectOnRetap = ![@NO isEqual:raw[@"deselectOnRetap"]];
    }
}

- (AMapSelectionChange *)set:(NSString *)markerId reason:(NSString *)reason {
    if (markerId == _selectedId || [markerId isEqualToString:_selectedId]) {
        return nil;
    }
    NSString *prev = _selectedId;
    _selectedId = [markerId copy];
    _revision++;
    return [[AMapSelectionChange alloc] initWithSelected:markerId previous:prev reason:reason revision:_revision];
}

- (AMapSelectionChange *)onMarkerTap:(NSString *)markerId selectable:(BOOL)selectable {
    if (!_autoEnabled || !selectable) {
        return nil;
    }
    if (![markerId isEqualToString:_selectedId]) {
        return [self set:markerId reason:AMapSelectionReasonMarkerTap];
    }
    return _deselectOnRetap ? [self set:nil reason:AMapSelectionReasonRetap] : nil;
}

- (AMapSelectionChange *)onMapTap {
    return _autoEnabled && _deselectOnMapTap ? [self set:nil reason:AMapSelectionReasonMapTap] : nil;
}

- (NSDictionary *)snapshot {
    return @{@"selectedId": _selectedId ?: [NSNull null], @"revision": @(_revision)};
}

@end
