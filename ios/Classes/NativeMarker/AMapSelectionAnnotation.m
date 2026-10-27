//
//  AMapSelectionAnnotation.m
//  amap_map
//

#import "AMapSelectionAnnotation.h"

@implementation AMapSelectionAnnotation

- (instancetype)initWithSource:(NSString *)sourceMarkerId zIndex:(NSInteger)zIndex {
    self = [super init];
    if (self) {
        _sourceMarkerId = [sourceMarkerId copy];
        _zIndex = zIndex;
    }
    return self;
}

@end
