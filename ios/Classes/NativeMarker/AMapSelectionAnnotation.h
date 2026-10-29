//
//  AMapSelectionAnnotation.h
//  amap_map
//
//  选中置顶用的高层 Annotation（§10.2）：每张地图最多一个，不进入 markerDict，
//  不带 markerId（旧路径代理会跳过它），点击按 sourceMarkerId 映射（R-TOP-5）。
//

#import <MAMapKit/MAMapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapSelectionAnnotation : MAPointAnnotation

- (instancetype)initWithSource:(NSString *)sourceMarkerId zIndex:(NSInteger)zIndex;

@property (nonatomic, readonly, copy) NSString *sourceMarkerId;
/// 创建时的 zIndex；运行中改 zIndex 无效（E-I0），变化时换一个重新添加
@property (nonatomic, readonly) NSInteger zIndex;

@end

NS_ASSUME_NONNULL_END
