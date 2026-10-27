// E-I0 运行时核对 zIndex；E-X1 takeSnapshot 是否包含 Annotation View。
#import "S14ExpHost.h"

@implementation S14ExpHost (ExpZ)

// 两个 40×40 方块放在同一坐标：先加绿色（高 z），后加红色（低 z）。
// 若 zIndex 无效，后加的红色在上。中心取色判断谁在上。
- (NSArray<S14Anno *> *)pair:(NSString *)tag at:(CGPoint)p redZ:(NSInteger)rz greenZ:(NSInteger)gz {
  S14Anno *g = [self anno:[tag stringByAppendingString:@"g"] at:p color:S14Green() z:gz kind:0];
  S14Anno *r = [self anno:[tag stringByAppendingString:@"r"] at:p color:S14Red() z:rz kind:0];
  [self.mapView addAnnotation:g];
  [self.mapView addAnnotation:r];
  return @[ r, g ];
}

- (void)runI0 {
  NSMutableDictionary<NSString *, S14Anno *> *red = [NSMutableDictionary dictionary];
  // P0 默认 z（都为 0）；P1 viewFor 设 z；P2 viewFor 设 5、didAdd 改 1；P3 运行中改 zIndex；
  // P4 运行中 bringSubviewToFront；P5 运行中改 layer.zPosition
  NSDictionary<NSString *, NSValue *> *pos = @{
    @"P0" : [NSValue valueWithCGPoint:CGPointMake(110, 220)], @"P1" : [NSValue valueWithCGPoint:CGPointMake(265, 220)],
    @"P2" : [NSValue valueWithCGPoint:CGPointMake(110, 380)], @"P3" : [NSValue valueWithCGPoint:CGPointMake(265, 380)],
    @"P4" : [NSValue valueWithCGPoint:CGPointMake(110, 540)], @"P5" : [NSValue valueWithCGPoint:CGPointMake(265, 540)],
  };
  __weak S14ExpHost *ws = self;
  self.onDidAdd = ^(S14Anno *a, MAAnnotationView *v) {
    if ([a.tag isEqualToString:@"P2r"]) v.zIndex = 1;  // didAdd 中把 5 改为 1，绿色 3 应在上
  };
  red[@"P0"] = [self pair:@"P0" at:pos[@"P0"].CGPointValue redZ:0 greenZ:0][0];
  red[@"P1"] = [self pair:@"P1" at:pos[@"P1"].CGPointValue redZ:1 greenZ:2][0];
  red[@"P2"] = [self pair:@"P2" at:pos[@"P2"].CGPointValue redZ:5 greenZ:3][0];
  red[@"P3"] = [self pair:@"P3" at:pos[@"P3"].CGPointValue redZ:1 greenZ:2][0];
  red[@"P4"] = [self pair:@"P4" at:pos[@"P4"].CGPointValue redZ:1 greenZ:2][0];
  red[@"P5"] = [self pair:@"P5" at:pos[@"P5"].CGPointValue redZ:1 greenZ:2][0];
  CGPoint (^at)(NSString *) = ^CGPoint(NSString *k) { return [ws pointOf:red[k].coordinate]; };
  void (^check)(NSString *) = ^(NSString *stage) {
    for (NSString *k in @[ @"P0", @"P1", @"P2", @"P3", @"P4", @"P5" ]) {
      MAAnnotationView *v = [ws.mapView viewForAnnotation:red[k]];
      CGPoint p = at(k);
      [ws log:@"%@ %@ (%.0f,%.0f) top=%@ redView.zIndex=%ld zPos=%.0f", stage, k, p.x, p.y, [ws colorAt:p],
              (long)v.zIndex, v.layer.zPosition];
    }
  };
  [self runSteps:@[
    [self wait:1.5], ^(S14Block n) { check(@"init"); n(); },
    ^(S14Block n) {  // 运行中修改：P3 zIndex=10，P4 移到最前，P5 zPosition=10
      MAAnnotationView *v3 = [ws.mapView viewForAnnotation:red[@"P3"]];
      MAAnnotationView *v4 = [ws.mapView viewForAnnotation:red[@"P4"]];
      MAAnnotationView *v5 = [ws.mapView viewForAnnotation:red[@"P5"]];
      v3.zIndex = 10;
      [v4.superview bringSubviewToFront:v4];
      v5.layer.zPosition = 10;
      [ws log:@"runtime changed; v3.superview=%@ v4.superview=%@", NSStringFromClass(v3.superview.class),
              NSStringFromClass(v4.superview.class)];
      n();
    },
    [self wait:0.6], ^(S14Block n) { check(@"runtime+0.6s"); n(); },
    ^(S14Block n) {  // 再加一个点，看 SDK 是否按 zIndex 重新排序（会不会冲掉 P4 的 bringSubviewToFront）
      [ws.mapView addAnnotation:[ws anno:@"extra" at:CGPointMake(190, 700) color:S14Blue() z:0 kind:0]];
      n();
    },
    [self wait:0.6], ^(S14Block n) { check(@"afterAdd"); n(); },
    [self swipe:CGPointMake(190, 760) to:CGPointMake(170, 740)], ^(S14Block n) { check(@"afterPan"); n(); },
    ^(S14Block n) {  // 缩放：程序设置，保持中心不变
      [ws.mapView setZoomLevel:ws.mapView.zoomLevel + 0.5 animated:YES];
      [ws after:1.5 do:n];
    },
    ^(S14Block n) { check(@"afterZoom"); n(); },
    [self shot:@"after"],
    ^(S14Block n) {  // 复用：相机移远让全部点离屏，再加一个点，看是否从复用池取出、取出时 zIndex 残留多少
      NSInteger before = ws.dequeueHitCount;
      CLLocationCoordinate2D far = [ws coordOf:CGPointMake(ws.center.x + 3000, ws.center.y)];
      [ws.mapView setCenterCoordinate:far animated:NO];
      [ws after:1.0 do:^{
        NSInteger alive = 0;
        for (NSString *k in red) alive += [ws.mapView viewForAnnotation:red[k]] != nil;
        S14Anno *x = [ws anno:@"X" at:ws.center color:S14Blue() z:7 kind:0];
        [ws.mapView addAnnotation:x];
        [ws after:0.5 do:^{
          MAAnnotationView *xv = [ws.mapView viewForAnnotation:x];
          [ws log:@"reuse: offscreen redViews alive=%ld dequeueHits +%ld lastReusedZ(before bind)=%ld X.zIndex=%ld",
                  (long)alive, (long)(ws.dequeueHitCount - before), (long)ws.lastReusedZ, (long)xv.zIndex];
          n();
        }];
      }];
    },
    ^(S14Block n) { [ws finish]; },
  ]];
}

- (S14Step)awaitPinchStep:(CGFloat)scale {
  return ^(S14Block next) { [self awaitPinch:scale settle:1.0 then:next]; };
}

- (void)runX1 {
  __weak S14ExpHost *ws = self;
  NSArray<UIColor *> *cs = @[ S14Red(), S14Green(), S14Blue(), S14Magenta(), S14Cyan() ];
  NSMutableArray<S14Anno *> *as = [NSMutableArray array];
  for (NSInteger i = 0; i < 5; i++) {
    S14Anno *a = [self anno:[NSString stringWithFormat:@"x%ld", (long)i] at:CGPointMake(70 + i * 60, 300)
                      color:cs[i] z:i kind:0];
    [as addObject:a];
  }
  [self.mapView addAnnotations:as];
  void (^sdkShot)(NSString *, S14Block) = ^(NSString *name, S14Block n) {
    CFTimeInterval t = CACurrentMediaTime();
    [ws.mapView takeSnapshotInRect:ws.mapView.frame withCompletionBlock:^(UIImage *img, NSInteger state) {
      double ms = (CACurrentMediaTime() - t) * 1000;
      S14Pixels *px = [[S14Pixels alloc] initWithImage:img viewWidth:ws.mapView.bounds.size.width];
      NSMutableArray *got = [NSMutableArray array];
      for (S14Anno *a in as) [got addObject:[px nameAt:[ws pointOf:a.coordinate]]];
      [ws log:@"%@ takeSnapshot state=%ld %.0fms size=%.0fx%.0f scale=%.0f colors=%@", name, (long)state, ms,
              img.size.width, img.size.height, img.scale, [got componentsJoinedByString:@","]];
      [ws saveImage:img name:name];
      n();
    }];
  };
  [self runSteps:@[
    [self wait:1.5],
    ^(S14Block n) {
      NSMutableArray *got = [NSMutableArray array];
      for (S14Anno *a in as) [got addObject:[ws colorAt:[ws pointOf:a.coordinate]]];
      [ws log:@"drawViewHierarchy colors=%@", [got componentsJoinedByString:@","]];
      n();
    },
    ^(S14Block n) { sdkShot(@"sdk1", n); },
    ^(S14Block n) {  // 改第 1 个点的颜色后立即截图
      [ws.mapView viewForAnnotation:as[0]].backgroundColor = S14Yellow();
      sdkShot(@"sdk2_afterChange", n);
    },
    [self shot:@"real"],
    ^(S14Block n) { [ws finish]; },
  ]];
}
@end
