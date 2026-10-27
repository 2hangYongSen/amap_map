// S14 实验宿主：窗口接管、命令通道、日志、截图、帧计时、地图代理。
#import "S14ExpHost.h"
#import <QuartzCore/QuartzCore.h>

@interface S14ExpHost ()
- (void)touchBegan;
- (void)allUp;
@end

// 拦截触摸：记录按下、全部抬起的时间（在 SDK 手势回调之前记录）
@interface S14Window : UIWindow
@property(nonatomic, weak) S14ExpHost *host;
@end

@implementation S14Window
- (void)sendEvent:(UIEvent *)event {
  if (event.type != UIEventTypeTouches) return [super sendEvent:event];
  BOOL began = NO, allEnded = event.allTouches.count > 0;
  for (UITouch *t in event.allTouches) {
    if (t.phase == UITouchPhaseBegan) began = YES;
    if (t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled) allEnded = NO;
  }
  if (began) [self.host touchBegan];
  if (allEnded) {
    self.host.touchDown = NO;
    self.host.lastTouchUp = CACurrentMediaTime();
  }
  [super sendEvent:event];
  if (allEnded) [self.host allUp];
}
@end

@implementation S14ExpHost {
  UILabel *_cmdLabel;
  UITextView *_logView;
  NSMutableString *_logText;
  CFTimeInterval _t0;
  NSInteger _seq, _ups, _token;
  NSTimeInterval _settle;
  S14Block _pending;
  CADisplayLink *_link;
  NSMutableArray *_frames;
  CFTimeInterval _lastTs;
  BOOL _started;
  BOOL _manual;          // 手动模式：中文提示 + 红圈，由人执行手势
  NSMutableArray<UIView *> *_marks;
}
@synthesize tapEvents = _tapEvents;

+ (BOOL)installIfRequested:(id<UIApplicationDelegate>)delegate {
  NSString *exp = [NSUserDefaults.standardUserDefaults stringForKey:@"S14Exp"];
  if (exp.length == 0) return NO;
  [MAMapView updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];
  [MAMapView updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];
  S14Window *w = [[S14Window alloc] initWithFrame:UIScreen.mainScreen.bounds];
  S14ExpHost *h = [S14ExpHost new];
  h.exp = exp;
  w.host = h;
  w.rootViewController = h;
  [(id)delegate setWindow:w];
  [w makeKeyAndVisible];
  return YES;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  _t0 = CACurrentMediaTime();
  _logText = [NSMutableString string];
  _tapEvents = [NSMutableArray array];
  self.mapView = [[MAMapView alloc] initWithFrame:self.view.bounds];
  self.mapView.delegate = self;
  self.mapView.accessibilityElementsHidden = YES;  // 减少 UI 测试快照开销
  self.mapView.showsCompass = NO;
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(39.909, 116.397) animated:NO];
  [self.mapView setZoomLevel:15 animated:NO];
  [self.view addSubview:self.mapView];
  _cmdLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, 18)];
  _cmdLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
  _cmdLabel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.8];
  _cmdLabel.accessibilityIdentifier = @"s14cmd";
  _cmdLabel.text = @"0|wait";
  [self.view addSubview:_cmdLabel];
  _manual = [NSUserDefaults.standardUserDefaults boolForKey:@"S14Manual"];
  _marks = [NSMutableArray array];
  if (_manual) {  // 手动模式：提示条放大成两行中文，不挡点位区域
    _cmdLabel.frame = CGRectMake(0, 50, self.view.bounds.size.width, 56);
    _cmdLabel.font = [UIFont boldSystemFontOfSize:16];
    _cmdLabel.numberOfLines = 2;
    _cmdLabel.textAlignment = NSTextAlignmentCenter;
    _cmdLabel.text = @"等待地图加载…";
  }
  _logView = [[UITextView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 4, 4, 4)];
  _logView.accessibilityIdentifier = @"s14log";
  _logView.editable = NO;
  [self.view addSubview:_logView];
  [self log:@"exp=%@ sdk=%@ device=%@ iOS=%@ fps=%ld scale=%.2f", self.exp, MAMapKitVersion,
            UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion,
            (long)UIScreen.mainScreen.maximumFramesPerSecond, UIScreen.mainScreen.nativeScale];
  // 地图加载回调兜底：10s 内没回调也开始
  [self after:10 do:^{ [self startExp]; }];
}

- (void)mapViewDidFinishLoadingMap:(MAMapView *)mapView {
  [self after:2 do:^{ [self startExp]; }];
}

- (void)startExp {
  if (_started) return;
  _started = YES;
  SEL sel = NSSelectorFromString([@"run" stringByAppendingString:self.exp]);
  if (![self respondsToSelector:sel]) {
    [self log:@"unknown exp"];
    return [self finish];
  }
  [self log:@"start"];
  ((void (*)(id, SEL))[self methodForSelector:sel])(self, sel);
}

- (void)log:(NSString *)fmt, ... {
  va_list ap;
  va_start(ap, fmt);
  NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);
  NSString *line = [NSString stringWithFormat:@"[%7.0fms] %@", (CACurrentMediaTime() - _t0) * 1000, s];
  [_logText appendFormat:@"%@\n", line];
  NSLog(@"S14 %@", line);
}

- (void)after:(NSTimeInterval)t do:(S14Block)b {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
}

- (void)runSteps:(NSArray<S14Step> *)steps {
  if (steps.count == 0) return;
  S14Step first = steps.firstObject;
  NSArray *rest = [steps subarrayWithRange:NSMakeRange(1, steps.count - 1)];
  first(^{ [self runSteps:rest]; });
}

// ---- 命令通道 ----
- (void)issue:(NSString *)op settle:(NSTimeInterval)settle args:(NSString *)args {
  _seq++;
  if (!_manual) {
    _cmdLabel.text = [NSString stringWithFormat:@"%ld|%@|%.2f|%@", (long)_seq, op, settle, args ?: @""];
    return;
  }
  [self showManual:op args:args ?: @""];
}

// 手动模式：把命令翻译成中文提示，并在要点的位置画红圈、拖动起点画绿圈
- (void)showManual:(NSString *)op args:(NSString *)args {
  for (UIView *m in _marks) [m removeFromSuperview];
  [_marks removeAllObjects];
  NSString *tip;
  if ([op isEqualToString:@"tap"]) {
    NSArray *p = [args componentsSeparatedByString:@","];
    [self mark:CGPointMake([p[0] doubleValue], [p[1] doubleValue]) color:UIColor.redColor];
    tip = [NSString stringWithFormat:@"第 %ld 步：单击红圈中心（只点一下）", (long)_seq];
  } else if ([op isEqualToString:@"swipe"]) {
    NSArray *segs = [[args componentsSeparatedByString:@"|"].lastObject componentsSeparatedByString:@";"];
    NSArray *p = [segs.firstObject componentsSeparatedByString:@","];
    [self mark:CGPointMake([p[0] doubleValue], [p[1] doubleValue]) color:UIColor.greenColor];
    tip = segs.count > 1
              ? [NSString stringWithFormat:@"第 %ld 步：用一根手指来回拖动地图 %lu 次（每次松手）", (long)_seq, (unsigned long)segs.count]
              : [NSString stringWithFormat:@"第 %ld 步：从绿圈慢慢拖动地图一小段后松手", (long)_seq];
  } else if ([op isEqualToString:@"pinch"]) {
    tip = [NSString stringWithFormat:@"第 %ld 步：双指%@地图后松手", (long)_seq, args.doubleValue > 1 ? @"张开放大" : @"捏合缩小"];
  } else if ([op isEqualToString:@"shot"]) {
    tip = @"请保持不动（截图中）";
  } else {
    tip = @"实验结束，可以关闭 App";
  }
  _cmdLabel.text = tip;
  [self log:@"PROMPT %@", tip];
}

- (void)mark:(CGPoint)p color:(UIColor *)c {
  UIView *v = [[UIView alloc] initWithFrame:CGRectMake(p.x - 22, p.y - 22, 44, 44)];
  v.layer.borderColor = c.CGColor;
  v.layer.borderWidth = 3;
  v.layer.cornerRadius = 22;
  v.userInteractionEnabled = NO;  // 不挡点击
  [self.view addSubview:v];
  [_marks addObject:v];
}

- (void)expectUps:(NSInteger)n settle:(NSTimeInterval)settle then:(S14Block)next {
  _ups = n;
  _settle = settle;
  _pending = next;
  NSInteger token = ++_token;
  [self after:(_manual ? 120 : 30) do:^{  // 手动模式给人留足时间
    if (token != self->_token || !self->_pending) return;
    [self log:@"WARN gesture timeout"];
    S14Block b = self->_pending;
    self->_pending = nil;
    b();
  }];
}

- (void)touchBegan {
  self.touchDown = YES;
}

- (void)allUp {
  if (_ups <= 0) return;
  if (--_ups > 0) return;
  S14Block b = _pending;
  _pending = nil;
  _token++;
  if (_manual) {  // 手势完成：去掉圈，提示等待下一步
    for (UIView *m in _marks) [m removeFromSuperview];
    [_marks removeAllObjects];
    _cmdLabel.text = @"已收到，请等待下一步提示…";
  }
  if (b) [self after:_settle do:b];
}

static NSString *pt(CGPoint p) { return [NSString stringWithFormat:@"%.1f,%.1f", p.x, p.y]; }

- (void)awaitTap:(CGPoint)p settle:(NSTimeInterval)settle then:(S14Block)next {
  [_tapEvents removeAllObjects];
  [self expectUps:1 settle:settle then:next];
  [self issue:@"tap" settle:settle args:pt(p)];
}

- (void)awaitSwipes:(NSArray<NSValue *> *)pts velocity:(CGFloat)v settle:(NSTimeInterval)settle then:(S14Block)next {
  NSMutableArray *segs = [NSMutableArray array];
  for (NSUInteger i = 0; i + 1 < pts.count; i += 2) {
    [segs addObject:[NSString stringWithFormat:@"%@,%@", pt(pts[i].CGPointValue), pt(pts[i + 1].CGPointValue)]];
  }
  [self expectUps:segs.count settle:settle then:next];
  [self issue:@"swipe" settle:settle args:[NSString stringWithFormat:@"%.0f|%@", v, [segs componentsJoinedByString:@";"]]];
}

- (void)awaitPinch:(CGFloat)scale settle:(NSTimeInterval)settle then:(S14Block)next {
  [self expectUps:1 settle:settle then:next];
  [self issue:@"pinch" settle:settle args:[NSString stringWithFormat:@"%.2f", scale]];
}

- (void)realShot:(NSString *)name then:(S14Block)next {
  [self issue:@"shot" settle:0 args:name];
  [self after:2.5 do:next];
}

- (void)finish {
  [self log:@"finish"];
  _logView.text = _logText;
  if (_manual) {  // 手动模式：屏幕上直接给出 PASS/FAIL 计数
    NSUInteger pass = 0, fail = 0;
    for (NSString *l in [_logText componentsSeparatedByString:@"\n"]) {
      if ([l containsString:@"] PASS "]) pass++;
      if ([l containsString:@"] FAIL "]) fail++;
    }
    [self after:0.6 do:^{
      self->_cmdLabel.text = [NSString stringWithFormat:@"实验 %@ 结束：PASS %lu，FAIL %lu\n日志已保存，可以关闭 App", self.exp,
                                                       (unsigned long)pass, (unsigned long)fail];
    }];
  }
  NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
      stringByAppendingPathComponent:@"s14"];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  [_logText writeToFile:[dir stringByAppendingFormat:@"/%@.log", self.exp] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  [self after:0.5 do:^{ [self issue:@"done" settle:0 args:nil]; }];
}

// ---- 帧计时：CADisplayLink 相邻回调间隔 ----
- (void)startFrames {
  _frames = [NSMutableArray array];
  _lastTs = 0;
  _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)l {
  if (self.onFrame) self.onFrame(l.timestamp);
  if (_lastTs > 0) {
    BOOL moving = self.touchDown || (CACurrentMediaTime() - self.lastRegionChange < 0.1);
    [_frames addObject:@[ @((l.timestamp - _lastTs) * 1000), @(moving) ]];
  }
  _lastTs = l.timestamp;
}

- (NSArray<NSArray<NSNumber *> *> *)stopFrames {
  [_link invalidate];
  _link = nil;
  return _frames;
}

// 只统计移动中的帧；卡顿帧 = 间隔超过 1.5 个刷新周期
- (NSString *)frameStats:(NSArray<NSArray<NSNumber *> *> *)frames {
  double period = 1000.0 / UIScreen.mainScreen.maximumFramesPerSecond;
  NSMutableArray<NSNumber *> *dts = [NSMutableArray array];
  double total = 0, hitchMs = 0;
  NSInteger hitches = 0;
  for (NSArray<NSNumber *> *f in frames) {
    if (!f[1].boolValue) continue;
    double dt = f[0].doubleValue;
    [dts addObject:@(dt)];
    total += dt;
    if (dt > period * 1.5) {
      hitches++;
      hitchMs += dt - period;
    }
  }
  if (dts.count == 0) return @"moving frames=0";
  [dts sortUsingSelector:@selector(compare:)];
  double p50 = dts[dts.count / 2].doubleValue, p95 = dts[(NSUInteger)(dts.count * 0.95)].doubleValue;
  return [NSString stringWithFormat:@"moving frames=%lu dur=%.0fms fps=%.1f p50=%.1f p95=%.1f max=%.1f hitches=%ld hitchMs/s=%.1f",
                                    (unsigned long)dts.count, total, dts.count * 1000 / total, p50, p95,
                                    dts.lastObject.doubleValue, (long)hitches, hitchMs / (total / 1000)];
}

// ---- 截图与坐标 ----
- (UIImage *)snapshot {
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:self.mapView.bounds];
  return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    [self.mapView drawViewHierarchyInRect:self.mapView.bounds afterScreenUpdates:NO];
  }];
}

- (void)saveImage:(UIImage *)img name:(NSString *)name {
  NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
      stringByAppendingPathComponent:@"s14"];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  [UIImagePNGRepresentation(img) writeToFile:[dir stringByAppendingFormat:@"/%@_%@.png", self.exp, name] atomically:YES];
}

- (CGPoint)pointOf:(CLLocationCoordinate2D)c {
  return [self.mapView convertCoordinate:c toPointToView:self.mapView];
}

- (CLLocationCoordinate2D)coordOf:(CGPoint)p {
  return [self.mapView convertPoint:p toCoordinateFromView:self.mapView];
}

- (S14Anno *)anno:(NSString *)tag at:(CGPoint)p color:(UIColor *)c z:(NSInteger)z kind:(NSInteger)k {
  S14Anno *a = [S14Anno new];
  a.tag = tag;
  a.coordinate = [self coordOf:p];
  a.color = c;
  a.z = z;
  a.kind = k;
  return a;
}

- (MAAnnotationView *)liveViewOf:(id<MAAnnotation>)a {
  MAAnnotationView *v = [self.mapView viewForAnnotation:a];
  if (!v || !v.window || v.hidden || v.annotation != a) return nil;
  return v;
}

- (void)clearAll {
  [self.mapView removeAnnotations:self.mapView.annotations];
}

// ---- 地图代理 ----
- (MAAnnotationView *)mapView:(MAMapView *)mapView viewForAnnotation:(id<MAAnnotation>)annotation {
  if (![annotation isKindOfClass:S14Anno.class]) return nil;
  S14Anno *a = (S14Anno *)annotation;
  self.viewForCount++;
  S14View *v = (S14View *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"S14"];
  if (v) {
    self.dequeueHitCount++;
    self.lastReusedZ = v.zIndex;
    v.annotation = a;
  } else {
    v = [[S14View alloc] initWithAnnotation:a reuseIdentifier:@"S14"];
  }
  [v bindAnno:a];
  v.enabled = !a.disabled;
  if (self.onViewFor) self.onViewFor(a, v);
  return v;
}

- (void)mapView:(MAMapView *)mapView didAddAnnotationViews:(NSArray *)views {
  for (MAAnnotationView *v in views) {
    if (self.onDidAdd && [v.annotation isKindOfClass:S14Anno.class]) self.onDidAdd((S14Anno *)v.annotation, v);
  }
}

- (NSString *)tagOf:(MAAnnotationView *)v {
  return [v.annotation isKindOfClass:S14Anno.class] ? ((S14Anno *)v.annotation).tag : @"?";
}

- (void)record:(NSString *)name {
  double rel = (CACurrentMediaTime() - self.lastTouchUp) * 1000;
  NSString *e = [NSString stringWithFormat:@"%@ %+.0fms%@", name, rel, self.touchDown ? @"(down)" : @""];
  [_tapEvents addObject:e];
  [self log:@"cb %@", e];
}

- (void)mapView:(MAMapView *)mapView didAnnotationViewTapped:(MAAnnotationView *)view {
  [self record:[@"tapped:" stringByAppendingString:[self tagOf:view]]];
}

- (void)mapView:(MAMapView *)mapView didSelectAnnotationView:(MAAnnotationView *)view {
  [self record:[@"select:" stringByAppendingString:[self tagOf:view]]];
}

- (void)mapView:(MAMapView *)mapView didDeselectAnnotationView:(MAAnnotationView *)view {
  [self record:[@"deselect:" stringByAppendingString:[self tagOf:view]]];
}

- (void)mapView:(MAMapView *)mapView didSingleTappedAtCoordinate:(CLLocationCoordinate2D)coordinate {
  [self record:@"mapTap"];
}

- (void)mapView:(MAMapView *)mapView didTouchPois:(NSArray *)pois {
  [self record:[NSString stringWithFormat:@"pois:%lu", (unsigned long)pois.count]];
}

- (void)mapViewRegionChanged:(MAMapView *)mapView {
  self.lastRegionChange = CACurrentMediaTime();
}
@end

@implementation S14ExpHost (Steps)
- (CGPoint)center {
  return CGPointMake(CGRectGetMidX(self.mapView.bounds), CGRectGetMidY(self.mapView.bounds));
}

- (NSString *)colorAt:(CGPoint)p {
  S14Pixels *px = [[S14Pixels alloc] initWithImage:[self snapshot] viewWidth:self.mapView.bounds.size.width];
  return [px nameAt:p];
}

- (S14Step)wait:(NSTimeInterval)t {
  return ^(S14Block next) { [self after:t do:next]; };
}

// 点击后等 0.8s（覆盖双击判定窗口），再记录这次点击触发的全部回调
- (S14Step)tapAt:(CGPoint (^)(void))pt label:(NSString *)label {
  return ^(S14Block next) {
    CGPoint p = pt();
    [self awaitTap:p settle:0.8 then:^{
      [self log:@"TAP %@ at (%.0f,%.0f): %@", label, p.x, p.y,
                self.tapEvents.count ? [self.tapEvents componentsJoinedByString:@", "] : @"(none)"];
      next();
    }];
  };
}

- (S14Step)expectColor:(NSString *)color at:(CGPoint (^)(void))pt label:(NSString *)label {
  return ^(S14Block next) {
    CGPoint p = pt();
    NSString *got = [self colorAt:p];
    [self log:@"%@ %@ at (%.0f,%.0f): want %@ got %@", [got isEqualToString:color] ? @"PASS" : @"FAIL", label, p.x, p.y,
              color, got];
    next();
  };
}

- (S14Step)swipe:(CGPoint)a to:(CGPoint)b {
  return ^(S14Block next) {
    [self awaitSwipes:@[ [NSValue valueWithCGPoint:a], [NSValue valueWithCGPoint:b] ] velocity:300 settle:1.0 then:next];
  };
}

- (S14Step)shot:(NSString *)name {
  return ^(S14Block next) {
    [self saveImage:[self snapshot] name:name];
    [self realShot:name then:next];
  };
}
@end
