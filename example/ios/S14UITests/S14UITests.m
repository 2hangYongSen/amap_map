// S14 真机实验驱动：启动 App 进入实验宿主，轮询 `s14cmd` 标签，按命令执行真实触摸。
// 命令格式：seq|op|settle|args。op = tap / swipe / pinch / shot / done。
// 运行：TEST_RUNNER_S14EXP=I1 xcodebuild test -scheme S14 ...（见 example/tool/s14_run.sh）
#import <XCTest/XCTest.h>

@interface S14UITests : XCTestCase
@end

@implementation S14UITests

- (void)testExperiment {
  NSString *exp = NSProcessInfo.processInfo.environment[@"S14EXP"] ?: @"I0";
  XCUIApplication *app = [XCUIApplication new];
  app.launchArguments = @[ @"-S14Exp", exp ];
  [app launch];
  XCUIElement *cmd = app.staticTexts[@"s14cmd"];
  XCTAssertTrue([cmd waitForExistenceWithTimeout:30], @"实验宿主未启动");
  XCUICoordinate *origin = [app coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *(^at)(NSString *, NSString *) = ^XCUICoordinate *(NSString *x, NSString *y) {
    return [origin coordinateWithOffset:CGVectorMake(x.doubleValue, y.doubleValue)];
  };
  NSString *lastSeq = @"0";
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20 * 60];
  while ([deadline timeIntervalSinceNow] > 0) {
    NSArray<NSString *> *f = [cmd.label componentsSeparatedByString:@"|"];
    if (f.count < 4 || [f[0] isEqualToString:lastSeq]) {
      [NSThread sleepForTimeInterval:0.3];
      continue;
    }
    lastSeq = f[0];
    NSString *op = f[1];
    NSLog(@"S14UI cmd %@", cmd.label);
    if ([op isEqualToString:@"done"]) break;
    if ([op isEqualToString:@"tap"]) {
      NSArray *p = [f[3] componentsSeparatedByString:@","];
      [at(p[0], p[1]) tap];
    } else if ([op isEqualToString:@"swipe"]) {  // args = 速度|x1,y1,x2,y2;...
      CGFloat v = f[3].doubleValue;
      for (NSString *seg in [f[4] componentsSeparatedByString:@";"]) {
        NSArray *p = [seg componentsSeparatedByString:@","];
        // 终点停 0.1s 再抬起，避免惯性滑动
        [at(p[0], p[1]) pressForDuration:0.05 thenDragToCoordinate:at(p[2], p[3]) withVelocity:v thenHoldForDuration:0.1];
      }
    } else if ([op isEqualToString:@"pinch"]) {
      CGFloat s = f[3].doubleValue;
      [app pinchWithScale:s velocity:(s > 1 ? 2 : -2)];
    } else if ([op isEqualToString:@"shot"]) {
      XCTAttachment *a = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
      a.name = [NSString stringWithFormat:@"%@_%@", exp, f[3]];
      a.lifetime = XCTAttachmentLifetimeKeepAlways;
      [self addAttachment:a];
    }
  }
  // 实验日志作为附件取回
  XCUIElement *log = app.textViews[@"s14log"];
  NSString *text = [log waitForExistenceWithTimeout:5] ? (NSString *)log.value : @"(no log)";
  XCTAttachment *la = [XCTAttachment attachmentWithString:text];
  la.name = [exp stringByAppendingString:@".log"];
  la.lifetime = XCTAttachmentLifetimeKeepAlways;
  [self addAttachment:la];
  NSLog(@"S14UI LOG BEGIN\n%@\nS14UI LOG END", text);
  XCTAssertTrue([deadline timeIntervalSinceNow] > 0, @"实验超时");
}

// ---- S17：点击计时。App 以 integration_test/native_marker_tap_diag_test.dart 为入口，
// 测试绑定下 Flutter 语义不进无障碍树，这里按固定顺序点原生点位视图（n1 = 带 ¥3000 标签，l1 = 图片点）。
// 判定由 Dart 写到 App tmp/s17_result.txt，s17_ios_run.sh 取回 ----

- (void)testS17Taps {
  XCUIApplication *app = [XCUIApplication new];
  [app launch];
  XCUIElementQuery *views = [[app descendantsMatchingType:XCUIElementTypeAny]
      matchingIdentifier:@"maannotationview"];
  XCUIElement *n1 = [views matchingPredicate:[NSPredicate predicateWithFormat:@"label == '¥3000'"]].firstMatch;
  XCUIElement *l1 = [views matchingPredicate:[NSPredicate predicateWithFormat:@"label == ''"]].firstMatch;
  XCTAssertTrue([n1 waitForExistenceWithTimeout:60] && [l1 waitForExistenceWithTimeout:10], @"点位未出现");
  [NSThread sleepForTimeInterval:4];  // Dart 端进入点击阶段前要等首次回执
  // 每次点击前重新取 frame（选中会改变 n1 的大小），间隔 2.5s 避开双击放大
  NSArray<XCUIElement *> *seq = @[ n1, n1, n1, l1, l1, l1 ];
  for (XCUIElement *e in seq) {
    CGRect f = e.frame;
    NSLog(@"S17UI tap %@ %@", e == n1 ? @"n1" : @"l1", NSStringFromCGRect(f));
    [[self at:app point:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))] tap];
    [NSThread sleepForTimeInterval:2.5];
  }
  [NSThread sleepForTimeInterval:3];  // Dart 关闭诊断
  for (XCUIElement *e in @[ n1, l1 ]) {
    CGRect f = e.frame;
    [[self at:app point:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))] tap];
    [NSThread sleepForTimeInterval:2.5];
  }
  [NSThread sleepForTimeInterval:4];
  XCTAttachment *a = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
  a.name = @"S17_end";
  a.lifetime = XCTAttachmentLifetimeKeepAlways;
  [self addAttachment:a];
}

// ---- S18：通用命令驱动。App 以 integration_test/native_marker_tap_test.dart 为入口，
// 命令写在一个不可点击的原生点位文字里："S18|序号|op|参数"（原生点位文字进无障碍树）。
// op = tap（x,y 为点）/ done；结果由 Dart 写到 App tmp/s18/，s18_ios_run.sh 取回 ----

- (void)testS18Commands {
  XCUIApplication *app = [XCUIApplication new];
  [app launch];
  XCUIElement *cmd = [[app descendantsMatchingType:XCUIElementTypeAny]
      matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH 'S18|'"]].firstMatch;
  XCTAssertTrue([cmd waitForExistenceWithTimeout:60], @"命令点位未出现");
  NSString *lastSeq = @"0";
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40 * 60];
  while ([deadline timeIntervalSinceNow] > 0) {
    NSArray<NSString *> *f = [cmd.label componentsSeparatedByString:@"|"];
    if (f.count < 4 || [f[1] isEqualToString:lastSeq]) {
      [NSThread sleepForTimeInterval:0.1];
      continue;
    }
    lastSeq = f[1];
    NSLog(@"S18UI cmd %@", cmd.label);
    if ([f[2] isEqualToString:@"done"]) break;
    if ([f[2] isEqualToString:@"tap"]) {
      NSArray *p = [f[3] componentsSeparatedByString:@","];
      [[self at:app point:CGPointMake([p[0] doubleValue], [p[1] doubleValue])] tap];
    }
  }
  XCTAssertTrue([deadline timeIntervalSinceNow] > 0, @"S18 超时");
}

// ---- S16：选择示例页真实点击（SDK → AMapViewController → 插件 → 通道 → Dart 页面日志） ----

- (NSString *)logOf:(XCUIApplication *)app {
  NSPredicate *p = [NSPredicate predicateWithFormat:@"label CONTAINS 'onTap' OR label CONTAINS '选择 ' OR label CONTAINS '点击价格'"];
  XCUIElement *e = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:p].firstMatch;
  return e.exists ? e.label : @"(none)";
}

// 点击后等日志变化（点击回调约 352ms，E-I2）
- (NSString *)tap:(XCUICoordinate *)c app:(XCUIApplication *)app name:(NSString *)name {
  NSString *before = [self logOf:app];
  [c tap];
  for (int i = 0; i < 30 && [[self logOf:app] isEqualToString:before]; i++) [NSThread sleepForTimeInterval:0.1];
  [NSThread sleepForTimeInterval:0.3];
  NSString *log = [self logOf:app];
  NSLog(@"S16UI %@ → %@", name, [log stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
  XCTAttachment *a = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
  a.name = [@"S16_" stringByAppendingString:name];
  a.lifetime = XCTAttachmentLifetimeKeepAlways;
  [self addAttachment:a];
  return log;
}

- (XCUICoordinate *)at:(XCUIApplication *)app point:(CGPoint)p {
  return [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(p.x, p.y)];
}

static CGPoint Mid(CGRect r) { return CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r)); }

- (void)testSelectionPage {
  XCUIApplication *app = [XCUIApplication new];
  [app launch];
  // Flutter 把 ListTile 的标题与副标题合成一个标签，按包含匹配，元素类型不限
  XCUIElement *entry = [[app descendantsMatchingType:XCUIElementTypeAny]
                           matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS 'AM-E50.7'"]].firstMatch;
  // Flutter 的无障碍树在首次查询后才生成，等待期间反复取快照
  BOOL listed = NO;
  // 列表懒加载：等首页出现，再上滑直到条目可点
  [[[app descendantsMatchingType:XCUIElementTypeAny]
       matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS 'AM-D01'"]].firstMatch
      waitForExistenceWithTimeout:20];
  for (int i = 0; i < 15 && !listed; i++) {
    listed = entry.exists && entry.frame.size.height > 0 && CGRectGetMaxY(entry.frame) < 700;
    if (!listed) [[self at:app point:CGPointMake(187, 600)] pressForDuration:0.05
                                               thenDragToCoordinate:[self at:app point:CGPointMake(187, 350)]];
    [NSThread sleepForTimeInterval:0.6];
  }
  if (!listed) NSLog(@"S16UI tree %@", app.debugDescription);
  XCTAssertTrue(listed, @"列表中没有选择示例");
  [NSThread sleepForTimeInterval:2];  // 等首页布局稳定，避免点到过期的无障碍坐标
  XCUIElement *pageButton = [[app descendantsMatchingType:XCUIElementTypeAny]
                                matchingPredicate:[NSPredicate predicateWithFormat:@"label == '选中 p2'"]].firstMatch;
  for (int i = 0; i < 3 && !pageButton.exists; i++) {
    [[self at:app point:Mid(entry.frame)] tap];
    [pageButton waitForExistenceWithTimeout:5];
  }
  XCTAssertTrue(pageButton.exists, @"没有进入选择示例页");
  // 点位 View 带按钮 trait，按标签匹配、类型不限
  XCUIElement *(^byLabel)(NSString *) = ^XCUIElement *(NSString *l) {
    return [[app descendantsMatchingType:XCUIElementTypeAny]
               matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", l]].firstMatch;
  };
  XCUIElement *p1 = byLabel(@"¥3000"), *p2 = byLabel(@"¥5200"), *p3 = byLabel(@"¥4100");
  BOOL found = [p3 waitForExistenceWithTimeout:20];
  if (!found) NSLog(@"S16UI tree %@", app.debugDescription);
  XCTAssertTrue(found, @"原生点位文字不可见（无障碍树中没有）");
  [NSThread sleepForTimeInterval:2];
  CGPoint c1 = Mid(p1.frame), c2 = Mid(p2.frame), c3 = Mid(p3.frame);
  CGPoint overlap = CGPointMake((c1.x + c3.x) / 2, (c1.y + c3.y) / 2);  // p1、p3 气泡重叠处
  NSLog(@"S16UI frames p1=%@ p2=%@ p3=%@", NSStringFromCGRect(p1.frame), NSStringFromCGRect(p2.frame),
        NSStringFromCGRect(p3.frame));

  // 1. 点 p2：先选择事件、后 onTap（R-SEL-3）
  NSString *log = [self tap:[self at:app point:c2] app:app name:@"1_p2"];
  XCTAssertTrue([log containsString:@"→ p2（markerTap"] && [log hasSuffix:@"onTap p2"], @"%@", log);
  // 2. 再点 p2：落在高层 View 上，映射回 p2（R-TOP-5），重复点击取消
  log = [self tap:[self at:app point:c2] app:app name:@"2_p2_retap"];
  XCTAssertTrue([log containsString:@"p2 → null（retap"], @"%@", log);
  // 3. 点重叠处：选中当前在上面的那个（T）
  log = [self tap:[self at:app point:overlap] app:app name:@"3_overlap"];
  NSString *top = [log containsString:@"→ p1（"] ? @"p1" : [log containsString:@"→ p3（"] ? @"p3" : nil;
  XCTAssertNotNil(top, @"%@", log);
  NSString *other = [top isEqualToString:@"p1"] ? @"p3" : @"p1";
  // 4. 地图空白处取消（mapTap）
  CGPoint blank = CGPointMake(c1.x - 120, c1.y + 80);  // p1 左下方空白
  // 宏参数按逗号切分，方括号不保护逗号：期望串先算好
  NSString *want = [NSString stringWithFormat:@"%@ → null（mapTap", top];
  log = [self tap:[self at:app point:blank] app:app name:@"4_blank"];
  XCTAssertTrue([log containsString:want], @"%@", log);
  // 5. 点被压住那个（O）露出的一侧把它选中
  CGPoint co = [other isEqualToString:@"p1"] ? CGPointMake(c1.x - (c3.x - c1.x), c1.y + (c1.y - c3.y))
                                             : CGPointMake(c3.x + (c3.x - c1.x), c3.y - (c1.y - c3.y));
  want = [NSString stringWithFormat:@"→ %@（markerTap", other];
  log = [self tap:[self at:app point:co] app:app name:@"5_other"];
  XCTAssertTrue([log containsString:want], @"%@", log);
  // 6. 再点重叠处：选中的 O 已经置顶，点击落在 O 上（retap），不是原来在上面的 T
  want = [NSString stringWithFormat:@"%@ → null（retap", other];
  log = [self tap:[self at:app point:overlap] app:app name:@"6_overlap_after"];
  XCTAssertTrue([log containsString:want], @"选中点没有置顶：%@", log);
}

@end
