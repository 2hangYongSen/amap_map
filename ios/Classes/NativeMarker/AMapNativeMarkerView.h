//
//  AMapNativeMarkerView.h
//  amap_map
//
//  原生点位 View（§10.1）：CAShapeLayer（形状 + shadowPath）、背景 UIImageView、
//  图标 UIImageView、UILabel，全部直接设 frame，不用 Auto Layout。
//  两态共用画布：bounds 固定为 U，切换状态只改子视图（§9.2）。
//

#import <MAMapKit/MAMapKit.h>
#import "AMapNativeMarkerLayout.h"

NS_ASSUME_NONNULL_BEGIN

@class AMapMarker;
@class AMapImageRegistry;

/// 与旧路径 AMapFlutterAnnotationViewIdentifier 分开，两种 View 不会互相复用
extern NSString *const AMapFlutterNativeMarkerViewIdentifier;

/// 字重 400/500/600/700 → systemFontOfSize:weight:（§9.3）
UIFont *AMapNativeFont(double size, NSInteger weight);

/// 平台测量器：UIFont 单行宽度与行高
@interface AMapUIKitTextMeasurer : NSObject <AMapTextMeasurer>
@end

/// 带箭头的连续轮廓（§9.3），与 Android OutlineBuilder.withArrow 同一算法
UIBezierPath *AMapNativeOutlinePath(CGRect body, CGFloat radius, CGPoint tip, CGFloat arrowWidth);

@interface AMapNativeMarkerView : MAAnnotationView

/// R-IOS-1：按完整期望快照设置全部可见属性，不依赖上一次绑定留下的状态
- (void)bindMarker:(AMapMarker *)marker
            layout:(AMapNativeMarkerLayout *)layout
          selected:(BOOL)selected
          registry:(AMapImageRegistry *)registry;

/// 归还显示引用并清空内容（点位删除时调用；复用时由 prepareForReuse 调用）
- (void)unbind;

/// 当前显示引用的资源（R-RES-1 iOS 当前显示）
@property (nonatomic, readonly, copy) NSSet<NSString *> *boundImageIds;
@property (nonatomic, readonly, copy, nullable) NSString *boundMarkerId;

// 测试读取
@property (nonatomic, readonly) CAShapeLayer *shapeLayer;
@property (nonatomic, readonly) CAShapeLayer *arrowLayer;
@property (nonatomic, readonly) UIImageView *shadowImageView;
@property (nonatomic, readonly) UIImageView *backgroundImageView;
@property (nonatomic, readonly) UIImageView *iconImageView;
@property (nonatomic, readonly) UILabel *textLabel;

@end

NS_ASSUME_NONNULL_END
