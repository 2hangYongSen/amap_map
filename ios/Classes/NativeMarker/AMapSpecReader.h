//
//  AMapSpecReader.h
//  amap_map
//
//  R-NORM-2 规范化与通道载荷读取（与 Android Norm / SpecReader 对应）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 长度精度 1/64，比例（锚点、像素比）精度 1/1024
extern const NSInteger AMapNormLengthScale;
extern const NSInteger AMapNormRatioScale;

/// 远离零的四舍五入到整数单位；非有限或超出 int32 返回 NO
BOOL AMapNormUnits(double v, NSInteger scale, int32_t *out);

/// 规范化后的长度换回整数单位（1/64 是二进制精确值，无误差），用于渲染 key
long long AMapLengthUnits(double normalized);

/// 通道里的 NSNull 视为缺省
id _Nullable AMapNonNull(id _Nullable v);

/// 读取并规范化字段。只记录第一个错误，之后的读取都返回默认值，调用方最后检查 error。
@interface AMapSpecReader : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *error;

- (void)require:(BOOL)ok message:(NSString *)message;

- (nullable NSDictionary *)map:(nullable NSDictionary *)m key:(NSString *)key required:(BOOL)required;

/// 必填长度（已规范化的逻辑像素）
- (double)length:(nullable NSDictionary *)m key:(NSString *)key;

/// 缺省时取 def
- (double)length:(nullable NSDictionary *)m key:(NSString *)key or:(double)def;

/// 可空长度
- (nullable NSNumber *)optLength:(nullable NSDictionary *)m key:(NSString *)key;

/// 定长数值数组（size / offset / insets），缺省返回 nil
- (nullable NSArray<NSNumber *> *)optLengths:(nullable NSDictionary *)m key:(NSString *)key count:(NSUInteger)n;

/// 比例值（1/1024）
- (double)ratio:(nullable id)v path:(NSString *)path;

/// ARGB 颜色：Dart 侧可能是 64 位整数，截成 32 位
- (nullable NSNumber *)optColor:(nullable NSDictionary *)m key:(NSString *)key;

- (uint32_t)color:(nullable NSDictionary *)m key:(NSString *)key;

- (nullable NSString *)optString:(nullable NSDictionary *)m key:(NSString *)key;

- (double)number:(nullable id)v path:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
