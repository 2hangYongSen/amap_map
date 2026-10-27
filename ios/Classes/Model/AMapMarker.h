//
//  AMapMarker.h
//  amap_map
//
//  Created by lly on 2020/11/3.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MAMapKit/MAMapKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AMapInfoWindow;
@class AMapNativeMarkerSpec;

@interface AMapMarker : NSObject

@property (nonatomic, copy) NSString *id_;

@property (nonatomic, assign) double alpha;

@property (nonatomic, assign) CGPoint anchor;

//原始的图片BitmapDescriptor的json存储结构
@property (nonatomic, copy) NSArray *icon;

//解析后的图片
@property (nonatomic, strong) UIImage *image;

@property (nonatomic, assign) bool clickable;

@property (nonatomic, assign) bool draggable;

@property (nonatomic, assign) bool flat;

@property (nonatomic, assign) bool infoWindowEnable;

@property (nonatomic, strong) AMapInfoWindow *infoWindow;

@property (nonatomic, assign) CLLocationCoordinate2D position;

@property (nonatomic, assign) double rotation;

@property (nonatomic, assign) bool visible;

@property (nonatomic, assign) double zIndex;

// ---- 新协议（§6.3）：旧格式载荷不含这些键，保持默认值 ----

/// icon / native；旧协议登记的点为 nil，按 icon 处理（R-PROTO-1a）
@property (nonatomic, copy, nullable) NSString *renderMode;

@property (nonatomic, assign) bool selectable;

/// 为空表示沿用 zIndex
@property (nonatomic, strong, nullable) NSNumber *selectedZIndex;

/// 原始 presentation（键名与载荷不同，不经过 modelFromDict 反射映射，R-IOS-3）
@property (nonatomic, copy, nullable) NSDictionary *presentation;

/// presentation 的规范化规格（R-NORM-1），native 模式非空
@property (nonatomic, strong, nullable) AMapNativeMarkerSpec *spec;

/// 点位代次：每次新增、修改、删除自增，删除后重新加入继续递增（R-TOP-2）
@property (nonatomic, assign) NSInteger generation;

/// 本快照实际取得期望引用的资源（未登记的不在其中），归还时以此为准
@property (nonatomic, copy, nullable) NSArray<NSString *> *heldImageIds;

- (BOOL)isNative;

//根据以上marker信息生成的对应的iOS端的Annotation
@property (nonatomic, strong, readonly) MAPointAnnotation *annotation;


/// 更新marker的信息
/// @param changedMarker 带修改信息的marker
- (void)updateMarker:(AMapMarker *)changedMarker;

/// 新协议同模式整体替换：复制 updateMarker 的字段与新字段，保留已添加的 annotation
- (void)replaceWithMarker:(AMapMarker *)changedMarker;

@end

NS_ASSUME_NONNULL_END
