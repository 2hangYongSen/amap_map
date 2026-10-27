//
//  AMapMarkerDiagnostics.h
//  amap_map
//
//  诊断与计时（§13）：markers#applied 回执、标记方块、tapId 关联、diag#ping。
//  与 Android Diagnostics 对应。只在 markerDiagnostics 开启时工作，关闭时不发任何事件（T-TIME-3）。
//  时间统一用 CACurrentMediaTime（mach 单调时钟）换算为毫秒（R-TIME-4）。主线程访问。
//

#import <Foundation/Foundation.h>

@class AMapNativeEventLog;

NS_ASSUME_NONNULL_BEGIN

/// 地图角落 8×8 的标记方块（R-TIME-6）
@protocol AMapDiagnosticsSquare <NSObject>
- (void)showColor:(uint32_t)argb;
- (void)hide;
@end

/// 一次 markers#update / resync 的计时记录
@interface AMapDiagSync : NSObject
@property (nonatomic, readonly) NSInteger syncId;
@end

typedef double (^AMapDiagClock)(void);

@interface AMapMarkerDiagnostics : NSObject

- (instancetype)initWithEvents:(AMapNativeEventLog *)events;

/// 可替换的时钟（毫秒）；XCTest 注入可控时钟
@property (nonatomic, copy) AMapDiagClock clock;
@property (nonatomic, strong, nullable) id<AMapDiagnosticsSquare> square;
@property (nonatomic, readonly) BOOL enabled;
/// 回执中的布局计算次数（iOS 没有合成位图，按布局缓存未命中计 drawCount）
@property (nonatomic, assign) NSInteger layoutMisses;
@property (nonatomic, assign) NSInteger layoutHits;
/// 回执 memory.decodedBytes 的来源
@property (nonatomic, copy, nullable) NSUInteger (^decodedBytes)(void);
@property (nonatomic, copy, nullable) BOOL (^decodedOverBudget)(void);

+ (NSArray<NSNumber *> *)palette;

- (void)setEnabled:(BOOL)on;

/// t2：请求到达，同一调用内切换方块颜色并记录 t2v；未开启返回 nil
- (nullable AMapDiagSync *)begin:(NSInteger)syncId args:(nullable id)args;
/// 被接受的新增或修改点；isNative 为 NO 时（icon 点）旧路径 c2 在此记录
- (void)touched:(nullable AMapDiagSync *)sync markerId:(NSString *)markerId isNative:(BOOL)isNative;
/// iOS 外观同步绑定：t4 在返回前记录（t4 ≤ t3），随后发回执
- (void)end:(nullable AMapDiagSync *)sync;

/// c1：SDK 点击回调；未开启返回 nil
- (nullable NSNumber *)tapBegin:(NSString *)markerId;
/// 新路径：选择已提交、外观已绑定，立即记 c2
- (void)tapAppliedNative:(nullable NSNumber *)tapId;

/// diag#ping 的返回 {nativeMs}；未开启返回 nil
- (nullable NSDictionary *)ping;

- (double)nowMs;

+ (long long)countBytes:(nullable id)obj;

@end

NS_ASSUME_NONNULL_END
