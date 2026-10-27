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

@end
