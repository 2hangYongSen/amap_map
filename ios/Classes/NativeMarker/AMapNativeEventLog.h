//
//  AMapNativeEventLog.h
//  amap_map
//
//  新协议事件出口（R-INIT-2/4/5）：分配 eventSeq、握手前不发送、保留最近 64 条错误。
//  与 Android NativeEventLog 一致。主线程访问。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AMapEventSink)(NSString *method, NSDictionary *args);

@interface AMapNativeEventLog : NSObject

- (instancetype)initWithSink:(AMapEventSink)sink;

@property (nonatomic, copy) AMapEventSink sink;
@property (nonatomic, readonly) NSInteger lastEventSeq;
@property (nonatomic, readonly) NSInteger errorsDropped;

/// 握手：打开事件开关（与生成快照在同一次主线程调用内）
- (void)open;
/// 销毁后不再发送任何事件
- (void)close;

/// 状态类事件：握手前也分配序号，但不发送，状态由 attach 快照交付
- (void)event:(NSString *)method args:(NSDictionary *)args;

/// marker#nativeError：握手前只缓冲，握手后同时实时发送
- (void)error:(NSString *)code markerId:(nullable NSString *)markerId
      imageId:(nullable NSString *)imageId message:(NSString *)message;

- (NSArray<NSDictionary *> *)errorsSnapshot;

@end

NS_ASSUME_NONNULL_END
