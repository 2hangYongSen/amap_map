//
//  AMapNativeMarkerLayout.h
//  amap_map
//
//  布局几何（§9.1、§9.2）：纯计算，只读 NormSpec、测量器与资源解析结果。
//  坐标单位为 point（逻辑像素），iOS 不做像素化（§9.2 末条）。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "AMapNativeMarkerSpec.h"

NS_ASSUME_NONNULL_BEGIN

/// 资源解析结果（R-RES-12）：pending 与 failed 都按降级外观绘制，但 key 不同
typedef NS_ENUM(NSInteger, AMapImageResolution) {
    AMapImageResolutionReady = 0,
    AMapImageResolutionPending = 1,
    AMapImageResolutionFallback = 2,
};

/// 文字测量（R-NORM-4）；测试用确定性替身，平台用 UIFont
@protocol AMapTextMeasurer <NSObject>
- (double)widthOf:(NSString *)text fontSize:(double)fontSize weight:(NSInteger)weight;
- (double)lineHeightForFontSize:(double)fontSize weight:(NSInteger)weight;
@end

@protocol AMapImageResolver <NSObject>
- (AMapImageResolution)resolutionOf:(NSString *)imageId;
/// 逻辑尺寸；首次解码完成前返回 NO
- (BOOL)logicalSizeOf:(NSString *)imageId size:(CGSize *)size;
@end

/// 尾部省略（R-ELL-1）：等于不省略；以字形簇截断；avail ≤ 0 或放不下“…”时返回空串
NSString *AMapEllipsize(NSString *_Nullable text, double avail, id<AMapTextMeasurer> m,
                        double fontSize, NSInteger weight);

/// R-VAL-5：左右之和 < 逻辑宽、上下之和 < 逻辑高
BOOL AMapCapInsetsFit(NSArray<NSNumber *> *cap, CGSize logical);

/// 单个状态的布局结果；坐标以该状态 visibleRect 左上角为原点
@interface AMapNativeStateLayout : NSObject
@property (nonatomic, readonly) CGRect body;
@property (nonatomic, readonly) CGRect visible;
@property (nonatomic, readonly) CGPoint anchor;
@property (nonatomic, readonly) BOOL hasArrow;
@property (nonatomic, readonly) CGPoint arrowTip;
/// 省略后的显示文字，空串表示不显示
@property (nonatomic, readonly, copy) NSString *displayText;
@property (nonatomic, readonly) double textWidth;
@property (nonatomic, readonly) BOOL showIcon;
@property (nonatomic, readonly) CGSize iconSize;
/// 图片背景不可用（pending、failed、缺失或九宫格超限），按 R-RES-6 默认背景绘制
@property (nonatomic, readonly) BOOL fallbackBackground;
@end

@interface AMapNativeMarkerLayout : NSObject

+ (instancetype)layoutWithSpec:(AMapNativeMarkerSpec *)spec
                      measurer:(id<AMapTextMeasurer>)m
                      resolver:(id<AMapImageResolver>)r;

@property (nonatomic, readonly) AMapNativeStateLayout *normal;
/// 未设置选中态时与 normal 为同一对象（R-GEO-3）
@property (nonatomic, readonly) AMapNativeStateLayout *selected;
/// 以地理锚点为原点的并集 U（R-GEO-1）
@property (nonatomic, readonly) CGRect unionRect;

- (AMapNativeStateLayout *)state:(BOOL)selected;

/// View 尺寸 = U.size；centerOffset 使 View 内 (-U.left, -U.top) 落在地理点（R-GEO-2 iOS）
- (CGSize)viewSize;
- (CGPoint)centerOffset;

/// 该状态的状态局部坐标 → View 坐标的平移量
- (CGPoint)originForState:(BOOL)selected;

/// R-GEO-2 像素化（与 Android 同一公式，夹具 T-GEO-3）；返回 {px, py, W, H}
+ (void)pixelize:(CGRect)u density:(double)d out:(NSInteger[_Nonnull 4])out;

@end

/// 渲染 key（§9.4）：NormSpec 规范串 + 屏幕 scale + 资源解析结果 + role
NSString *AMapNativeRenderKey(AMapNativeMarkerSpec *spec, double scale, id<AMapImageResolver> r,
                              BOOL selectedRole);

NS_ASSUME_NONNULL_END
