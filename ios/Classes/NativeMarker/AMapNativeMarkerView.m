//
//  AMapNativeMarkerView.m
//  amap_map
//

#import "AMapNativeMarkerView.h"
#import "AMapMarker.h"
#import "AMapImageRegistry.h"

NSString *const AMapFlutterNativeMarkerViewIdentifier = @"AMapFlutterNativeMarkerViewIdentifier";

/// R-RES-6 默认背景：白色、圆角 4、1 物理像素 0x1F000000 描边（D-2）
static const uint32_t kFallbackFill = 0xFFFFFFFF;
static const uint32_t kFallbackBorder = 0x1F000000;
static const CGFloat kFallbackRadius = 4;

static UIColor *ARGB(uint32_t c) {
    return [UIColor colorWithRed:((c >> 16) & 0xFF) / 255.0 green:((c >> 8) & 0xFF) / 255.0
                            blue:(c & 0xFF) / 255.0 alpha:((c >> 24) & 0xFF) / 255.0];
}

UIFont *AMapNativeFont(double size, NSInteger weight) {
    UIFontWeight w = weight >= 700 ? UIFontWeightBold : weight >= 600 ? UIFontWeightSemibold
        : weight >= 500 ? UIFontWeightMedium : UIFontWeightRegular;
    return [UIFont systemFontOfSize:size weight:w];
}

@implementation AMapUIKitTextMeasurer {
    NSCache<NSString *, NSNumber *> *_cache;
}

- (instancetype)init {
    self = [super init];
    _cache = [NSCache new];
    _cache.countLimit = 2000;
    return self;
}

/// 测量结果按“文字 + 字号 + 字重”缓存（§4 iOS 设计取舍）
- (double)widthOf:(NSString *)text fontSize:(double)fontSize weight:(NSInteger)weight {
    NSString *key = [NSString stringWithFormat:@"%g|%ld|%@", fontSize, (long)weight, text];
    NSNumber *hit = [_cache objectForKey:key];
    if (hit) {
        return hit.doubleValue;
    }
    CGFloat w = ceil([text sizeWithAttributes:@{NSFontAttributeName: AMapNativeFont(fontSize, weight)}].width);
    [_cache setObject:@(w) forKey:key];
    return w;
}

- (double)lineHeightForFontSize:(double)fontSize weight:(NSInteger)weight {
    return ceil(AMapNativeFont(fontSize, weight).lineHeight);
}

@end

/// 从 a0 到 a1（弧度，屏幕坐标系顺时针为正）追加圆弧
static void Arc(UIBezierPath *p, CGFloat cx, CGFloat cy, CGFloat r, CGFloat a0, CGFloat a1) {
    if (r <= 0 || a1 - a0 <= 1e-9) {
        return;
    }
    [p addArcWithCenter:CGPointMake(cx, cy) radius:r startAngle:a0 endAngle:a1 clockwise:YES];
}

static CGFloat Clamp1(CGFloat v) {
    return MAX(-1, MIN(1, v));
}

static UIBezierPath *BodyPath(CGRect b, CGFloat r) {
    CGFloat x0 = CGRectGetMinX(b), y0 = CGRectGetMinY(b), w = CGRectGetWidth(b), h = CGRectGetHeight(b);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x0 + r, y0)];
    [p addLineToPoint:CGPointMake(x0 + w - r, y0)];
    Arc(p, x0 + w - r, y0 + r, r, 3 * M_PI_2, 2 * M_PI);
    [p addLineToPoint:CGPointMake(x0 + w, y0 + h - r)];
    Arc(p, x0 + w - r, y0 + h - r, r, 0, M_PI_2);
    [p addLineToPoint:CGPointMake(x0 + r, y0 + h)];
    Arc(p, x0 + r, y0 + h - r, r, M_PI_2, M_PI);
    [p addLineToPoint:CGPointMake(x0, y0 + r)];
    Arc(p, x0 + r, y0 + r, r, M_PI, 3 * M_PI_2);
    [p closePath];
    return p;
}

UIBezierPath *AMapNativeOutlinePath(CGRect body, CGFloat r, CGPoint tip, CGFloat arrowW) {
    CGFloat half = arrowW / 2;
    if (half <= 0 || tip.y <= CGRectGetMaxY(body)) {
        return BodyPath(body, r);
    }
    CGFloat x0 = CGRectGetMinX(body), y0 = CGRectGetMinY(body), w = CGRectGetWidth(body), h = CGRectGetHeight(body);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x0 + r, y0)];
    [p addLineToPoint:CGPointMake(x0 + w - r, y0)];
    Arc(p, x0 + w - r, y0 + r, r, 3 * M_PI_2, 2 * M_PI); // 右上角
    [p addLineToPoint:CGPointMake(x0 + w, y0 + h - r)];
    // 右下角弧画到箭头右侧底边点；底边点在直边上时画满整段弧再走直边
    CGFloat xr = MIN(tip.x + half, x0 + w);
    BOOL rightOnArc = xr > x0 + w - r;
    CGFloat tr = rightOnArc ? acos(Clamp1((xr - (x0 + w - r)) / r)) : M_PI_2;
    Arc(p, x0 + w - r, y0 + h - r, r, 0, tr);
    if (!rightOnArc) {
        [p addLineToPoint:CGPointMake(xr, y0 + h)];
    }
    [p addLineToPoint:tip];
    CGFloat xl = MAX(tip.x - half, x0);
    BOOL leftOnArc = xl < x0 + r;
    CGFloat tl = leftOnArc ? acos(Clamp1((xl - (x0 + r)) / r)) : M_PI_2;
    if (!leftOnArc) {
        [p addLineToPoint:CGPointMake(xl, y0 + h)];
        [p addLineToPoint:CGPointMake(x0 + r, y0 + h)];
    } else {
        [p addLineToPoint:CGPointMake(x0 + r + r * cos(tl), y0 + h - r + r * sin(tl))];
    }
    Arc(p, x0 + r, y0 + h - r, r, tl, M_PI); // 左下角
    [p addLineToPoint:CGPointMake(x0, y0 + r)];
    Arc(p, x0 + r, y0 + r, r, M_PI, 3 * M_PI_2); // 左上角
    [p closePath];
    return p;
}

/// 阴影参数：shadowRadius 取 blur/2，与 Android setShadowLayer(blur) 的视觉范围接近
static void ApplyShadow(CALayer *l, AMapNativeMarkerStyle *s, CGPathRef path) {
    if (!s.hasShadow) {
        l.shadowOpacity = 0;
        l.shadowPath = nil;
        return;
    }
    l.shadowColor = ARGB(s.shadowColor).CGColor;
    l.shadowOpacity = 1;
    l.shadowRadius = s.shadowBlur / 2;
    l.shadowOffset = CGSizeMake(s.shadowDx, s.shadowDy);
    // E-I3：必须设置 shadowPath，否则拖动时掉到 20fps 左右
    l.shadowPath = path;
}

@implementation AMapNativeMarkerView {
    __weak AMapImageRegistry *_registry;
    NSSet<NSString *> *_boundImageIds;
    NSString *_boundMarkerId;
}

- (instancetype)initWithAnnotation:(id<MAAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        _boundImageIds = [NSSet set];
        self.canShowCallout = NO;
        _shapeLayer = [CAShapeLayer layer];
        [self.layer addSublayer:_shapeLayer];
        _shadowImageView = [self addImageView];
        _arrowLayer = [CAShapeLayer layer];
        [self.layer addSublayer:_arrowLayer];
        _backgroundImageView = [self addImageView];
        _iconImageView = [self addImageView];
        _textLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel.userInteractionEnabled = NO;
        _textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _textLabel.textAlignment = NSTextAlignmentLeft;
        [self addSubview:_textLabel];
    }
    return self;
}

/// 按添加顺序自下而上叠放：形状层 → 阴影图 → 箭头层 → 背景图 → 图标 → 文字
- (UIImageView *)addImageView {
    UIImageView *v = [[UIImageView alloc] initWithFrame:CGRectZero];
    v.userInteractionEnabled = NO;
    v.contentMode = UIViewContentModeScaleToFill;
    [self addSubview:v];
    return v;
}

- (NSSet<NSString *> *)boundImageIds {
    return _boundImageIds;
}

- (NSString *)boundMarkerId {
    return _boundMarkerId;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self unbind];
}

- (void)dealloc {
    [self releaseDisplayRefs];
}

/// R-IOS-1：清空文字、图片、隐藏状态与资源引用
- (void)unbind {
    [self releaseDisplayRefs];
    _boundMarkerId = nil;
    _textLabel.text = nil;
    _iconImageView.image = nil;
    _backgroundImageView.image = nil;
    _shadowImageView.image = nil;
    self.hidden = NO;
}

- (void)releaseDisplayRefs {
    AMapImageRegistry *reg = _registry;
    for (NSString *id_ in _boundImageIds) {
        [reg unref:id_ kind:AMapImageRefDisplay];
    }
    _boundImageIds = [NSSet set];
}

- (void)bindMarker:(AMapMarker *)marker layout:(AMapNativeMarkerLayout *)layout selected:(BOOL)selected
          registry:(AMapImageRegistry *)registry {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSSet<NSString *> *previous = _boundImageIds;
    AMapImageRegistry *previousRegistry = _registry;
    _registry = registry;
    _boundMarkerId = [marker.id_ copy];
    NSMutableSet<NSString *> *shown = [NSMutableSet set];

    AMapNativeMarkerSpec *spec = marker.spec;
    AMapNativeMarkerStyle *style = selected ? spec.selectedOrNormal : spec.normal;
    AMapNativeStateLayout *st = [layout state:selected];
    CGPoint o = [layout originForState:selected];
    CGSize size = layout.viewSize;
    self.bounds = CGRectMake(0, 0, size.width, size.height);
    self.centerOffset = layout.centerOffset;
    CGRect body = CGRectOffset(st.body, o.x, o.y);
    CGPoint tip = CGPointMake(st.arrowTip.x + o.x, st.arrowTip.y + o.y);

    if (style.isImage && !st.fallbackBackground) {
        [self bindImageBackground:style body:body tip:tip registry:registry shown:shown];
    } else {
        [self bindShapeBackground:style body:body tip:tip];
    }
    [self bindContent:spec style:style state:st body:body registry:registry shown:shown];

    // 先取新引用再还旧引用，同一资源不会在中间被释放；只记录真正取到的引用
    NSMutableSet<NSString *> *held = [NSMutableSet set];
    for (NSString *id_ in shown) {
        if ([registry acquire:id_ kind:AMapImageRefDisplay]) {
            [held addObject:id_];
        }
    }
    for (NSString *id_ in previous) {
        [previousRegistry unref:id_ kind:AMapImageRefDisplay];
    }
    _boundImageIds = [held copy];

    // 其余属性按完整快照设置；zIndex 每次都赋值（R-IOS-2，复用 View 带旧值）
    self.alpha = marker.alpha;
    self.enabled = marker.clickable;
    self.draggable = marker.draggable;
    self.canShowCallout = marker.infoWindowEnable;
    self.zIndex = (NSInteger)marker.zIndex;
    self.hidden = !marker.visible || [self shouldHide:spec registry:registry];
    [CATransaction commit];
}

/// D-5：背景图失败、图标未配置或失败、且没有文字时不显示
- (BOOL)shouldHide:(AMapNativeMarkerSpec *)spec registry:(AMapImageRegistry *)r {
    BOOL bgFailed = spec.normal.isImage && [r resolutionOf:spec.normal.imageId] == AMapImageResolutionFallback;
    BOOL iconGone = spec.iconId == nil || [r resolutionOf:spec.iconId] == AMapImageResolutionFallback;
    return bgFailed && iconGone && spec.text == nil;
}

/// 形状背景或降级默认背景：轮廓 + 箭头一条路径，内描边（D-3），阴影带 shadowPath
- (void)bindShapeBackground:(AMapNativeMarkerStyle *)s body:(CGRect)body tip:(CGPoint)tip {
    BOOL fallback = s.isImage;
    CGFloat scale = UIScreen.mainScreen.scale;
    uint32_t fill = fallback ? kFallbackFill : s.fillColor;
    NSNumber *borderColor = fallback ? @(kFallbackBorder) : s.borderColor;
    CGFloat bw = fallback ? 1 / scale : s.borderWidth;
    CGFloat w = CGRectGetWidth(body), h = CGRectGetHeight(body);
    CGFloat r = s.bgType == AMapNativeBackgroundCircle ? w / 2
        : MAX(0, MIN(fallback ? kFallbackRadius : s.cornerRadius, MIN(w, h) / 2));
    CGFloat inset = borderColor != nil && bw > 0 ? bw / 2 : 0;
    CGRect b = CGRectInset(body, inset, inset);
    CGFloat rr = MAX(0, r - inset);
    CGPoint t = CGPointMake(tip.x, MAX(CGRectGetMaxY(b), tip.y - inset));
    UIBezierPath *path = AMapNativeOutlinePath(b, rr, t, s.hasArrow ? s.arrowWidth : 0);

    _shapeLayer.hidden = NO;
    _shapeLayer.frame = self.bounds;
    _shapeLayer.path = path.CGPath;
    _shapeLayer.fillColor = ARGB(fill).CGColor;
    _shapeLayer.strokeColor = inset > 0 ? ARGB(borderColor.unsignedIntValue).CGColor : nil;
    _shapeLayer.lineWidth = inset > 0 ? bw : 0;
    _shapeLayer.lineJoin = kCALineJoinRound;
    ApplyShadow(_shapeLayer, s, path.CGPath);
    _arrowLayer.hidden = YES;
    _shadowImageView.hidden = YES;
    _backgroundImageView.hidden = YES;
}

/// 图片背景（§9.3）：阴影图 → 箭头三角形（含阴影）→ 图片本体
- (void)bindImageBackground:(AMapNativeMarkerStyle *)s body:(CGRect)body tip:(CGPoint)tip
                   registry:(AMapImageRegistry *)registry shown:(NSMutableSet *)shown {
    UIImage *img = [registry imageFor:s.imageId];
    [shown addObject:s.imageId];
    UIImage *display = img;
    if (s.capInsets) {
        // capInsets 以 point 为单位；解码时 UIImage.scale = pixelRatio，point 即逻辑像素
        UIEdgeInsets e = UIEdgeInsetsMake(s.capInsets[1].doubleValue, s.capInsets[0].doubleValue,
                                          s.capInsets[3].doubleValue, s.capInsets[2].doubleValue);
        display = [img resizableImageWithCapInsets:e resizingMode:UIImageResizingModeStretch];
    }
    _shapeLayer.hidden = YES;
    _backgroundImageView.hidden = NO;
    _backgroundImageView.frame = body;
    _backgroundImageView.image = display;

    if (s.hasShadow) {
        // 阴影跟随图片不透明区域：按图片 alpha 预渲染一张阴影图，同一 View 内不再逐帧计算
        CGFloat ex = s.shadowBlur + fabs(s.shadowDx), ey = s.shadowBlur + fabs(s.shadowDy);
        CGRect frame = CGRectInset(body, -ex, -ey);
        _shadowImageView.hidden = NO;
        _shadowImageView.frame = frame;
        _shadowImageView.image = [self shadowImageFor:display size:body.size inset:CGPointMake(ex, ey) style:s];
    } else {
        _shadowImageView.hidden = YES;
        _shadowImageView.image = nil;
    }

    if (s.hasArrow) {
        // 箭头底边向主体内多伸 1 物理像素，由图片盖住，消除发丝缝
        CGFloat base = CGRectGetMaxY(body) - 1 / UIScreen.mainScreen.scale;
        CGFloat half = s.arrowWidth / 2;
        UIBezierPath *tri = [UIBezierPath bezierPath];
        [tri moveToPoint:CGPointMake(tip.x - half, base)];
        [tri addLineToPoint:CGPointMake(tip.x + half, base)];
        [tri addLineToPoint:tip];
        [tri closePath];
        _arrowLayer.hidden = NO;
        _arrowLayer.frame = self.bounds;
        _arrowLayer.path = tri.CGPath;
        _arrowLayer.fillColor = ARGB(s.arrowColor.unsignedIntValue).CGColor;
        _arrowLayer.strokeColor = nil;
        ApplyShadow(_arrowLayer, s, tri.CGPath);
    } else {
        _arrowLayer.hidden = YES;
    }
}

- (UIImage *)shadowImageFor:(UIImage *)img size:(CGSize)size inset:(CGPoint)inset style:(AMapNativeMarkerStyle *)s {
    CGSize canvas = CGSizeMake(size.width + 2 * inset.x, size.height + 2 * inset.y);
    // 画布倍率必须与图片一致：倍率不同时 drawInRect: 画可拉伸图会把九宫格切错（左右圆角不对称）
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = img.scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:f];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetShadowWithColor(ctx.CGContext, CGSizeMake(s.shadowDx, s.shadowDy), s.shadowBlur,
                                    ARGB(s.shadowColor).CGColor);
        [img drawInRect:CGRectMake(inset.x, inset.y, size.width, size.height)];
    }];
}

/// 内容 = 图标 + 间距 + 文字，整体按 textAlign 水平对齐、在内容区垂直居中（与 Android drawContent 一致）
- (void)bindContent:(AMapNativeMarkerSpec *)spec style:(AMapNativeMarkerStyle *)s state:(AMapNativeStateLayout *)st
               body:(CGRect)body registry:(AMapImageRegistry *)registry shown:(NSMutableSet *)shown {
    BOOL hasText = st.displayText.length > 0;
    double avail = CGRectGetWidth(body) - s.padL - s.padR;
    double tw = hasText ? st.textWidth : 0;
    double iconW = st.showIcon ? st.iconSize.width : 0;
    double gap = st.showIcon && hasText ? spec.iconSpacing : 0;
    double cw = iconW + gap + tw;
    double x = CGRectGetMinX(body) + s.padL;
    if ([s.textAlign isEqualToString:@"center"]) {
        x += (avail - cw) / 2;
    } else if ([s.textAlign isEqualToString:@"right"]) {
        x += avail - cw;
    }
    double centerY = CGRectGetMinY(body) + s.padT + (CGRectGetHeight(body) - s.padT - s.padB) / 2;

    if (st.showIcon) {
        _iconImageView.hidden = NO;
        _iconImageView.image = [registry imageFor:spec.iconId];
        _iconImageView.frame = CGRectMake(x, centerY - st.iconSize.height / 2, iconW, st.iconSize.height);
        [shown addObject:spec.iconId];
    } else {
        _iconImageView.hidden = YES;
        _iconImageView.image = nil;
    }
    if (hasText) {
        UIFont *font = AMapNativeFont(s.fontSize, s.fontWeight);
        _textLabel.hidden = NO;
        _textLabel.font = font;
        _textLabel.textColor = ARGB(s.textColor);
        _textLabel.text = st.displayText;
        // 宽度留 1pt 余量，避免 UILabel 因亚像素取整再次截断已省略好的文字
        _textLabel.frame = CGRectMake(x + iconW + gap, centerY - font.lineHeight / 2, tw + 1, font.lineHeight);
    } else {
        _textLabel.hidden = YES;
        _textLabel.text = nil;
    }
}

@end
