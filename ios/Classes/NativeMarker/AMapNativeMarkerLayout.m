//
//  AMapNativeMarkerLayout.m
//  amap_map
//
//  与 Android StateLayout / NativeMarkerLayout / Ellipsizer 同一算法，三端共用夹具。
//

#import "AMapNativeMarkerLayout.h"
#import "AMapSpecReader.h"

static NSString *const kEllipsis = @"\u2026";
/// 抵消浮点噪声，与 Android CEIL_EPS 一致
static const double kCeilEps = 1e-9;

NSString *AMapEllipsize(NSString *text, double avail, id<AMapTextMeasurer> m, double fontSize, NSInteger weight) {
    if (text.length == 0 || avail <= 0) {
        return @"";
    }
    if ([m widthOf:text fontSize:fontSize weight:weight] <= avail) {
        return text;
    }
    // 字形簇的结束位置（不含整串），从长到短尝试，不拆代理对与组合字符
    NSMutableArray<NSNumber *> *bounds = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
                          usingBlock:^(NSString *s, NSRange r, NSRange er, BOOL *stop) {
        NSUInteger end = NSMaxRange(r);
        if (end < text.length) {
            [bounds addObject:@(end)];
        }
    }];
    for (NSNumber *b in bounds.reverseObjectEnumerator) {
        NSString *candidate = [[text substringToIndex:b.unsignedIntegerValue] stringByAppendingString:kEllipsis];
        if ([m widthOf:candidate fontSize:fontSize weight:weight] <= avail) {
            return candidate;
        }
    }
    return @"";
}

BOOL AMapCapInsetsFit(NSArray<NSNumber *> *cap, CGSize logical) {
    return cap[0].doubleValue + cap[2].doubleValue < logical.width
        && cap[1].doubleValue + cap[3].doubleValue < logical.height;
}

static double Clamp(double v, NSNumber *min, NSNumber *max) {
    if (min) v = MAX(v, min.doubleValue);
    if (max) v = MIN(v, max.doubleValue);
    return v;
}

/// 图片背景是否按默认背景显示：未 ready（pending / failed / 缺失）或九宫格超限（R-NAT-REJ-2）
static BOOL BackgroundFallback(AMapNativeMarkerStyle *s, id<AMapImageResolver> r) {
    if (!s.isImage) {
        return NO;
    }
    if ([r resolutionOf:s.imageId] != AMapImageResolutionReady) {
        return YES;
    }
    CGSize size;
    return s.capInsets != nil && [r logicalSizeOf:s.imageId size:&size] && !AMapCapInsetsFit(s.capInsets, size);
}

@interface AMapNativeStateLayout ()
@property (nonatomic, readwrite) CGRect body, visible;
@property (nonatomic, readwrite) CGPoint anchor, arrowTip;
@property (nonatomic, readwrite) BOOL hasArrow, showIcon, fallbackBackground;
@property (nonatomic, readwrite, copy) NSString *displayText;
@property (nonatomic, readwrite) double textWidth;
@property (nonatomic, readwrite) CGSize iconSize;
@end

@implementation AMapNativeStateLayout

/// §9.1 layoutState
+ (instancetype)computeSpec:(AMapNativeMarkerSpec *)spec style:(AMapNativeMarkerStyle *)s
                   measurer:(id<AMapTextMeasurer>)m resolver:(id<AMapImageResolver>)r {
    AMapNativeStateLayout *l = [self new];
    double font = s.fontSize;
    // 1. 内容尺寸：只有 ready 的图标参与（pending / failed 先省略，R-RES-5/6）
    BOOL showIcon = spec.iconId != nil && [r resolutionOf:spec.iconId] == AMapImageResolutionReady;
    CGSize icon = CGSizeZero;
    if (showIcon) {
        if (spec.iconSize) {
            icon = CGSizeMake(spec.iconSize[0].doubleValue, spec.iconSize[1].doubleValue);
        } else if (![r logicalSizeOf:spec.iconId size:&icon]) {
            icon = CGSizeZero;
        }
    }
    BOOL hasText = spec.text != nil;
    double gap = showIcon && hasText ? spec.iconSpacing : 0;
    double textW = hasText ? [m widthOf:spec.text fontSize:font weight:s.fontWeight] : 0;
    double textH = hasText ? [m lineHeightForFontSize:font weight:s.fontWeight] : 0;
    double contentW = icon.width + gap + textW;
    double contentH = MAX(icon.height, textH);

    // 2. 主体尺寸
    BOOL fallback = BackgroundFallback(s, r);
    double bw, bh;
    CGSize imgSize;
    if (s.bgType == AMapNativeBackgroundCircle) {
        bw = bh = s.diameter;
    } else if (s.isImage && s.imageSize) {
        // 固定尺寸；降级时也保持尺寸，避免布局跳动
        bw = s.imageSize[0].doubleValue;
        bh = s.imageSize[1].doubleValue;
    } else if (s.isImage && s.capInsets == nil && !fallback) {
        BOOL known = [r logicalSizeOf:s.imageId size:&imgSize];
        bw = known ? imgSize.width : 0;
        bh = known ? imgSize.height : 0;
    } else {
        // 圆角矩形规则（含九宫格与降级默认背景）
        bw = s.width ? s.width.doubleValue : Clamp(contentW + s.padL + s.padR, s.minWidth, s.maxWidth);
        bh = s.height ? s.height.doubleValue : contentH + s.padT + s.padB;
    }
    // R-ELL-1
    double avail = bw - s.padL - s.padR - (icon.width + gap);
    NSString *text = hasText ? AMapEllipsize(spec.text, avail, m, font, s.fontWeight) : @"";

    // 3. 箭头：主体底部中点下方
    CGRect body = CGRectMake(0, 0, bw, bh);
    double tipX = bw / 2;
    double tipY = bh + (s.hasArrow ? s.arrowHeight : 0);
    CGRect visible = body;
    if (s.hasArrow) {
        double half = s.arrowWidth / 2;
        visible = CGRectUnion(visible, CGRectMake(tipX - half, bh, s.arrowWidth, tipY - bh));
    }
    // 4. 阴影扩边：只扩大可见范围，不移动主体
    if (s.hasShadow) {
        visible = CGRectInset(visible, -(s.shadowBlur + fabs(s.shadowDx)), -(s.shadowBlur + fabs(s.shadowDy)));
    }
    // 5. 状态内锚点；无箭头时 tipY == bh，即主体底边中点（R-ANC-2）
    CGPoint a;
    if (spec.anchorType == AMapNativeAnchorCustom) {
        a = CGPointMake(bw * spec.anchorDx, bh * spec.anchorDy);
    } else if (spec.anchorType == AMapNativeAnchorArrowTip) {
        a = CGPointMake(tipX, tipY);
    } else {
        a = CGPointMake(bw / 2, bh / 2);
    }
    // 6. 平移到 visibleRect 左上角为原点
    double ox = -visible.origin.x, oy = -visible.origin.y;
    l.body = CGRectOffset(body, ox, oy);
    l.visible = CGRectOffset(visible, ox, oy);
    l.anchor = CGPointMake(a.x + ox, a.y + oy);
    l.hasArrow = s.hasArrow;
    l.arrowTip = CGPointMake(tipX + ox, tipY + oy);
    l.displayText = text;
    l.textWidth = text.length ? [m widthOf:text fontSize:font weight:s.fontWeight] : 0;
    l.showIcon = showIcon;
    l.iconSize = icon;
    l.fallbackBackground = fallback;
    return l;
}

/// 平移 -a 后的可见范围（以地理锚点为原点，R-GEO-1）
- (CGRect)alignedVisible {
    return CGRectOffset(_visible, -_anchor.x, -_anchor.y);
}

@end

@implementation AMapNativeMarkerLayout

+ (instancetype)layoutWithSpec:(AMapNativeMarkerSpec *)spec measurer:(id<AMapTextMeasurer>)m
                      resolver:(id<AMapImageResolver>)r {
    AMapNativeMarkerLayout *l = [self new];
    l->_normal = [AMapNativeStateLayout computeSpec:spec style:spec.normal measurer:m resolver:r];
    l->_selected = spec.selected == nil ? l->_normal
        : [AMapNativeStateLayout computeSpec:spec style:spec.selected measurer:m resolver:r];
    l->_unionRect = CGRectUnion([l->_normal alignedVisible], [l->_selected alignedVisible]);
    return l;
}

- (AMapNativeStateLayout *)state:(BOOL)selected {
    return selected ? _selected : _normal;
}

- (CGSize)viewSize {
    return _unionRect.size;
}

- (CGPoint)centerOffset {
    return CGPointMake(CGRectGetWidth(_unionRect) / 2 + CGRectGetMinX(_unionRect),
                       CGRectGetHeight(_unionRect) / 2 + CGRectGetMinY(_unionRect));
}

- (CGPoint)originForState:(BOOL)selected {
    // View 内地理点在 (-U.left, -U.top)，状态局部锚点 a 对齐到这里
    AMapNativeStateLayout *st = [self state:selected];
    return CGPointMake(-CGRectGetMinX(_unionRect) - st.anchor.x, -CGRectGetMinY(_unionRect) - st.anchor.y);
}

static NSInteger CeilEps(double v) {
    return (NSInteger)ceil(v - kCeilEps);
}

+ (void)pixelize:(CGRect)u density:(double)d out:(NSInteger[4])out {
    NSInteger px = CeilEps(-CGRectGetMinX(u) * d);
    NSInteger py = CeilEps(-CGRectGetMinY(u) * d);
    out[0] = px;
    out[1] = py;
    out[2] = MAX(1, px + CeilEps(CGRectGetMaxX(u) * d));
    out[3] = MAX(1, py + CeilEps(CGRectGetMaxY(u) * d));
}

@end

NSString *AMapNativeRenderKey(AMapNativeMarkerSpec *spec, double scale, id<AMapImageResolver> r, BOOL selectedRole) {
    NSMutableString *k = [NSMutableString stringWithString:@"v1|"];
    [spec appendKey:k];
    int32_t density = 0;
    AMapNormUnits(scale, AMapNormRatioScale, &density);
    [k appendFormat:@"density|%d|images|", density];
    // 资源 ID + 解析结果（R-RES-12）：ready / pending / fallback 互不命中
    static NSString *const names[] = {@"ready", @"pending", @"fallback"};
    for (NSString *id_ in spec.imageIds) {
        [k appendFormat:@"%lu:%@=%@|", (unsigned long)id_.length, id_, names[[r resolutionOf:id_]]];
    }
    [k appendString:selectedRole ? @"role|selected" : @"role|normal"];
    return k;
}
