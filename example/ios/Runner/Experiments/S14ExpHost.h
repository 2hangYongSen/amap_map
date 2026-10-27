// S14 iOS SDK 实验宿主（规格 §14 E-I0～I4、E-X1）。
// 只在启动参数带 `-S14Exp <编号>` 时接管窗口；不进入插件，正常启动不受影响。
// 真实触摸由 UI 测试 `S14UITests` 执行：本宿主把命令写到 `s14cmd` 标签，UI 测试读到后点击或拖动。
#import <MAMapKit/MAMapKit.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 实验点位：kind 决定外观
// 0 纯色方块 40×40；1 旧路径整图（预渲染阴影）；2 形状+shadowPath；3 形状+shadowPath+光栅化；4 形状+阴影无 shadowPath（对照）
@interface S14Anno : MAPointAnnotation
@property(nonatomic, copy) NSString *tag;
@property(nonatomic, strong) UIColor *color;
@property(nonatomic, assign) NSInteger z;
@property(nonatomic, assign) NSInteger kind;
@property(nonatomic, assign) BOOL startHidden;
@property(nonatomic, assign) BOOL disabled;
@end

@interface S14View : MAAnnotationView
- (void)bindAnno:(S14Anno *)a;
@end

// 截图取色：一次转成 RGBA 缓冲，多点取色（坐标单位为点）
@interface S14Pixels : NSObject
- (instancetype)initWithImage:(UIImage *)img viewWidth:(CGFloat)vw;
- (NSString *)nameAt:(CGPoint)p;
@end

typedef void (^S14Block)(void);
typedef void (^S14Step)(S14Block next);

@interface S14ExpHost : UIViewController <MAMapViewDelegate>
@property(nonatomic, strong) MAMapView *mapView;
@property(nonatomic, copy) NSString *exp;
@property(nonatomic, assign) NSInteger viewForCount;
@property(nonatomic, assign) NSInteger dequeueHitCount;
@property(nonatomic, assign) NSInteger lastReusedZ;  // 出队 View 在绑定前的 zIndex（核对复用是否残留）
@property(nonatomic, assign) BOOL touchDown;
@property(nonatomic, assign) CFTimeInterval lastTouchUp;
@property(nonatomic, assign) CFTimeInterval lastRegionChange;
// 实验钩子：viewForAnnotation 绑定之后、didAddAnnotationViews 时、每帧
@property(nonatomic, copy, nullable) void (^onViewFor)(S14Anno *a, S14View *v);
@property(nonatomic, copy, nullable) void (^onDidAdd)(S14Anno *a, MAAnnotationView *v);
@property(nonatomic, copy, nullable) void (^onFrame)(CFTimeInterval ts);
// S16：插件点位控制器；设置后代理回调先交给它（与 AMapViewController 相同的分流，见 S16ExpTop.m）
@property(nonatomic, strong, nullable) id markerController;
// 点击类回调记录，每项形如 "tapped:S +12ms"（相对最近一次手指抬起）
@property(nonatomic, strong, readonly) NSMutableArray<NSString *> *tapEvents;

+ (BOOL)installIfRequested:(id<UIApplicationDelegate>)delegate;

- (void)log:(NSString *)fmt, ... NS_FORMAT_FUNCTION(1, 2);
- (void)after:(NSTimeInterval)t do:(S14Block)b;
- (void)runSteps:(NSArray<S14Step> *)steps;
// 请求 UI 测试执行手势；收到 n 次“全部手指抬起”后再等 settle 秒执行 next（30s 兜底）
- (void)awaitTap:(CGPoint)p settle:(NSTimeInterval)settle then:(S14Block)next;
- (void)awaitSwipes:(NSArray<NSValue *> *)pts velocity:(CGFloat)v settle:(NSTimeInterval)settle then:(S14Block)next;
- (void)awaitPinch:(CGFloat)scale settle:(NSTimeInterval)settle then:(S14Block)next;
// 请 UI 测试截一张真实屏幕图（存入 xcresult 附件），固定等 2s
- (void)realShot:(NSString *)name then:(S14Block)next;
- (void)finish;

- (UIImage *)snapshot;  // drawViewHierarchy 截图
- (void)saveImage:(UIImage *)img name:(NSString *)name;
- (CGPoint)pointOf:(CLLocationCoordinate2D)c;
- (CLLocationCoordinate2D)coordOf:(CGPoint)p;
- (S14Anno *)anno:(NSString *)tag at:(CGPoint)p color:(UIColor *)c z:(NSInteger)z kind:(NSInteger)k;
- (nullable MAAnnotationView *)liveViewOf:(id<MAAnnotation>)a;  // 在窗口中且未隐藏
- (void)clearAll;

- (void)startFrames;
- (NSArray<NSArray<NSNumber *> *> *)stopFrames;  // 每项 @[dt(ms), moving(0/1)]
- (NSString *)frameStats:(NSArray<NSArray<NSNumber *> *> *)frames;
@end

// S16 插件代理分流（S16ExpTop.m）
@interface S14ExpHost (S16ExpTop)
- (nullable MAAnnotationView *)pluginViewFor:(id<MAAnnotation>)annotation;
- (void)pluginDidAdd:(MAAnnotationView *)view;
- (void)pluginTapped:(MAAnnotationView *)view;
@end

// 常用步骤（实验文件 S14Exp*.m 用 runSteps 串起来；runI0 等按名字反射调用）
@interface S14ExpHost (Steps)
- (NSString *)colorAt:(CGPoint)p;  // 当前截图在 p 处的颜色名
- (S14Step)wait:(NSTimeInterval)t;
- (S14Step)tapAt:(CGPoint (^)(void))pt label:(NSString *)label;  // 点击并记录回调
- (S14Step)expectColor:(NSString *)color at:(CGPoint (^)(void))pt label:(NSString *)label;
- (S14Step)swipe:(CGPoint)a to:(CGPoint)b;
- (S14Step)shot:(NSString *)name;  // 真实屏幕截图 + 应用内截图
@property(nonatomic, readonly) CGPoint center;
@end

UIColor *S14Red(void);
UIColor *S14Green(void);
UIColor *S14Blue(void);
UIColor *S14Yellow(void);
UIColor *S14Magenta(void);
UIColor *S14Cyan(void);

NS_ASSUME_NONNULL_END
