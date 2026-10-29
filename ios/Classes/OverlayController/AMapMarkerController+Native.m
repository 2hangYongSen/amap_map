//
//  AMapMarkerController+Native.m
//  amap_map
//
//  新协议（§6）：握手、完整替换、逐点拒绝、资源注册与 R-RES-12 恢复。全部在主线程。
//

#import "AMapMarkerController+Private.h"
#import "AMapMarker.h"
#import "AMapJsonUtils.h"
#import "AMapConvertUtil.h"
#import "AMapSpecReader.h"
#import "AMapNativeEventLog.h"
#import "AMapNativeMarkerView.h"
#import "MAAnnotationView+Flutter.h"
#import <objc/runtime.h>

static NSString *const kInvalidConfig = @"invalidConfig";
static NSString *const kImageMissing = @"imageMissing";
static NSString *const kApplyFailed = @"applyFailed";

@implementation AMapMarkerController (Native)

// ---------- 装配 ----------

- (void)setUpNative {
    self.initialRejected = [NSMutableArray array];
    self.generations = [NSMutableDictionary dictionary];
    self.imageIndex = [NSMutableDictionary dictionary];
    self.capErrorKeys = [NSMutableDictionary dictionary];
    self.layoutCache = [NSCache new];
    self.layoutCache.countLimit = 500;
    self.screenScale = UIScreen.mainScreen.scale;
    self.measurer = [AMapUIKitTextMeasurer new];
    self.selection = [AMapSelectionState new];
    if (self.registry == nil) {
        self.registry = [[AMapImageRegistry alloc] initWithDecoder:[self defaultDecoder]
                                                           runner:[AMapImageRegistry defaultRunner]
                                                           budget:8 * 1024 * 1024];
    }
    self.registry.listener = self;
    __weak typeof(self) weakSelf = self;
    self.events = [[AMapNativeEventLog alloc] initWithSink:^(NSString *method, NSDictionary *args) {
        [weakSelf.methodChannel invokeMethod:method arguments:args];
    }];
    self.diag = [[AMapMarkerDiagnostics alloc] initWithEvents:self.events];
    AMapImageRegistry *registry = self.registry;
    __weak AMapImageRegistry *weakRegistry = registry;
    self.diag.decodedBytes = ^NSUInteger { return [weakRegistry decodedBytes]; };
    self.diag.decodedOverBudget = ^BOOL { return [weakRegistry decodedOverBudget]; };
}

/// 后台解码：bytes 直接解码，asset 经 registrar 查找打包路径；UIImage.scale = pixelRatio
- (AMapImageDecoder)defaultDecoder {
    NSObject<FlutterPluginRegistrar> *registrar = self.registrar;
    return ^UIImage *(AMapImageSource *src, NSString **error) {
        NSData *data = src.data;
        if ([src.type isEqualToString:@"asset"]) {
            NSString *key = src.assetPackage
                ? [registrar lookupKeyForAsset:src.asset fromPackage:src.assetPackage]
                : [registrar lookupKeyForAsset:src.asset];
            NSString *path = [[NSBundle mainBundle] pathForResource:key ofType:nil];
            data = path ? [NSData dataWithContentsOfFile:path] : nil;
            if (data == nil) {
                *error = [@"asset 不可读: " stringByAppendingString:src.asset];
                return nil;
            }
        }
        UIImage *img = [UIImage imageWithData:data scale:src.pixelRatio];
        if (img == nil) {
            *error = @"图片数据无法解码";
            return nil;
        }
        // 在后台完成解压，避免首次显示时卡主线程
        if (@available(iOS 15.0, *)) {
            img = [img imageByPreparingForDisplay] ?: img;
        }
        return img;
    };
}

/// 绑定过的 native View（弱引用），资源恢复与点位修改时按它们重新绑定
- (NSHashTable<AMapNativeMarkerView *> *)boundViews {
    NSHashTable *t = objc_getAssociatedObject(self, @selector(boundViews));
    if (t == nil) {
        t = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(self, @selector(boundViews), t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return t;
}

// ---------- 握手与请求 ----------

- (NSDictionary *)attach {
    self.v2 = YES;
    NSDictionary *r = @{
        @"protocolVersion": @2,
        @"syncId": @(self.lastSyncId),
        @"rejectedMarkerIds": [self.initialRejected copy],
        @"images": [self.registry snapshot],
        @"selection": [self.selection snapshot],
        @"lastEventSeq": @(self.events.lastEventSeq),
        @"errors": [self.events errorsSnapshot],
        @"errorsDropped": @(self.events.errorsDropped),
    };
    [self.events open]; // 生成快照与打开事件开关在同一次调用内（R-INIT-4）
    return r;
}

- (void)applyCreationParams:(NSDictionary *)params {
    if (self.disposed) {
        return;
    }
    self.v2 = YES;
    [self applyMarkerOptions:params]; // 创建参数顶层带 markerSelection、markerTransition（§6.1）
    NSArray<AMapImageSource *> *images = [self parseImages:params key:@"imagesToAdd"];
    if (images == nil) {
        [self.events error:kInvalidConfig markerId:nil imageId:nil message:@"创建参数 imagesToAdd 结构错误"];
    }
    [self registerImages:images];
    for (id raw in AMapArray(params[@"markersToAdd"])) {
        NSString *id_ = AMapReadId(raw);
        if (id_ && ![self applyOne:raw markerId:id_]) {
            [self.initialRejected addObject:id_];
        }
    }
    [self syncTopAnnotation];
}

- (NSDictionary *)nativeUpdate:(id)args {
    NSInteger syncId = AMapReadSyncId(args);
    NSArray *images = self.disposed ? nil : [self parseImages:args key:@"imagesToAdd"];
    NSArray *releases = self.disposed ? nil : AMapStringsOrNil(args, @"imageIdsToRelease");
    if (images == nil || releases == nil || !AMapValidStructure(args, @[@"markersToAdd", @"markersToChange"])) {
        return [self result:syncId accepted:NO rejected:@[]];
    }
    self.v2 = YES;
    [self.initialRejected removeAllObjects];
    NSMutableArray *rejected = [NSMutableArray array];
    // t2 与标记方块在同一次主线程调用内（R-TIME-6）
    self.diagSync = [self.diag begin:syncId args:args];
    // 顺序：登记资源 → 删除 → 新增 → 修改 → 释放资源（§6.2）
    [self registerImages:images];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    for (id id_ in AMapArray(args[@"markerIdsToRemove"])) {
        if ([id_ isKindOfClass:[NSString class]] && [self removeOne:id_]) {
            [removed addObject:id_];
        }
    }
    self.pendingAdds = [NSMutableArray array];
    [self applyList:args[@"markersToAdd"] rejected:rejected];
    [self applyList:args[@"markersToChange"] rejected:rejected];
    [self flushPendingAdds];
    for (NSString *id_ in releases) {
        [self.registry releaseId:id_];
    }
    [self syncTopAnnotation]; // R-TOP-2/4：本次请求的坐标、内容、可见性、删除一并调和
    // 同一请求中又加回来的 id 不算删除
    [removed filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *id_, id b) {
        return self.markerDict[id_] == nil;
    }]];
    [self emitRemoved:removed syncId:syncId];
    self.lastSyncId = syncId;
    [self endDiagSync];
    return [self result:syncId accepted:YES rejected:rejected];
}

/// iOS 布局同步：外观在本次调用内已绑定，t4 记在返回前（t4 ≤ t3）
- (void)endDiagSync {
    AMapDiagSync *s = self.diagSync;
    self.diagSync = nil;
    [self.diag end:s];
}

/// 以快照为唯一期望状态：多余点位删除，不在资源列表中的资源进入 releasing（R-RES-9）
- (NSDictionary *)nativeResync:(id)args {
    NSInteger syncId = AMapReadSyncId(args);
    NSArray<AMapImageSource *> *images = self.disposed ? nil : [self parseImages:args key:@"images"];
    if (images == nil || !AMapValidStructure(args, @[@"markers"])) {
        return [self result:syncId accepted:NO rejected:@[]];
    }
    self.v2 = YES;
    [self.initialRejected removeAllObjects];
    self.diagSync = [self.diag begin:syncId args:args];
    [self registerImages:images];
    NSMutableSet *keep = [NSMutableSet set];
    for (id raw in AMapArray(args[@"markers"])) {
        [keep addObject:AMapReadId(raw)];
    }
    for (NSString *id_ in self.markerDict.allKeys) {
        if (![keep containsObject:id_]) {
            [self removeOne:id_];
        }
    }
    NSMutableArray *rejected = [NSMutableArray array];
    [self applyList:args[@"markers"] rejected:rejected];
    NSMutableSet *keepImages = [NSMutableSet set];
    for (AMapImageSource *s in images) {
        [keepImages addObject:s.id_];
    }
    [self.registry releaseAllExcept:keepImages];
    [self syncTopAnnotation]; // Dart 在 resync 返回时清空过渡条目，不发 markers#removed
    self.lastSyncId = syncId;
    [self endDiagSync];
    return [self result:syncId accepted:YES rejected:rejected];
}

- (NSDictionary *)result:(NSInteger)syncId accepted:(BOOL)accepted rejected:(NSArray *)rejected {
    return @{@"syncId": @(syncId), @"accepted": @(accepted), @"rejectedMarkerIds": rejected,
             @"imagesPending": accepted ? [self.registry pendingIds] : @[]};
}

- (void)dispose {
    if (self.disposed) {
        return;
    }
    self.disposed = YES;
    [self.diag setEnabled:NO]; // 隐藏标记方块、丢弃未完成的点击记录
    [self.events close];
    [self.registry dispose];
}

// ---------- 诊断命令（§13） ----------

- (nullable NSDictionary *)diagPing {
    return self.disposed ? nil : [self.diag ping];
}

/// 冷测试前清空布局缓存（iOS 没有合成位图缓存）；未开启返回 NO
- (BOOL)diagClearCaches {
    if (self.disposed || !self.diag.enabled) {
        return NO;
    }
    [self.layoutCache removeAllObjects];
    return YES;
}

// ---------- 单个点位 ----------

/// 把本次请求收集的新增 annotation 一次加到地图上
- (void)flushPendingAdds {
    NSArray *adds = self.pendingAdds;
    self.pendingAdds = nil;
    if (adds.count > 0) {
        [self.mapView addAnnotations:adds];
    }
}

- (void)applyList:(id)list rejected:(NSMutableArray *)rejected {
    for (id raw in AMapArray(list)) {
        NSString *id_ = AMapReadId(raw);
        if (![self applyOne:raw markerId:id_]) {
            [rejected addObject:id_];
        } else {
            // 旧路径点击：该点已按新图标更新（setIcon 等价）即记 c2（R-TIME-7）
            [self.diag touched:self.diagSync markerId:id_ isNative:self.markerDict[id_].isNative];
        }
    }
}

/// 先完整校验再修改（R-NAT-REJ-1）：拒绝时点位的模型、代次、显示都保持不变
- (BOOL)applyOne:(NSDictionary *)raw markerId:(NSString *)id_ {
    NSString *error = nil;
    AMapMarker *next = [self parseMarker:raw error:&error];
    if (next == nil) {
        [self.events error:kInvalidConfig markerId:id_ imageId:nil message:error ?: @"点位非法"];
        return NO;
    }
    next.generation = self.generations[id_].integerValue + 1;
    self.generations[id_] = @(next.generation);
    AMapMarker *current = self.markerDict[id_];
    BOOL wasSelectable = current.selectable;
    NSArray<NSString *> *oldImages = current.heldImageIds ?: @[];
    [self holdImages:next];
    // 模式切换或 zIndex 变化（运行中改 zIndex 无效，E-I0）时换一个 annotation 重新添加
    BOOL reAdd = current == nil || current.isNative != next.isNative || current.zIndex != next.zIndex;
    if (reAdd) {
        [self detachViewsOf:id_];
        if (current) {
            [self.pendingAdds removeObject:current.annotation]; // 同一请求内先加后换：旧的还没上地图
            [self.mapView removeAnnotation:current.annotation];
        }
        self.markerDict[id_] = next;
        if (self.pendingAdds) {
            [self.pendingAdds addObject:next.annotation];
        } else {
            [self.mapView addAnnotation:next.annotation];
        }
    } else {
        [current replaceWithMarker:next];
        current.icon = next.icon;
        current.image = next.image;
        [self refreshViewsOf:current];
    }
    [self dropImages:oldImages markerId:id_];
    [self reportCapOverflow:self.markerDict[id_]];
    // R-SEL-7：选中点由可选中改为不可选中才取消（API 选中的非 selectable 点不受影响）
    if ([id_ isEqualToString:self.selection.selectedId] && wasSelectable && !next.selectable) {
        [self commitSelection:[self.selection set:nil reason:AMapSelectionReasonInvalidated]];
    }
    return YES;
}

/// R-PROTO-1/2 防御性校验并解析；缺失或 null 字段一律取默认值（modelFromDict 从默认模型出发）
- (AMapMarker *)parseMarker:(NSDictionary *)raw error:(NSString **)error {
    id mode = raw[@"renderMode"];
    BOOL isNative = [@"native" isEqual:mode];
    id presentation = AMapNonNull(raw[@"nativePresentation"]);
    id icon = AMapNonNull(raw[@"icon"]);
    NSArray *pos = AMapNonNull(raw[@"position"]);
    NSString *reason = nil;
    if (!isNative && ![@"icon" isEqual:mode]) {
        reason = [NSString stringWithFormat:@"renderMode 缺失或非法: %@", mode];
    } else if (isNative && (![presentation isKindOfClass:[NSDictionary class]] || icon != nil)) {
        reason = @"native 模式必须带 nativePresentation 且 icon 为 null";
    } else if (!isNative && (![icon isKindOfClass:[NSArray class]] || presentation != nil)) {
        reason = @"icon 模式必须带 icon 且 nativePresentation 为 null";
    } else if (![pos isKindOfClass:[NSArray class]] || pos.count < 2) {
        reason = @"position 非法";
    }
    AMapNativeMarkerSpec *spec = nil;
    UIImage *image = nil;
    if (reason == nil && isNative) {
        spec = [AMapNativeMarkerSpec parse:presentation error:&reason];
    } else if (reason == nil) {
        @try {
            image = [AMapConvertUtil imageFromRegistrar:self.registrar iconData:icon];
        } @catch (NSException *ex) {
            reason = ex.reason ?: @"icon 无法解析";
        }
    }
    if (reason != nil) {
        *error = reason;
        return nil;
    }
    AMapMarker *m = [AMapJsonUtils modelFromDict:raw modelClass:[AMapMarker class]];
    m.renderMode = mode;
    m.presentation = isNative ? presentation : nil;
    m.spec = spec;
    m.icon = isNative ? nil : icon;
    m.image = image;
    m.selectedZIndex = [AMapNonNull(raw[@"selectedZIndex"]) isKindOfClass:[NSNumber class]] ? raw[@"selectedZIndex"] : nil;
    m.selectable = [@YES isEqual:raw[@"selectable"]];
    return m;
}

/// 选中点被删除时选择保留、不发事件（R-SEL-6）；高层 Annotation 由 syncTopAnnotation 移除（R-TOP-4）
- (BOOL)removeOne:(NSString *)id_ {
    AMapMarker *m = self.markerDict[id_];
    if (m == nil) {
        return NO;
    }
    self.generations[id_] = @(self.generations[id_].integerValue + 1);
    [self detachViewsOf:id_];
    [self.mapView removeAnnotation:m.annotation];
    [self.markerDict removeObjectForKey:id_];
    [self dropImages:m.heldImageIds ?: @[] markerId:id_];
    [self.capErrorKeys removeObjectForKey:id_];
    return YES;
}

// ---------- 资源引用（R-RES-1 期望引用、R-RES-12 反向索引） ----------

- (void)registerImages:(NSArray<AMapImageSource *> *)images {
    for (AMapImageSource *s in images) {
        [self.registry registerSource:s];
    }
}

/// 新快照先取引用，旧快照后归还，同一资源不会在中间被释放
- (void)holdImages:(AMapMarker *)m {
    NSMutableArray *held = [NSMutableArray array];
    for (NSString *imageId in m.isNative ? m.spec.imageIds : @[]) {
        if ([self.registry acquire:imageId kind:AMapImageRefDesired]) {
            [held addObject:imageId];
            NSMutableSet *set = self.imageIndex[imageId] ?: [NSMutableSet set];
            [set addObject:m.id_];
            self.imageIndex[imageId] = set;
        } else {
            [self.events error:kImageMissing markerId:m.id_ imageId:imageId
                       message:[@"资源未登记: " stringByAppendingString:imageId]];
        }
    }
    m.heldImageIds = held;
}

/// 归还旧快照取得的引用；同一点的新快照仍持有时保留反向索引
- (void)dropImages:(NSArray<NSString *> *)imageIds markerId:(NSString *)id_ {
    NSArray *nowHeld = self.markerDict[id_].heldImageIds ?: @[];
    for (NSString *imageId in imageIds) {
        if (![nowHeld containsObject:imageId]) {
            [self.imageIndex[imageId] removeObject:id_];
        }
        [self.registry unref:imageId kind:AMapImageRefDesired];
    }
}

/// 资源状态变化：发结果事件，引用它的点重新绑定（R-RES-7/12）
- (void)imageRegistryDidResolve:(NSString *)imageId {
    NSDictionary *failure = [self.registry failureOf:imageId];
    [self.events event:@"marker#imagesResult"
                  args:@{@"ready": failure ? @[] : @[imageId], @"failed": failure ? @[failure] : @[]}];
    if (failure) {
        [self.events error:failure[@"code"] markerId:nil imageId:imageId message:failure[@"message"]];
    }
    for (NSString *id_ in [self.imageIndex[imageId] copy]) {
        AMapMarker *m = self.markerDict[id_];
        if (m) {
            [self reportCapOverflow:m];
            [self refreshViewsOf:m];
        }
    }
}

/// R-NAT-REJ-2：九宫格超限保留期望快照、按默认背景显示，同一 normalKey 只报一次
- (void)reportCapOverflow:(AMapMarker *)m {
    if (!m.isNative) {
        return;
    }
    BOOL overflow = NO;
    for (AMapNativeMarkerStyle *s in @[m.spec.normal, m.spec.selectedOrNormal]) {
        CGSize size;
        overflow |= s.capInsets && [self.registry resolutionOf:s.imageId] == AMapImageResolutionReady
            && [self.registry logicalSizeOf:s.imageId size:&size] && !AMapCapInsetsFit(s.capInsets, size);
    }
    NSString *key = AMapNativeRenderKey(m.spec, self.screenScale, self.registry, NO);
    if (!overflow || [self.capErrorKeys[m.id_] isEqualToString:key]) {
        return;
    }
    self.capErrorKeys[m.id_] = key;
    [self.events error:kInvalidConfig markerId:m.id_ imageId:nil
               message:@"capInsets 超出图片逻辑尺寸（R-VAL-5），按默认背景显示"];
}

// ---------- View ----------

- (AMapNativeMarkerLayout *)layoutForMarker:(AMapMarker *)marker {
    NSString *key = AMapNativeRenderKey(marker.spec, self.screenScale, self.registry, NO);
    AMapNativeMarkerLayout *l = [self.layoutCache objectForKey:key];
    if (l == nil) {
        l = [AMapNativeMarkerLayout layoutWithSpec:marker.spec measurer:self.measurer resolver:self.registry];
        [self.layoutCache setObject:l forKey:key];
        self.diag.layoutMisses++; // 回执 drawCount / cacheMisses
    } else {
        self.diag.layoutHits++;
    }
    return l;
}

- (MAAnnotationView *)nativeViewForMarker:(AMapMarker *)marker mapView:(MAMapView *)mapView {
    AMapNativeMarkerView *view = (AMapNativeMarkerView *)[mapView dequeueReusableAnnotationViewWithIdentifier:AMapFlutterNativeMarkerViewIdentifier];
    if (view == nil) {
        view = [[AMapNativeMarkerView alloc] initWithAnnotation:marker.annotation
                                                reuseIdentifier:AMapFlutterNativeMarkerViewIdentifier];
    } else {
        view.annotation = marker.annotation;
    }
    [self bindNativeView:view marker:marker];
    return view;
}

- (void)bindNativeView:(AMapNativeMarkerView *)view marker:(AMapMarker *)marker {
    // 高层 View 按选中态绑定；源点 View 一律普通态（选中时被隐藏，R-TOP-1）
    BOOL isTop = [view.annotation isKindOfClass:[AMapSelectionAnnotation class]];
    [view bindMarker:marker layout:[self layoutForMarker:marker] selected:isTop registry:self.registry];
    [self applyTopRules:view marker:marker isTop:isTop];
    [[self boundViews] addObject:view];
}

- (void)refreshViewsOf:(AMapMarker *)m {
    for (AMapNativeMarkerView *v in [[self boundViews] allObjects]) {
        if ([v.boundMarkerId isEqualToString:m.id_]) {
            [self bindNativeView:v marker:m];
        }
    }
    if (!m.isNative) {
        MAAnnotationView *view = [self.mapView viewForAnnotation:m.annotation];
        [view updateViewWithMarker:m];
    }
}

/// 点位删除或换 annotation：View 立即归还显示引用（R-RES-1）
- (void)detachViewsOf:(NSString *)id_ {
    for (AMapNativeMarkerView *v in [[self boundViews] allObjects]) {
        if ([v.boundMarkerId isEqualToString:id_]) {
            [v unbind];
            [[self boundViews] removeObject:v];
        }
    }
}

// ---------- 载荷工具 ----------

- (NSArray<AMapImageSource *> *)parseImages:(id)args key:(NSString *)key {
    id v = [args isKindOfClass:[NSDictionary class]] ? AMapNonNull(args[key]) : nil;
    if (v == nil) {
        return @[];
    }
    if (![v isKindOfClass:[NSArray class]]) {
        return nil;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (id raw in (NSArray *)v) {
        AMapImageSource *s = [AMapImageSource parse:raw error:nil];
        if (s == nil) {
            return nil;
        }
        [out addObject:s];
    }
    return out;
}

static NSArray *AMapArray(id v) {
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static NSString *AMapReadId(id raw) {
    if (![raw isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id v = raw[@"id"];
    return [v isKindOfClass:[NSString class]] && [v length] > 0 ? v : nil;
}

static NSInteger AMapReadSyncId(id args) {
    id v = [args isKindOfClass:[NSDictionary class]] ? args[@"syncId"] : nil;
    return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : 0;
}

static NSArray<NSString *> *AMapStringsOrNil(id args, NSString *key) {
    id v = [args isKindOfClass:[NSDictionary class]] ? AMapNonNull(args[key]) : nil;
    if (v == nil) {
        return @[];
    }
    if (![v isKindOfClass:[NSArray class]]) {
        return nil;
    }
    return [(NSArray *)v filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id o, id b) { return [o isKindOfClass:[NSString class]]; }]];
}

/// 结构检查：列表键必须是数组，每个点位必须带可回报的 id，否则整个请求 accepted=false
static BOOL AMapValidStructure(id args, NSArray<NSString *> *keys) {
    if (![args isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    for (NSString *key in keys) {
        id v = AMapNonNull(args[key]);
        if (v == nil) {
            continue;
        }
        if (![v isKindOfClass:[NSArray class]]) {
            return NO;
        }
        for (id raw in (NSArray *)v) {
            if (AMapReadId(raw) == nil) {
                return NO;
            }
        }
    }
    id removes = AMapNonNull(args[@"markerIdsToRemove"]);
    return removes == nil || [removes isKindOfClass:[NSArray class]];
}

@end
