#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"
#import <AMapFoundationKit/AMapServices.h>
#import "Experiments/S14ExpHost.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [GeneratedPluginRegistrant registerWithRegistry:self];
//    设置AMap的key
    [AMapServices sharedServices].apiKey = @"4dfdec97b7bf0b8c13e94777103015a9";
  BOOL ok = [super application:application didFinishLaunchingWithOptions:launchOptions];
  // S14 实验：仅当启动参数带 -S14Exp 时接管窗口（UI 测试使用），正常启动不受影响
  [S14ExpHost installIfRequested:self];
  return ok;
}

@end
