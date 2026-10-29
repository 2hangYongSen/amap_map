//
//  AMapNativeMarkerSpec+Private.h
//  amap_map
//
//  解析入口，仅供 NativeMarker 内部使用。
//

#import "AMapNativeMarkerSpec.h"

@class AMapSpecReader;

NS_ASSUME_NONNULL_BEGIN

@interface AMapNativeMarkerStyle ()

- (instancetype)initWithDict:(NSDictionary *)s reader:(AMapSpecReader *)r;

@end

NS_ASSUME_NONNULL_END
