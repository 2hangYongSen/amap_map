//
//  AMapMarkerController+Selection.m
//  amap_map
//
//  原生单选（§11）与选中置顶（§10.2 R-TOP 系列）。全部在主线程。
//  选择状态只由 AMapSelectionState 决定，不读取 SDK 自带的 selected 状态。
//

#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapNativeEventLog.h"
#import "AMapNativeMarkerView.h"

@implementation AMapMarkerController (Selection)

// ---------- 选择命令与事件 ----------

/// markers#setSelected：返回提交后的 revision；id 相同不发事件（R-SEL-4）
- (NSDictionary *)setSelectedFromArgs:(id)args {
    id markerId = [args isKindOfClass:[NSDictionary class]] ? args[@"markerId"] : nil;
    self.v2 = YES;
    if (!self.disposed) {
        [self commitSelection:[self.selection set:[markerId isKindOfClass:[NSString class]] ? markerId : nil
                                           reason:AMapSelectionReasonApi]];
    }
    return @{@"revision": @(self.selection.revision)};
}

/// R-SEL-1：先发事件，再更新外观（iOS 布局是同步的，外观在同一调用内补齐）
- (void)commitSelection:(AMapSelectionChange *)change {
    if (change == nil) {
        return;
    }
    NSMutableDictionary *args = [[change toMap] mutableCopy];
    if (self.currentTapId) {
        args[@"tapId"] = self.currentTapId; // 仅诊断模式（R-TIME-2）
    }
    [self.events event:@"marker#selectionChanged" args:args];
    [self syncTopAnnotation];
    // 新路径：外观已在本次调用内绑定到高层 View 或源点 View，即为 c2（R-TIME-7）
    [self.diag tapAppliedNative:self.currentTapId];
}

/// 点位点击（R-SEL-2/3）：先提交选择并发 selectionChanged，再由调用方发 marker#onTap
- (void)selectionOnMarkerTap:(NSString *)markerId {
    if (self.v2 && !self.disposed) {
        [self commitSelection:[self.selection onMarkerTap:markerId selectable:self.markerDict[markerId].selectable]];
    }
}

/// 地图空白处单击（R-SEL-2）；点击启用的 View 时 SDK 不回调这里（E-I2），不需要去重
- (void)onMapTap {
    if (self.v2 && !self.disposed) {
        [self commitSelection:[self.selection onMapTap]];
    }
}

/// map#update.options 与创建参数中的 markerSelection、markerTransition；键缺失不改
- (void)applyMarkerOptions:(id)options {
    if (![options isKindOfClass:[NSDictionary class]] || self.disposed) {
        return;
    }
    id sel = options[@"markerSelection"];
    if (sel != nil) {
        [self.selection configure:sel];
    }
    id tr = options[@"markerTransition"];
    if (tr != nil) {
        self.replaceTransition = [tr isKindOfClass:[NSDictionary class]]
            && [@"replaceWhenReady" isEqual:tr[@"mode"]];
    }
    id diag = options[@"markerDiagnostics"];
    if (diag != nil) {
        [self.diag setEnabled:[@YES isEqual:diag]];
    }
}

/// R-DEL-6：iOS 删除在本次调用中完成；replaceWhenReady 下仍发 markers#removed，Dart 两端共用释放逻辑
- (void)emitRemoved:(NSArray<NSString *> *)ids syncId:(NSInteger)syncId {
    if (!self.replaceTransition || ids.count == 0) {
        return;
    }
    NSMutableArray *syncIds = [NSMutableArray arrayWithCapacity:ids.count];
    for (NSUInteger i = 0; i < ids.count; i++) {
        [syncIds addObject:@(syncId)];
    }
    [self.events event:@"markers#removed" args:@{@"markerIds": ids, @"removeSyncIds": syncIds}];
}

// ---------- 高层 Annotation（R-TOP-1～6） ----------

/// 按当前选择与期望快照调和高层 Annotation；每次选择变化、每次点位请求结束时调用
- (void)syncTopAnnotation {
    NSString *sid = self.selection.selectedId;
    AMapMarker *m = sid ? self.markerDict[sid] : nil;
    // R-TOP-1 显示条件：在集合中、期望可见、原生渲染模式
    BOOL want = m != nil && m.isNative && m.visible;
    NSInteger z = want ? (NSInteger)(m.selectedZIndex ? m.selectedZIndex.doubleValue : m.zIndex) : 0;
    AMapSelectionAnnotation *cur = self.topAnnotation;
    // 选择改变、不再满足条件或选中 zIndex 变化（运行中改 zIndex 无效，E-I0）：移除后按需重新添加
    if (cur && (!want || ![cur.sourceMarkerId isEqualToString:sid] || cur.zIndex != z)) {
        [self removeTopAnnotation];
    }
    if (!want) {
        return;
    }
    if (self.topAnnotation == nil) {
        AMapSelectionAnnotation *a = [[AMapSelectionAnnotation alloc] initWithSource:sid zIndex:z];
        a.coordinate = m.position;
        self.topAnnotation = a;
        [self hideSourceViewsOf:sid];
        [self.mapView addAnnotation:a];
        return;
    }
    // R-TOP-2：坐标同步；内容或样式变化时重新绑定高层 View
    self.topAnnotation.coordinate = m.position;
    AMapNativeMarkerView *tv = [self liveTopView];
    if (tv) {
        [self bindNativeView:tv marker:m];
    }
}

/// 高层 View 可能已被 SDK 回收并复用到别的 Annotation 上，只认仍挂在高层 Annotation 上的
- (AMapNativeMarkerView *)liveTopView {
    AMapNativeMarkerView *v = self.topView;
    return v != nil && v.annotation == self.topAnnotation ? v : nil;
}

/// R-TOP-3：移除高层 Annotation，源点按期望快照重新绑定（hidden = !visible，不一律取消隐藏）
- (void)removeTopAnnotation {
    AMapNativeMarkerView *v = [self liveTopView];
    AMapSelectionAnnotation *a = self.topAnnotation;
    self.topAnnotation = nil;
    self.topView = nil;
    if (v) {
        [v unbind]; // 立即归还显示引用（R-RES-1）
        [[self boundViews] removeObject:v];
    }
    [self.mapView removeAnnotation:a];
    AMapMarker *src = self.markerDict[a.sourceMarkerId];
    if (src) {
        // 已被复用到别的 Annotation 的 View 已解绑，不会被这里改动
        [self refreshViewsOf:src];
    }
}

- (void)hideSourceViewsOf:(NSString *)markerId {
    for (AMapNativeMarkerView *v in [[self boundViews] allObjects]) {
        if (![v.annotation isKindOfClass:[AMapSelectionAnnotation class]] && [v.boundMarkerId isEqualToString:markerId]) {
            v.hidden = YES;
        }
    }
}

/// 绑定后的置顶规则：高层 View 用选中 zIndex、不可拖动；源点 View 在高层展示期间保持隐藏（R-TOP-6）
- (void)applyTopRules:(AMapNativeMarkerView *)view marker:(AMapMarker *)marker isTop:(BOOL)isTop {
    if (isTop) {
        view.zIndex = ((AMapSelectionAnnotation *)view.annotation).zIndex;
        view.draggable = NO;
        return;
    }
    if ([self.topAnnotation.sourceMarkerId isEqualToString:marker.id_]) {
        view.hidden = YES;
    }
}

- (MAAnnotationView *)nativeViewForSelectionAnnotation:(AMapSelectionAnnotation *)annotation
                                               mapView:(MAMapView *)mapView {
    AMapMarker *m = self.markerDict[annotation.sourceMarkerId];
    if (annotation != self.topAnnotation || m == nil || !m.isNative) {
        return nil; // 已过期的高层 Annotation（移除前的回调）
    }
    AMapNativeMarkerView *view = (AMapNativeMarkerView *)[mapView dequeueReusableAnnotationViewWithIdentifier:AMapFlutterNativeMarkerViewIdentifier];
    if (view == nil) {
        view = [[AMapNativeMarkerView alloc] initWithAnnotation:annotation
                                                reuseIdentifier:AMapFlutterNativeMarkerViewIdentifier];
    } else {
        view.annotation = annotation;
    }
    self.topView = view;
    [self bindNativeView:view marker:m];
    return view;
}

- (void)rebindSelectionView:(AMapNativeMarkerView *)view {
    AMapSelectionAnnotation *a = (AMapSelectionAnnotation *)view.annotation;
    AMapMarker *m = self.markerDict[a.sourceMarkerId];
    if (a == self.topAnnotation && m.isNative) {
        self.topView = view;
        [self bindNativeView:view marker:m];
    }
}

@end
