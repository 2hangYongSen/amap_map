//
//  AMapDiagSquareView.h
//  amap_map
//
//  诊断标记方块（R-TIME-6）：地图左上角 8×8pt 的原生 View，仅诊断模式显示。
//

#import <UIKit/UIKit.h>
#import "AMapMarkerDiagnostics.h"

NS_ASSUME_NONNULL_BEGIN

@interface AMapDiagSquareView : NSObject <AMapDiagnosticsSquare>

/// host 为地图 View（弱引用）；第一次 showColor: 时才把方块加到它上面
- (instancetype)initWithHost:(UIView *)host;

@end

NS_ASSUME_NONNULL_END
