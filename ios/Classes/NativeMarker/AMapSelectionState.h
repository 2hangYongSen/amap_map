//
//  AMapSelectionState.h
//  amap_map
//
//  原生单选状态（§11）：每张地图一份，主线程访问。只做状态与规则判断，
//  外观由调用方按返回的变化更新。与 Android SelectionState 一致。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const AMapSelectionReasonMarkerTap;
extern NSString *const AMapSelectionReasonRetap;
extern NSString *const AMapSelectionReasonMapTap;
extern NSString *const AMapSelectionReasonApi;
extern NSString *const AMapSelectionReasonInvalidated;

/// 一次选择变化（marker#selectionChanged 的业务字段）
@interface AMapSelectionChange : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *selectedId;
@property (nonatomic, readonly, copy, nullable) NSString *previousId;
@property (nonatomic, readonly, copy) NSString *reason;
@property (nonatomic, readonly) NSInteger revision;
- (NSDictionary *)toMap;
@end

@interface AMapSelectionState : NSObject

@property (nonatomic, readonly, copy, nullable) NSString *selectedId;
@property (nonatomic, readonly) NSInteger revision;
/// markerSelection 非空才启用自动选择（点击、地图单击）
@property (nonatomic, readonly) BOOL autoEnabled;

/// markerSelection 选项：非字典（含 NSNull）关闭自动选择，已有选择保留
- (void)configure:(nullable id)raw;

/// R-SEL-1/4：id 相同返回 nil（revision 不变、不发事件）
- (nullable AMapSelectionChange *)set:(nullable NSString *)markerId reason:(NSString *)reason;

/// R-SEL-2 点位点击；未启用或非 selectable 点不改变选择
- (nullable AMapSelectionChange *)onMarkerTap:(NSString *)markerId selectable:(BOOL)selectable;

/// R-SEL-2 地图空白处单击
- (nullable AMapSelectionChange *)onMapTap;

/// markers#attach 快照
- (NSDictionary *)snapshot;

@end

NS_ASSUME_NONNULL_END
