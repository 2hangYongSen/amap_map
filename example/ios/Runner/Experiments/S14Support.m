// S14 实验辅助：点位模型、点位 View、取色、配色。
#import "S14ExpHost.h"

static UIColor *rgb(CGFloat r, CGFloat g, CGFloat b) {
  return [UIColor colorWithRed:r / 255 green:g / 255 blue:b / 255 alpha:1];
}
UIColor *S14Red(void) { return rgb(230, 0, 0); }
UIColor *S14Green(void) { return rgb(0, 190, 0); }
UIColor *S14Blue(void) { return rgb(0, 0, 230); }
UIColor *S14Yellow(void) { return rgb(240, 220, 0); }
UIColor *S14Magenta(void) { return rgb(230, 0, 230); }
UIColor *S14Cyan(void) { return rgb(0, 200, 230); }

@implementation S14Anno
@end

// 价格气泡：72×30 圆角矩形 + 底部 10×6 箭头，箭头尖对准坐标
static const CGFloat kBW = 72, kBH = 30, kAH = 6;
static UIBezierPath *bubblePath(void) {
  UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, kBW, kBH) cornerRadius:6];
  [p moveToPoint:CGPointMake(kBW / 2 - 5, kBH)];
  [p addLineToPoint:CGPointMake(kBW / 2, kBH + kAH)];
  [p addLineToPoint:CGPointMake(kBW / 2 + 5, kBH)];
  [p closePath];
  return p;
}

// 旧路径对照：整张预渲染图（含阴影），相当于 Marker.icon 传 PNG
static UIImage *bubbleImage(UIColor *c) {
  static NSMutableDictionary *cache;
  if (!cache) cache = [NSMutableDictionary dictionary];
  UIImage *img = cache[c];
  if (img) return img;
  CGFloat m = 4;  // 阴影留边
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kBW + 2 * m, kBH + kAH + 2 * m)];
  img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    CGContextTranslateCTM(ctx.CGContext, m, m);
    CGContextSetShadowWithColor(ctx.CGContext, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.25].CGColor);
    [c setFill];
    [bubblePath() fill];
    CGContextSetShadowWithColor(ctx.CGContext, CGSizeZero, 0, nil);
    [@"¥123万" drawInRect:CGRectMake(0, 7, kBW, 16)
           withAttributes:@{NSFontAttributeName : [UIFont boldSystemFontOfSize:13],
                            NSForegroundColorAttributeName : UIColor.whiteColor}];
  }];
  cache[c] = img;
  return img;
}

@implementation S14View {
  CAShapeLayer *_shape;
  UILabel *_label;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.hidden = NO;
  self.alpha = 1;
  self.backgroundColor = nil;
  _label.text = nil;
}

- (void)bindAnno:(S14Anno *)a {
  self.isAccessibilityElement = NO;
  self.zIndex = a.z;
  self.hidden = a.startHidden;
  self.canShowCallout = NO;
  if (a.kind == 0) {  // 纯色方块，取色判定用
    self.image = nil;
    _shape.hidden = YES;
    _label.hidden = YES;
    self.bounds = CGRectMake(0, 0, 40, 40);
    self.centerOffset = CGPointZero;
    self.backgroundColor = a.color;
    return;
  }
  self.backgroundColor = nil;
  if (a.kind == 1) {  // 旧路径整图
    _shape.hidden = YES;
    _label.hidden = YES;
    self.image = bubbleImage(a.color);
    self.centerOffset = CGPointMake(0, -(kBH + kAH) / 2);
    return;
  }
  // 2/3/4：形状层 + 文字（新路径的 View 结构）
  self.image = nil;
  self.bounds = CGRectMake(0, 0, kBW, kBH + kAH);
  self.centerOffset = CGPointMake(0, -(kBH + kAH) / 2);
  if (!_shape) {
    _shape = [CAShapeLayer layer];
    _shape.path = bubblePath().CGPath;
    _shape.shadowColor = UIColor.blackColor.CGColor;
    _shape.shadowOpacity = 0.25;
    _shape.shadowRadius = 3;
    _shape.shadowOffset = CGSizeMake(0, 1);
    [self.layer insertSublayer:_shape atIndex:0];
    _label = [[UILabel alloc] initWithFrame:CGRectMake(0, 7, kBW, 16)];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.font = [UIFont boldSystemFontOfSize:13];
    _label.textColor = UIColor.whiteColor;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];
  }
  _shape.hidden = NO;
  _label.hidden = NO;
  _shape.frame = self.bounds;
  _shape.fillColor = a.color.CGColor;
  _shape.shadowPath = (a.kind == 4) ? nil : _shape.path;  // 4 = 无 shadowPath 对照
  _shape.shouldRasterize = (a.kind == 3);
  _shape.rasterizationScale = UIScreen.mainScreen.scale;
  _label.text = @"¥123万";
}
@end

@implementation S14Pixels {
  NSData *_buf;
  size_t _w, _h;
  CGFloat _scale;
}

- (instancetype)initWithImage:(UIImage *)img viewWidth:(CGFloat)vw {
  self = [super init];
  CGImageRef cg = img.CGImage;
  _w = CGImageGetWidth(cg);
  _h = CGImageGetHeight(cg);
  _scale = _w / vw;  // 像素 / 点（截图可能是 1x 或 3x，统一按视图宽度换算）
  NSMutableData *d = [NSMutableData dataWithLength:_w * _h * 4];
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate(d.mutableBytes, _w, _h, 8, _w * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(ctx, CGRectMake(0, 0, _w, _h), cg);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  _buf = d;
  return self;
}

// 最近的实验色（距离 < 70）；否则返回 #rrggbb
- (NSString *)nameAt:(CGPoint)p {
  long x = lround(p.x * _scale), y = lround(p.y * _scale);
  if (x < 0 || y < 0 || x >= (long)_w || y >= (long)_h) return @"out";
  const uint8_t *px = (const uint8_t *)_buf.bytes + (y * _w + x) * 4;
  int r = px[0], g = px[1], b = px[2];
  static int pal[6][3] = {{230, 0, 0}, {0, 190, 0}, {0, 0, 230}, {240, 220, 0}, {230, 0, 230}, {0, 200, 230}};
  static NSString *names[6] = {@"red", @"green", @"blue", @"yellow", @"magenta", @"cyan"};
  for (int i = 0; i < 6; i++) {
    int dr = r - pal[i][0], dg = g - pal[i][1], db = b - pal[i][2];
    if (dr * dr + dg * dg + db * db < 70 * 70) return names[i];
  }
  return [NSString stringWithFormat:@"#%02x%02x%02x", r, g, b];
}
@end
