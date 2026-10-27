//
//  AMapMarkerController.m
//  amap_map
//
//  Created by lly on 2020/11/3.
//

#import "AMapMarkerController.h"
#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapJsonUtils.h"
#import "AMapConvertUtil.h"
#import "MAAnnotationView+Flutter.h"
#import "FlutterMethodChannel+MethodCallDispatch.h"

@implementation AMapMarkerController

- (instancetype)init:(FlutterMethodChannel*)methodChannel
             mapView:(MAMapView*)mapView
           registrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    return [self init:methodChannel mapView:mapView registrar:registrar registry:nil];
}

- (instancetype)init:(FlutterMethodChannel*)methodChannel
             mapView:(MAMapView*)mapView
           registrar:(NSObject<FlutterPluginRegistrar>*)registrar
            registry:(AMapImageRegistry *)registry {
    self = [super init];
    if (self) {
        _methodChannel = methodChannel;
        _mapView = mapView;
        _markerDict = [NSMutableDictionary dictionaryWithCapacity:1];
        _registrar = registrar;
        _registry = registry;
        [self setUpNative];
        
        __weak typeof(self) weakSelf = self;
        [_methodChannel addMethodName:@"markers#attach" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            if (weakSelf == nil || weakSelf.disposed) {
                result([FlutterError errorWithCode:@"disposed" message:@"map disposed" details:nil]);
                return;
            }
            result([weakSelf attach]);
        }];
        [_methodChannel addMethodName:@"markers#setSelected" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            result([weakSelf setSelectedFromArgs:call.arguments]);
        }];
        [_methodChannel addMethodName:@"markers#resync" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            result([weakSelf nativeResync:call.arguments]);
        }];
        [_methodChannel addMethodName:@"markers#update" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            // 按 protocolVersion 分流：不带即旧格式，行为与 1.0.15 相同（R-PROTO-3）
            if ([AMapMarkerController isV2Payload:call.arguments]) {
                result([weakSelf nativeUpdate:call.arguments]);
                return;
            }
            if (weakSelf.disposed) {
                result(nil);
                return;
            }
            id markersToAdd = call.arguments[@"markersToAdd"];
            if ([markersToAdd isKindOfClass:[NSArray class]]) {
                [weakSelf addMarkers:markersToAdd];
            }
            id markersToChange = call.arguments[@"markersToChange"];
            if ([markersToChange isKindOfClass:[NSArray class]]) {
                [weakSelf changeMarkers:markersToChange];
            }
            id markerIdsToRemove = call.arguments[@"markerIdsToRemove"];
            if ([markerIdsToRemove isKindOfClass:[NSArray class]]) {
                [weakSelf removeMarkerIds:markerIdsToRemove];
            }
            result(nil);
        }];
    }
    return self;
}

+ (BOOL)isV2Payload:(id)args {
    if (![args isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    id v = args[@"protocolVersion"];
    return [v isKindOfClass:[NSNumber class]] && [v integerValue] >= 2;
}

- (nullable AMapMarker *)markerForId:(NSString *)markerId {
    return _markerDict[markerId];
}

- (void)addMarkers:(NSArray*)markersToAdd {
    for (NSDictionary* marker in markersToAdd) {
        AMapMarker *markerModel = [AMapJsonUtils modelFromDict:marker modelClass:[AMapMarker class]];
        //从bitmapDesc中解析UIImage
        if (markerModel.icon) {
            markerModel.image = [AMapConvertUtil imageFromRegistrar:self.registrar iconData:markerModel.icon];
        }
        // 先加入到字段中，避免后续的地图回到里，取不到对应的marker数据
        if (markerModel.id_) {
            _markerDict[markerModel.id_] = markerModel;
        }
        [self.mapView addAnnotation:markerModel.annotation];
    }
}

- (void)changeMarkers:(NSArray*)markersToChange {
    for (NSDictionary* markerToChange in markersToChange) {
        NSLog(@"changeMarker:%@",markerToChange);
        AMapMarker *markerModelToChange = [AMapJsonUtils modelFromDict:markerToChange modelClass:[AMapMarker class]];
        AMapMarker *currentMarkerModel = _markerDict[markerModelToChange.id_];
        NSAssert(currentMarkerModel != nil, @"需要修改的marker不存在");
        
        //如果图标变了，则存储和解析新的图标
        if ([AMapConvertUtil checkIconDescriptionChangedFrom:currentMarkerModel.icon to:markerModelToChange.icon]) {
            UIImage *image = [AMapConvertUtil imageFromRegistrar:self.registrar iconData:markerModelToChange.icon];
            currentMarkerModel.icon = markerModelToChange.icon;
            currentMarkerModel.image = image;
        }
        //更新除了图标之外的其它信息
        [currentMarkerModel updateMarker:markerModelToChange];
        
        MAAnnotationView *view = [self.mapView viewForAnnotation:currentMarkerModel.annotation];
        if (view) {//如果可以获取到View，则立刻更新
            [view updateViewWithMarker:currentMarkerModel];
        } //获取不到时，则在viewDidAdd的回调中，重新更新view的效果；
    }
}

- (void)removeMarkerIds:(NSArray*)markerIdsToRemove {
    for (NSString* markerId in markerIdsToRemove) {
        if (!markerId) {
            continue;
        }
        AMapMarker* marker = _markerDict[markerId];
        if (!marker) {
            continue;
        }
        [self.mapView removeAnnotation:marker.annotation];
        [_markerDict removeObjectForKey:markerId];
    }
}

//MARK: Marker的回调

- (BOOL)onMarkerTap:(NSString*)markerId {
  if (!markerId) {
    return NO;
  }
  AMapMarker* marker = _markerDict[markerId];
  if (!marker) {
    return NO;
  }
  // R-SEL-3：先提交选择并发 selectionChanged，再发 marker#onTap（旧协议下无操作，R-SEL-9）
  [self selectionOnMarkerTap:markerId];
  [_methodChannel invokeMethod:@"marker#onTap" arguments:@{@"markerId" : markerId}];
  return YES;
}

- (BOOL)onMarker:(NSString *)markerId endPostion:(CLLocationCoordinate2D)position {
    if (!markerId) {
      return NO;
    }
    AMapMarker* marker = _markerDict[markerId];
    if (!marker) {
      return NO;
    }
    [_methodChannel invokeMethod:@"marker#onDragEnd"
                         arguments:@{@"markerId" : markerId, @"position" : [AMapConvertUtil jsonArrayFromCoordinate:position]}];
    return YES;
}

//- (BOOL)onInfoWindowTap:(NSString *)markerId {
//    if (!markerId) {
//      return NO;
//    }
//    AMapMarker* marker = _markerDict[markerId];
//    if (!marker) {
//      return NO;
//    }
//    [_methodChannel invokeMethod:@"infoWindow#onTap" arguments:@{@"markerId" : markerId}];
//    return YES;
//}



@end
