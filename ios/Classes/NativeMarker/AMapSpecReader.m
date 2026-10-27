//
//  AMapSpecReader.m
//  amap_map
//

#import "AMapSpecReader.h"

const NSInteger AMapNormLengthScale = 64;
const NSInteger AMapNormRatioScale = 1024;

BOOL AMapNormUnits(double v, NSInteger scale, int32_t *out) {
    double scaled = v * scale;
    if (!isfinite(v) || !isfinite(scaled)) {
        return NO;
    }
    // 不用 round()/floor(x+0.5)：后者对 0.49999999999999994 会错误进位
    double a = fabs(scaled);
    double f = floor(a);
    double r = f + ((a - f) >= 0.5 ? 1 : 0);
    if (r > INT32_MAX) {
        return NO;
    }
    *out = (int32_t)(scaled < 0 ? -r : r);
    return YES;
}

long long AMapLengthUnits(double normalized) {
    return llround(normalized * AMapNormLengthScale);
}

id AMapNonNull(id v) {
    return v == [NSNull null] ? nil : v;
}

@implementation AMapSpecReader {
    NSString *_error;
}

- (NSString *)error {
    return _error;
}

- (void)require:(BOOL)ok message:(NSString *)message {
    if (!ok && _error == nil) {
        _error = [message copy];
    }
}

- (NSDictionary *)map:(NSDictionary *)m key:(NSString *)key required:(BOOL)required {
    id v = AMapNonNull(m[key]);
    if (v == nil && !required) {
        return nil;
    }
    if (![v isKindOfClass:[NSDictionary class]]) {
        [self require:NO message:[key stringByAppendingString:@" 必须是对象"]];
        return nil;
    }
    return v;
}

- (double)number:(id)v path:(NSString *)path {
    // NSNumber 里的 BOOL 不算数值
    if (![v isKindOfClass:[NSNumber class]] || v == (id)kCFBooleanTrue || v == (id)kCFBooleanFalse) {
        [self require:NO message:[path stringByAppendingString:@" 必须是数值"]];
        return 0;
    }
    return [v doubleValue];
}

- (double)normalize:(double)v scale:(NSInteger)scale path:(NSString *)path {
    int32_t units = 0;
    if (!AMapNormUnits(v, scale, &units)) {
        [self require:NO message:[NSString stringWithFormat:@"%@ 必须是有限数值: %g", path, v]];
        return 0;
    }
    return units / (double)scale;
}

- (double)length:(NSDictionary *)m key:(NSString *)key {
    return [self normalize:[self number:AMapNonNull(m[key]) path:key] scale:AMapNormLengthScale path:key];
}

- (double)length:(NSDictionary *)m key:(NSString *)key or:(double)def {
    id v = AMapNonNull(m[key]);
    double raw = v == nil ? def : [self number:v path:key];
    return [self normalize:raw scale:AMapNormLengthScale path:key];
}

- (NSNumber *)optLength:(NSDictionary *)m key:(NSString *)key {
    id v = AMapNonNull(m[key]);
    return v == nil ? nil : @([self length:m key:key]);
}

- (NSArray<NSNumber *> *)optLengths:(NSDictionary *)m key:(NSString *)key count:(NSUInteger)n {
    id v = AMapNonNull(m[key]);
    if (v == nil) {
        return nil;
    }
    if (![v isKindOfClass:[NSArray class]] || [v count] != n) {
        [self require:NO message:[NSString stringWithFormat:@"%@ 必须是长度为 %lu 的数组", key, (unsigned long)n]];
        return nil;
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:n];
    for (id item in (NSArray *)v) {
        [out addObject:@([self normalize:[self number:item path:key] scale:AMapNormLengthScale path:key])];
    }
    return out;
}

- (double)ratio:(id)v path:(NSString *)path {
    return [self normalize:[self number:v path:path] scale:AMapNormRatioScale path:path];
}

- (NSNumber *)optColor:(NSDictionary *)m key:(NSString *)key {
    id v = AMapNonNull(m[key]);
    if (v == nil) {
        return nil;
    }
    if (![v isKindOfClass:[NSNumber class]]) {
        [self require:NO message:[key stringByAppendingString:@" 必须是 ARGB 整数"]];
        return nil;
    }
    return @((uint32_t)[v longLongValue]);
}

- (uint32_t)color:(NSDictionary *)m key:(NSString *)key {
    NSNumber *c = [self optColor:m key:key];
    [self require:c != nil message:[key stringByAppendingString:@" 不能为空"]];
    return c.unsignedIntValue;
}

- (NSString *)optString:(NSDictionary *)m key:(NSString *)key {
    id v = AMapNonNull(m[key]);
    if (v != nil && ![v isKindOfClass:[NSString class]]) {
        [self require:NO message:[key stringByAppendingString:@" 必须是字符串"]];
        return nil;
    }
    return v;
}

@end
