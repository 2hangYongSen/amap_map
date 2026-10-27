//
//  AMapDiagSquareView.m
//  amap_map
//

#import "AMapDiagSquareView.h"

@implementation AMapDiagSquareView {
    __weak UIView *_host;
    UIView *_square;
}

- (instancetype)initWithHost:(UIView *)host {
    self = [super init];
    _host = host;
    return self;
}

- (void)showColor:(uint32_t)argb {
    if (_square == nil) {
        UIView *host = _host;
        if (host == nil) {
            return;
        }
        _square = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
        _square.userInteractionEnabled = NO; // 不拦截地图点击
        _square.isAccessibilityElement = NO;
        [host addSubview:_square];
    }
    // ARGB → UIColor
    _square.backgroundColor = [UIColor colorWithRed:((argb >> 16) & 0xFF) / 255.0
                                              green:((argb >> 8) & 0xFF) / 255.0
                                               blue:(argb & 0xFF) / 255.0
                                              alpha:((argb >> 24) & 0xFF) / 255.0];
    _square.hidden = NO;
    [_square.superview bringSubviewToFront:_square];
}

- (void)hide {
    _square.hidden = YES;
}

@end
