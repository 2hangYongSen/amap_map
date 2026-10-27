//
//  AMapNativeMarkerSpec.h
//  amap_map
//
//  规范化规格 NormSpec（§9.0 R-NORM-1）：收到 presentation 后只生成一次，
//  之后校验、渲染 key、布局、绘制都只读它。长度字段已舍入到 1/64 逻辑像素。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AMapNativeBackgroundType) {
    AMapNativeBackgroundCircle = 0,
    AMapNativeBackgroundRect = 1,
    AMapNativeBackgroundImage = 2,
};

typedef NS_ENUM(NSInteger, AMapNativeAnchorType) {
    AMapNativeAnchorBodyCenter = 0,
    AMapNativeAnchorArrowTip = 1,
    AMapNativeAnchorCustom = 2,
};

/// 单个状态的规范化样式；构造时完成 R-VAL-2～4 原生防御性校验（R-VAL-10）
@interface AMapNativeMarkerStyle : NSObject

@property (nonatomic, readonly) AMapNativeBackgroundType bgType;
@property (nonatomic, readonly) double diameter;
@property (nonatomic, readonly) uint32_t fillColor;
@property (nonatomic, readonly) double cornerRadius;
@property (nonatomic, readonly, nullable) NSNumber *borderColor;
@property (nonatomic, readonly) double borderWidth;
@property (nonatomic, readonly, nullable) NSString *imageId;
/// 图片固定尺寸 [w,h]，可空
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *imageSize;
/// 九宫格 [l,t,r,b]，可空
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *capInsets;

@property (nonatomic, readonly) double fontSize;
@property (nonatomic, readonly) NSInteger fontWeight;
@property (nonatomic, readonly) uint32_t textColor;
/// left / center / right
@property (nonatomic, readonly, copy) NSString *textAlign;
/// [l,t,r,b]
@property (nonatomic, readonly) double padL, padT, padR, padB;
@property (nonatomic, readonly, nullable) NSNumber *width, *height, *minWidth, *maxWidth;

@property (nonatomic, readonly) BOOL hasArrow;
@property (nonatomic, readonly) double arrowWidth, arrowHeight;
/// 为空时沿用形状填充色
@property (nonatomic, readonly, nullable) NSNumber *arrowColor;

@property (nonatomic, readonly) BOOL hasShadow;
@property (nonatomic, readonly) uint32_t shadowColor;
@property (nonatomic, readonly) double shadowBlur, shadowDx, shadowDy;

- (BOOL)isImage;

/// 渲染 key 片段（R-KEY-1/3）：只写规范化后的整数单位与字符串
- (void)appendKey:(NSMutableString *)k;

@end

@interface AMapNativeMarkerSpec : NSObject

/// 解析并校验；非法时返回 nil 并给出原因（R-NAT-REJ-1 同步拒绝）
+ (nullable instancetype)parse:(nullable id)presentation error:(NSString *_Nullable *_Nullable)error;

/// 空串视为无文字
@property (nonatomic, readonly, copy, nullable) NSString *text;
@property (nonatomic, readonly, copy, nullable) NSString *iconId;
/// [w,h]，可空（用图片逻辑尺寸）
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *iconSize;
@property (nonatomic, readonly) double iconSpacing;
@property (nonatomic, readonly) AMapNativeMarkerStyle *normal;
/// 为空表示选中态沿用普通态（R-GEO-3）
@property (nonatomic, readonly, nullable) AMapNativeMarkerStyle *selected;
@property (nonatomic, readonly) AMapNativeAnchorType anchorType;
/// custom 锚点（已舍入到 1/1024）；其他类型恒为 0
@property (nonatomic, readonly) double anchorDx, anchorDy;

- (AMapNativeMarkerStyle *)selectedOrNormal;

/// 引用的全部图片资源 id（图标 + 两态背景），有序
- (NSArray<NSString *> *)imageIds;

/// 规范化序列化（R-KEY-3），不含资源解析结果与 role
- (void)appendKey:(NSMutableString *)k;

@end

NS_ASSUME_NONNULL_END
