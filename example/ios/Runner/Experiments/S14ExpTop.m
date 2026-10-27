// E-I1 高层 Annotation 置顶（规格 §10.2）；E-I2 点击 View 与地图单击的回调顺序（R-SEL-8）。
#import "S14ExpHost.h"

@implementation S14ExpHost (ExpTop)

// 30 个 40×40 方块排成 6×5、间距 12pt（大量重叠），z = 序号。S 在中间、z=0，被邻居压住。
- (void)runI1 {
  __weak S14ExpHost *ws = self;
  NSArray<UIColor *> *cs = @[ S14Red(), S14Green(), S14Cyan(), S14Yellow() ];
  NSMutableArray<S14Anno *> *all = [NSMutableArray array];
  __block S14Anno *src = nil;
  CGPoint c = self.center;
  for (NSInteger i = 0; i < 30; i++) {
    NSInteger col = i % 6, row = i / 6;
    CGPoint p = CGPointMake(c.x + (col - 2.5) * 12, c.y + (row - 2) * 12);
    BOOL isS = (col == 2 && row == 2);
    S14Anno *a = [self anno:isS ? @"S" : [NSString stringWithFormat:@"n%ld", (long)i] at:p
                      color:isS ? S14Blue() : cs[i % 4] z:isS ? 0 : i + 1 kind:0];
    if (isS) src = a;
    [all addObject:a];
  }
  [self.mapView addAnnotations:all];
  // 孤立点 H：只隐藏源 View、上面没有高层点，用来单独看“隐藏的 View 是否响应点击”
  S14Anno *h = [self anno:@"H" at:CGPointMake(c.x, c.y + 200) color:S14Red() z:0 kind:0];
  [self.mapView addAnnotation:h];

  __block S14Anno *sel = nil;
  __block NSInteger srcCreated = 0;
  self.onViewFor = ^(S14Anno *a, S14View *v) {  // R-TOP-6：源点 View 重建时检查是否需要隐藏
    if (a == src) {
      srcCreated++;
      if (sel) v.hidden = YES;
    }
    if (a == h) v.hidden = YES;
  };
  CGPoint (^sp)(void) = ^CGPoint { return [ws pointOf:src.coordinate]; };
  CGPoint (^hp)(void) = ^CGPoint { return [ws pointOf:h.coordinate]; };
  S14Step state = ^(S14Block n) {
    MAAnnotationView *sv = [ws.mapView viewForAnnotation:src];
    MAAnnotationView *tv = sel ? [ws.mapView viewForAnnotation:sel] : nil;
    [ws log:@"state srcView=%@ hidden=%d inWindow=%d | selView=%@ z=%ld | srcCreated=%ld", sv ? @"Y" : @"nil",
            sv.hidden, sv.window != nil, tv ? @"Y" : @"nil", (long)tv.zIndex, (long)srcCreated];
    n();
  };
  // 手势带惯性，结束后把相机拉回源点（不改缩放），再检查
  S14Step back = ^(S14Block n) {
    [ws.mapView setCenterCoordinate:src.coordinate animated:NO];
    [ws after:0.8 do:n];
  };
  [self runSteps:@[
    [self wait:1.5],
    ^(S14Block n) {
      [ws log:@"buried: color at S = %@ (S is blue)", [ws colorAt:sp()]];
      [ws.mapView viewForAnnotation:h].hidden = YES;
      n();
    },
    [self tapAt:sp label:@"S-before-select"],
    [self tapAt:hp label:@"hidden-H"],
    ^(S14Block n) {  // R-TOP-1：加高层点（品红，z=99），隐藏源点
      sel = [ws anno:@"sel" at:sp() color:S14Magenta() z:99 kind:0];
      sel.coordinate = src.coordinate;
      [ws.mapView addAnnotation:sel];
      [ws.mapView viewForAnnotation:src].hidden = YES;
      n();
    },
    [self wait:0.5], state,
    [self expectColor:@"magenta" at:sp label:@"top-after-add"],
    [self tapAt:sp label:@"top-tap"],
    [self shot:@"selected"],
    [self swipe:CGPointMake(250, 650) to:CGPointMake(200, 610)], back, state,
    [self expectColor:@"magenta" at:sp label:@"top-after-pan"], [self tapAt:sp label:@"top-tap-pan"],
    ^(S14Block n) { [ws awaitPinch:2.0 settle:1.2 then:n]; }, back, state,
    [self expectColor:@"magenta" at:sp label:@"top-after-zoomIn"], [self tapAt:sp label:@"top-tap-zoomIn"],
    ^(S14Block n) { [ws awaitPinch:0.5 settle:1.2 then:n]; }, back, state,
    [self expectColor:@"magenta" at:sp label:@"top-after-zoomOut"], [self tapAt:sp label:@"top-tap-zoomOut"],
    ^(S14Block n) {  // 滚出屏幕：程序移动相机，避免手势惯性；记录离屏时 View 是否被回收
      CLLocationCoordinate2D far = [ws coordOf:CGPointMake(ws.center.x + 1500, ws.center.y)];
      [ws.mapView setCenterCoordinate:far animated:NO];
      [ws after:1.0 do:^{
        [ws log:@"offscreen srcView=%@ selView=%@", [ws.mapView viewForAnnotation:src] ? @"Y" : @"nil",
                [ws.mapView viewForAnnotation:sel] ? @"Y" : @"nil"];
        [ws.mapView setCenterCoordinate:src.coordinate animated:NO];
        n();
      }];
    },
    [self wait:1.0], state,
    [self expectColor:@"magenta" at:sp label:@"top-after-offscreen"], [self tapAt:sp label:@"top-tap-offscreen"],
    [self swipe:CGPointMake(100, 400) to:CGPointMake(160, 420)], back, state,
    [self expectColor:@"magenta" at:sp label:@"top-after-pan2"],
    ^(S14Block n) {  // R-TOP-2：源点坐标变化，高层点同步坐标
      CLLocationCoordinate2D nc = [ws coordOf:CGPointMake(sp().x + 60, sp().y)];
      src.coordinate = nc;
      sel.coordinate = nc;
      n();
    },
    [self wait:0.6],
    [self expectColor:@"magenta" at:sp label:@"top-after-move"], [self tapAt:sp label:@"top-tap-move"],
    [self shot:@"moved"],
    ^(S14Block n) {  // R-TOP-3：取消选中，移除高层点，按期望 visible 恢复源点
      [ws.mapView removeAnnotation:sel];
      sel = nil;
      [ws.mapView viewForAnnotation:src].hidden = NO;
      n();
    },
    [self wait:0.5],
    ^(S14Block n) {
      [ws log:@"restored: color at S = %@", [ws colorAt:sp()]];
      n();
    },
    [self tapAt:sp label:@"S-after-restore"],
    ^(S14Block n) { [ws finish]; },
  ]];
}

// E-I2：点击启用的 View、禁用的 View、已选中的 View、空白处、POI 附近，各 3 次，记录回调和相对手指抬起的时间
- (void)runI2 {
  __weak S14ExpHost *ws = self;
  CGPoint c = self.center;
  S14Anno *a = [self anno:@"A" at:CGPointMake(c.x - 80, c.y) color:S14Red() z:0 kind:0];
  S14Anno *d = [self anno:@"D" at:CGPointMake(c.x + 80, c.y) color:S14Blue() z:0 kind:0];
  d.disabled = YES;
  [self.mapView addAnnotations:@[ a, d ]];
  CGPoint (^ap)(void) = ^CGPoint { return [ws pointOf:a.coordinate]; };
  CGPoint (^dp)(void) = ^CGPoint { return [ws pointOf:d.coordinate]; };
  CGPoint (^bp)(void) = ^CGPoint { return CGPointMake(ws.center.x, ws.center.y + 160); };
  NSMutableArray<S14Step> *steps = [NSMutableArray arrayWithObject:[self wait:1.0]];
  for (NSInteger i = 0; i < 3; i++) {
    [steps addObject:[self tapAt:ap label:[NSString stringWithFormat:@"enabled#%ld", (long)i]]];
    [steps addObject:[self tapAt:ap label:[NSString stringWithFormat:@"enabled-again#%ld", (long)i]]];
    [steps addObject:[self tapAt:dp label:[NSString stringWithFormat:@"disabled#%ld", (long)i]]];
    [steps addObject:[self tapAt:bp label:[NSString stringWithFormat:@"blank#%ld", (long)i]]];
  }
  [steps addObject:^(S14Block n) {  // 关闭 POI 点击后再点一次空白
    ws.mapView.touchPOIEnabled = NO;
    n();
  }];
  [steps addObject:[self tapAt:bp label:@"blank-poiOff"]];
  [steps addObject:[self tapAt:ap label:@"enabled-poiOff"]];
  [steps addObject:^(S14Block n) { [ws finish]; }];
  [self runSteps:steps];
}
@end
