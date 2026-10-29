//
//  AMapImageRegistry.h
//  amap_map
//
//  资源注册表（§7.1、§7.4）：状态机、epoch、期望/显示两类引用、8MiB 解码软预算。
//  全部方法在主线程调用；解码在后台队列执行，结果按 epoch 校验后回到主线程。
//

#import <UIKit/UIKit.h>
#import "AMapNativeMarkerLayout.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AMapImageState) {
    AMapImageStatePending = 0,
    AMapImageStateReady = 1,
    AMapImageStateFailed = 2,
};

/// R-RES-1 iOS 的两类引用：期望快照引用、View 绑定的当前显示引用
typedef NS_ENUM(NSInteger, AMapImageRef) {
    AMapImageRefDesired = 0,
    AMapImageRefDisplay = 1,
};

/// imagesToAdd 的一项，不可变；字节一直保留到资源释放（驱逐后可重新解码，R-RES-11）
@interface AMapImageSource : NSObject
@property (nonatomic, copy, readonly) NSString *id_;
/// bytes / asset
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, strong, readonly, nullable) NSData *data;
@property (nonatomic, copy, readonly, nullable) NSString *asset;
@property (nonatomic, copy, readonly, nullable) NSString *assetPackage;
@property (nonatomic, readonly) double pixelRatio;
/// 结构不合法时返回 nil
+ (nullable instancetype)parse:(id)raw error:(NSString *_Nullable *_Nullable)error;
+ (instancetype)bytesWithId:(NSString *)id_ data:(NSData *)data pixelRatio:(double)ratio;
@end

/// 解码函数：在后台队列调用；失败返回 nil 并给出原因
typedef UIImage *_Nullable (^AMapImageDecoder)(AMapImageSource *source, NSString *_Nullable *_Nonnull error);
/// 异步执行器：work 在后台执行，done 在主线程执行；测试可替换为手动执行
typedef void (^AMapImageRunner)(dispatch_block_t work, dispatch_block_t done);

@protocol AMapImageRegistryListener <NSObject>
/// 状态变为 ready 或 failed（首次结果、重试结果）
- (void)imageRegistryDidResolve:(NSString *)imageId;
@end

@interface AMapImageRegistry : NSObject <AMapImageResolver>

- (instancetype)initWithDecoder:(AMapImageDecoder)decoder runner:(AMapImageRunner)runner budget:(NSUInteger)bytes;

/// 默认：后台串行队列解码，结果回主线程
+ (AMapImageRunner)defaultRunner;

@property (nonatomic, weak, nullable) id<AMapImageRegistryListener> listener;

/// imagesToAdd：新登记进入 pending；releasing 中再次加入按原状态恢复；failed 重试（epoch+1）
- (void)registerSource:(AMapImageSource *)source;
/// imageIdsToRelease：进入 releasing，refs 归零才真正移除（R-RES-10）
- (void)releaseId:(NSString *)imageId;
- (void)releaseAllExcept:(NSSet<NSString *> *)keep;

/// 取得引用；条目不存在返回 NO
- (BOOL)acquire:(NSString *)imageId kind:(AMapImageRef)kind;
- (void)unref:(NSString *)imageId kind:(AMapImageRef)kind;

/// ready 的解码结果；被预算淘汰时从原始数据同步重新解码
- (nullable UIImage *)imageFor:(NSString *)imageId;

- (BOOL)contains:(NSString *)imageId;
- (AMapImageState)stateOf:(NSString *)imageId;
- (NSInteger)refsOf:(NSString *)imageId kind:(AMapImageRef)kind;
- (nullable NSDictionary *)failureOf:(NSString *)imageId;
- (NSUInteger)count;
- (NSInteger)decodeCount;
- (NSUInteger)decodedBytes;
- (BOOL)decodedOverBudget;

/// markers#attach 的 images 段（R-INIT-3）；releasing 的不列出
- (NSDictionary *)snapshot;
/// markers#update 返回值 imagesPending（§6.5）
- (NSArray<NSString *> *)pendingIds;

/// 地图销毁：之后的解码结果直接丢弃，不再通知
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
