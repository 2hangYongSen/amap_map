// S16 T-TOP-4（规格 §10.2）：用插件正式的 AMapMarkerController + AMapNativeMarkerView 复核 E-I1。
// 30 个原生形状点重叠，选中被遮挡的 S；拖动、放大、缩小、滚出屏幕再回来、改坐标后，
// 选中态始终在最上层（取色为选中色），点击始终映射到源 id "S"。
#import "S14ExpHost.h"
#import <amap_map/AMapMarkerController.h>
#import <amap_map/AMapMarker.h>
#import <amap_map/AMapNativeEventLog.h>
#import <amap_map/AMapNativeMarkerView.h>
#import <amap_map/AMapSelectionAnnotation.h>
#import <amap_map/MAPointAnnotation+Flutter.h>

// 与 S14Support 的取色调色板一致（ARGB）
static const uint32_t kRed = 0xFFE60000, kGreen = 0xFF00BE00, kBlue = 0xFF0000E6;
static const uint32_t kYellow = 0xFFF0DC00, kMagenta = 0xFFE600E6, kCyan = 0xFF00C8E6;

// 40×40 方块；文字与填充同色，取色不受文字干扰；选中态品红
static NSDictionary *T4Marker(NSString *id_, CLLocationCoordinate2D c, uint32_t fill, NSInteger z) {
  NSDictionary *bg = @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(fill), @"cornerRadius": @0};
  NSDictionary *sel = @{@"type": @"shape", @"kind": @"roundedRect", @"fillColor": @(kMagenta), @"cornerRadius": @0};
  NSDictionary *pres = @{
    @"content": @{@"text": id_},
    @"style": @{@"background": bg, @"textColor": @(fill), @"width": @40, @"height": @40},
    @"selectedStyle": @{@"background": sel, @"textColor": @(kMagenta), @"width": @40, @"height": @40},
    @"anchorType": @"bodyCenter",
  };
  return @{@"id": id_, @"renderMode": @"native", @"position": @[@(c.latitude), @(c.longitude)], @"alpha": @1,
           @"visible": @YES, @"clickable": @YES, @"zIndex": @(z), @"icon": [NSNull null],
           @"nativePresentation": pres, @"selectable": @YES, @"selectedZIndex": @99};
}

// record: 在 S14ExpHost.m 中实现，这里只声明
@interface S14ExpHost (S16Record)
- (void)record:(NSString *)name;
@end

@implementation S14ExpHost (S16ExpTop)

// ---- 与 AMapViewController 相同的代理分流 ----
- (MAAnnotationView *)pluginViewFor:(id<MAAnnotation>)annotation {
  AMapMarkerController *c = self.markerController;
  if ([annotation isKindOfClass:[AMapSelectionAnnotation class]]) {
    return [c nativeViewForSelectionAnnotation:(AMapSelectionAnnotation *)annotation mapView:self.mapView];
  }
  if (![annotation isKindOfClass:[MAPointAnnotation class]]) return nil;
  NSString *mid = ((MAPointAnnotation *)annotation).markerId;
  AMapMarker *m = mid ? [c markerForId:mid] : nil;
  if ([mid isEqualToString:@"S"]) self.viewForCount++;  // 源点 View 创建次数（R-TOP-6）
  return m.isNative ? [c nativeViewForMarker:m mapView:self.mapView] : nil;
}

- (void)pluginDidAdd:(MAAnnotationView *)view {
  AMapMarkerController *c = self.markerController;
  if (![view isKindOfClass:[AMapNativeMarkerView class]]) return;
  if ([view.annotation isKindOfClass:[AMapSelectionAnnotation class]]) {
    [c rebindSelectionView:(AMapNativeMarkerView *)view];
    return;
  }
  NSString *mid = ((MAPointAnnotation *)view.annotation).markerId;
  AMapMarker *m = mid ? [c markerForId:mid] : nil;
  if (m.isNative) [c bindNativeView:(AMapNativeMarkerView *)view marker:m];
}

// R-TOP-5：高层 View 按 sourceMarkerId 映射
- (void)pluginTapped:(MAAnnotationView *)view {
  NSString *mid = [view.annotation isKindOfClass:[AMapSelectionAnnotation class]]
                      ? ((AMapSelectionAnnotation *)view.annotation).sourceMarkerId
                      : ((MAPointAnnotation *)view.annotation).markerId;
  NSString *layer = [view.annotation isKindOfClass:[AMapSelectionAnnotation class]] ? @"top" : @"src";
  [self record:[NSString stringWithFormat:@"tapped:%@(%@)", mid ?: @"?", layer]];
  if (mid) [(AMapMarkerController *)self.markerController onMarkerTap:mid];
}

// ---- 实验 ----
- (void)runT4 {
  __weak S14ExpHost *ws = self;
  AMapMarkerController *c = [[AMapMarkerController alloc] init:nil mapView:self.mapView registrar:nil registry:nil];
  self.markerController = c;
  __block NSInteger selEvents = 0;
  c.events.sink = ^(NSString *method, NSDictionary *args) {
    if ([method isEqualToString:@"marker#selectionChanged"]) selEvents++;
    [ws log:@"event %@ %@", method, args[@"selectedId"] ?: args[@"code"] ?: @""];
  };
  [c attach];
  // 自动选择开启，但重复点击、点地图都不取消，便于连续检查点击映射
  [c applyMarkerOptions:@{@"markerSelection": @{@"deselectOnMapTap": @NO, @"deselectOnRetap": @NO}}];

  NSArray *pal = @[ @(kRed), @(kGreen), @(kCyan), @(kYellow) ];
  NSMutableArray *adds = [NSMutableArray array];
  CGPoint ctr = self.center;
  __block CLLocationCoordinate2D sc;
  for (NSInteger i = 0; i < 30; i++) {
    NSInteger col = i % 6, row = i / 6;
    CGPoint p = CGPointMake(ctr.x + (col - 2.5) * 12, ctr.y + (row - 2) * 12);
    BOOL isS = (col == 2 && row == 2);
    CLLocationCoordinate2D co = [self coordOf:p];
    if (isS) sc = co;
    [adds addObject:T4Marker(isS ? @"S" : [NSString stringWithFormat:@"n%ld", (long)i], co,
                             isS ? kBlue : [pal[i % 4] unsignedIntValue], isS ? 0 : i + 1)];
  }
  [c nativeUpdate:@{@"protocolVersion": @2, @"syncId": @1, @"markersToAdd": adds}];

  CGPoint (^sp)(void) = ^CGPoint { return [ws pointOf:[c markerForId:@"S"].position]; };
  S14Step back = ^(S14Block n) {  // 手势带惯性：结束后把相机拉回 S（不改缩放）
    [ws.mapView setCenterCoordinate:[c markerForId:@"S"].position animated:NO];
    [ws after:0.8 do:n];
  };
  S14Step (^check)(NSString *) = ^S14Step(NSString *label) {
    return ^(S14Block n) {
      [ws runSteps:@[
        [ws expectColor:@"magenta" at:sp label:[@"top-" stringByAppendingString:label]],
        [ws tapAt:sp label:[@"tap-" stringByAppendingString:label]],
        ^(S14Block n2) {
          NSString *events = [ws.tapEvents componentsJoinedByString:@","];
          BOOL ok = [events containsString:@"tapped:S(top)"] && ![events containsString:@"mapTap"];
          AMapNativeMarkerView *src = (AMapNativeMarkerView *)[ws.mapView viewForAnnotation:[c markerForId:@"S"].annotation];
          [ws log:@"%@ map-%@: %@ | srcHidden=%d srcCreated=%ld selected=%@", ok ? @"PASS" : @"FAIL", label, events,
                  src ? src.hidden : -1, (long)ws.viewForCount, [c attach][@"selection"][@"selectedId"]];
          n();
        },
      ]];
    };
  };

  [self runSteps:@[
    [self wait:1.5],
    ^(S14Block n) {
      [ws log:@"%@ buried: color at S = %@ (S is blue, should be covered)",
              [[ws colorAt:sp()] isEqualToString:@"blue"] ? @"FAIL" : @"PASS", [ws colorAt:sp()]];
      [c setSelectedFromArgs:@{@"markerId": @"S"}];  // 被遮挡的点只能用 API 选中
      n();
    },
    [self wait:0.5], check(@"select"), [self shot:@"selected"],
    [self swipe:CGPointMake(250, 650) to:CGPointMake(200, 610)], back, check(@"pan"),
    ^(S14Block n) { [ws awaitPinch:2.0 settle:1.2 then:n]; }, back, check(@"zoomIn"),
    ^(S14Block n) { [ws awaitPinch:0.5 settle:1.2 then:n]; }, back, check(@"zoomOut"),
    ^(S14Block n) {  // 滚出屏幕再回来：源点 View 被回收并重建，必须保持隐藏（R-TOP-6）
      CLLocationCoordinate2D far = [ws coordOf:CGPointMake(ws.center.x + 1500, ws.center.y)];
      [ws.mapView setCenterCoordinate:far animated:NO];
      [ws after:1.0 do:^{
        [ws log:@"offscreen srcView=%@", [ws.mapView viewForAnnotation:[c markerForId:@"S"].annotation] ? @"Y" : @"nil"];
        [ws.mapView setCenterCoordinate:[c markerForId:@"S"].position animated:NO];
        n();
      }];
    },
    [self wait:1.0], check(@"offscreen"),
    [self swipe:CGPointMake(100, 400) to:CGPointMake(160, 420)], back, check(@"pan2"),
    ^(S14Block n) {  // R-TOP-2：源点改坐标，高层点跟随
      CLLocationCoordinate2D nc = [ws coordOf:CGPointMake(sp().x + 60, sp().y)];
      [c nativeUpdate:@{@"protocolVersion": @2, @"syncId": @2,
                        @"markersToChange": @[ T4Marker(@"S", nc, kBlue, 0) ]}];
      n();
    },
    [self wait:0.6], check(@"move"), [self shot:@"moved"],
    ^(S14Block n) {  // R-TOP-3：取消选择后源点恢复显示（移动后不再被遮挡，应为蓝色）
      [c setSelectedFromArgs:@{@"markerId": [NSNull null]}];
      n();
    },
    [self wait:0.5],
    [self expectColor:@"blue" at:sp label:@"restored"],
    ^(S14Block n) {
      [ws log:@"%@ selectionEvents=%ld (want 2: select + deselect)", selEvents == 2 ? @"PASS" : @"FAIL", (long)selEvents];
      [ws finish];
    },
  ]];
}
@end
