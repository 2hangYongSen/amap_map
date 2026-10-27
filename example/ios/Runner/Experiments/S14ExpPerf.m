// E-I3 200 个带阴影 View 拖动帧率；E-I4 集合替换的视觉表现（R-DEL-6）。
#import "S14ExpHost.h"

@implementation S14ExpHost (ExpPerf)

// n 个点铺满屏幕网格（行列交错），颜色 c，外观 kind；返回点位数组（尚未添加）
- (NSArray<S14Anno *> *)grid:(NSInteger)n color:(UIColor *)c kind:(NSInteger)k shift:(CGFloat)shift tag:(NSString *)tag {
  CGSize s = self.mapView.bounds.size;
  NSInteger cols = 8, rows = (n + cols - 1) / cols;
  NSMutableArray *as = [NSMutableArray array];
  for (NSInteger i = 0; i < n; i++) {
    NSInteger col = i % cols, row = i / cols;
    CGFloat x = (col + 0.5 + ((row % 2) ? 0.25 : -0.25) + shift) * s.width / cols;
    CGFloat y = 80 + (row + 0.5) * (s.height - 120) / rows;
    [as addObject:[self anno:[NSString stringWithFormat:@"%@%ld", tag, (long)i] at:CGPointMake(x, y) color:c z:0 kind:k]];
  }
  return as;
}

// 来回拖动 8 次：左右、上下各 4 次，地图最终回到原位附近
- (NSArray<NSValue *> *)dragPath {
  CGPoint c = self.center;
  NSMutableArray *v = [NSMutableArray array];
  for (NSInteger i = 0; i < 2; i++) {
    [v addObjectsFromArray:@[ [NSValue valueWithCGPoint:CGPointMake(c.x + 120, c.y)], [NSValue valueWithCGPoint:CGPointMake(c.x - 120, c.y)] ]];
    [v addObjectsFromArray:@[ [NSValue valueWithCGPoint:CGPointMake(c.x - 120, c.y)], [NSValue valueWithCGPoint:CGPointMake(c.x + 120, c.y)] ]];
    [v addObjectsFromArray:@[ [NSValue valueWithCGPoint:CGPointMake(c.x, c.y + 200)], [NSValue valueWithCGPoint:CGPointMake(c.x, c.y - 200)] ]];
    [v addObjectsFromArray:@[ [NSValue valueWithCGPoint:CGPointMake(c.x, c.y - 200)], [NSValue valueWithCGPoint:CGPointMake(c.x, c.y + 200)] ]];
  }
  return v;
}

- (void)runI3 {
  __weak S14ExpHost *ws = self;
  NSDictionary *names = @{ @1 : @"legacyImage", @2 : @"shadowPath", @3 : @"shadowPath+raster", @4 : @"noShadowPath" };
  NSMutableArray<S14Step> *steps = [NSMutableArray arrayWithObject:[self wait:1.0]];
  for (NSNumber *k in @[ @1, @2, @3, @4, @1, @2, @3, @4, @1, @2, @3, @4 ]) {
    [steps addObject:^(S14Block n) {
      [ws clearAll];
      [ws.mapView setCenterCoordinate:CLLocationCoordinate2DMake(39.909, 116.397) animated:NO];
      CFTimeInterval t = CACurrentMediaTime();
      [ws.mapView addAnnotations:[ws grid:200 color:S14Red() kind:k.integerValue shift:0 tag:@"p"]];
      [ws log:@"I3 %@ add200=%.1fms", names[k], (CACurrentMediaTime() - t) * 1000];
      [ws after:2.0 do:^{
        [ws startFrames];
        [ws awaitSwipes:[ws dragPath] velocity:900 settle:1.5 then:^{
          [ws log:@"I3 %@ %@ views=%ld", names[k], [ws frameStats:[ws stopFrames]], (long)ws.viewForCount];
          n();
        }];
      }];
    }];
  }
  [steps addObject:[self shot:@"last"]];
  [steps addObject:^(S14Block n) { [ws finish]; }];
  [self runSteps:steps];
}

// 每帧统计可见点数；前 6 帧额外用截图取色确认屏幕上实际是哪一层
- (void)traceReplace:(NSString *)name old:(NSArray<S14Anno *> *)old neu:(NSArray<S14Anno *> *)neu
              action:(S14Block)action then:(S14Block)next {
  __weak S14ExpHost *ws = self;
  __block NSInteger frame = 0;
  __block NSInteger minTotal = NSIntegerMax, minFrame = -1;
  NSMutableArray *trace = [NSMutableArray array];
  NSArray *probe = [neu subarrayWithRange:NSMakeRange(0, MIN(20, neu.count))];
  NSArray *probeOld = [old subarrayWithRange:NSMakeRange(0, MIN(20, old.count))];
  CFTimeInterval t = CACurrentMediaTime();
  action();
  double actMs = (CACurrentMediaTime() - t) * 1000;
  NSInteger syncNew = 0;
  for (S14Anno *a in neu) syncNew += [ws liveViewOf:a] != nil;
  self.onFrame = ^(CFTimeInterval ts) {
    NSInteger o = 0, nn = 0;
    for (S14Anno *a in old) o += [ws liveViewOf:a] != nil;
    for (S14Anno *a in neu) nn += [ws liveViewOf:a] != nil;
    NSString *pix = @"";
    if (frame < 6) {  // 截图取色：新层探针点中显示新色的个数、旧层探针点中显示旧色的个数
      S14Pixels *px = [[S14Pixels alloc] initWithImage:[ws snapshot] viewWidth:ws.mapView.bounds.size.width];
      NSInteger pn = 0, po = 0;
      for (S14Anno *a in probe) pn += [[px nameAt:[ws pointOf:a.coordinate]] isEqualToString:@"green"];
      for (S14Anno *a in probeOld) po += [[px nameAt:[ws pointOf:a.coordinate]] isEqualToString:@"red"];
      pix = [NSString stringWithFormat:@" px(new %ld/20 old %ld/20)", (long)pn, (long)po];
    }
    [trace addObject:[NSString stringWithFormat:@"f%ld old=%ld new=%ld%@", (long)frame, (long)o, (long)nn, pix]];
    if (o + nn < minTotal) {
      minTotal = o + nn;
      minFrame = frame;
    }
    frame++;
  };
  [self startFrames];
  [self after:1.0 do:^{
    ws.onFrame = nil;
    [ws stopFrames];
    [ws log:@"I4 %@ action=%.1fms syncNewLive=%ld/%lu minVisible=%ld@f%ld | %@", name, actMs, (long)syncNew,
            (unsigned long)neu.count, (long)minTotal, (long)minFrame,
            [[trace subarrayWithRange:NSMakeRange(0, MIN(10, trace.count))] componentsJoinedByString:@"; "]];
    next();
  }];
}

- (void)runI4 {
  __weak S14ExpHost *ws = self;
  NSMutableArray<S14Step> *steps = [NSMutableArray arrayWithObject:[self wait:1.0]];
  for (NSNumber *n in @[ @200, @500 ]) {
    for (NSString *mode in @[ @"immediate", @"nextRunloop", @"addThenRemoveSame" ]) {
      for (NSInteger round = 0; round < 3; round++) {
        [steps addObject:^(S14Block next) {
          [ws clearAll];
          NSArray *old = [ws grid:n.integerValue color:S14Red() kind:2 shift:0 tag:@"o"];
          NSArray *neu = [ws grid:n.integerValue color:S14Green() kind:2 shift:0.5 tag:@"n"];
          [ws.mapView addAnnotations:old];
          [ws after:1.5 do:^{
            S14Block act;
            if ([mode isEqualToString:@"immediate"]) {  // 先删后加，同一调用内
              act = ^{
                [ws.mapView removeAnnotations:old];
                [ws.mapView addAnnotations:neu];
              };
            } else if ([mode isEqualToString:@"nextRunloop"]) {  // 先加，下一次 runloop 再删（R-DEL-6 方案）
              act = ^{
                [ws.mapView addAnnotations:neu];
                dispatch_async(dispatch_get_main_queue(), ^{ [ws.mapView removeAnnotations:old]; });
              };
            } else {  // 先加后删，同一调用内
              act = ^{
                [ws.mapView addAnnotations:neu];
                [ws.mapView removeAnnotations:old];
              };
            }
            NSString *name = [NSString stringWithFormat:@"%@ n=%@ r%ld", mode, n, (long)round];
            [ws traceReplace:name old:old neu:neu action:act then:next];
          }];
        }];
      }
    }
  }
  [steps addObject:^(S14Block n) { [ws finish]; }];
  [self runSteps:steps];
}
@end
