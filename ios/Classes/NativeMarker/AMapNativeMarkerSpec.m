//
//  AMapNativeMarkerSpec.m
//  amap_map
//

#import "AMapNativeMarkerSpec.h"
#import "AMapNativeMarkerSpec+Private.h"
#import "AMapSpecReader.h"

@implementation AMapNativeMarkerSpec

+ (instancetype)parse:(id)presentation error:(NSString **)error {
    if (![presentation isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"nativePresentation 不能为空";
        return nil;
    }
    AMapSpecReader *r = [AMapSpecReader new];
    AMapNativeMarkerSpec *spec = [[self alloc] initWithDict:presentation reader:r];
    if (r.error != nil) {
        if (error) *error = r.error;
        return nil;
    }
    return spec;
}

- (instancetype)initWithDict:(NSDictionary *)p reader:(AMapSpecReader *)r {
    self = [super init];
    NSDictionary *c = [r map:p key:@"content" required:YES];
    NSString *t = [r optString:c key:@"text"];
    _text = t.length == 0 ? nil : t;
    _iconId = [r optString:c key:@"iconId"];
    _iconSize = [r optLengths:c key:@"iconSize" count:2];
    _iconSpacing = [r length:c key:@"iconSpacing" or:4];
    NSDictionary *style = [r map:p key:@"style" required:YES];
    _normal = [[AMapNativeMarkerStyle alloc] initWithDict:style ?: @{} reader:r];
    NSDictionary *sel = [r map:p key:@"selectedStyle" required:NO];
    _selected = sel == nil ? nil : [[AMapNativeMarkerStyle alloc] initWithDict:sel reader:r];
    id type = AMapNonNull(p[@"anchorType"]);
    if (type == nil || [@"bodyCenter" isEqual:type]) {
        _anchorType = AMapNativeAnchorBodyCenter;
    } else if ([@"arrowTip" isEqual:type]) {
        _anchorType = AMapNativeAnchorArrowTip;
    } else {
        [r require:[@"custom" isEqual:type] message:[NSString stringWithFormat:@"anchorType 非法: %@", type]];
        _anchorType = AMapNativeAnchorCustom;
    }
    if (_anchorType == AMapNativeAnchorCustom) {
        id raw = AMapNonNull(p[@"anchor"]);
        BOOL ok = [raw isKindOfClass:[NSArray class]] && [raw count] == 2;
        [r require:ok message:@"custom 锚点必须提供 anchor"];
        if (ok) {
            _anchorDx = [r ratio:raw[0] path:@"anchor"];
            _anchorDy = [r ratio:raw[1] path:@"anchor"];
        }
    }
    [self validate:r];
    return self;
}

/// R-VAL-6/8、D-4 与内容字段的防御性校验
- (void)validate:(AMapSpecReader *)r {
    [r require:_text != nil || _iconId != nil message:@"text 与 iconId 至少提供一个"];
    [r require:_text == nil || ([_text rangeOfCharacterFromSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"\n\r"]].location == NSNotFound)
       message:@"text 不能包含换行符"];
    [r require:_iconSpacing >= 0 message:@"iconSpacing 不能为负"];
    [r require:_iconSize == nil || (_iconSize[0].doubleValue >= 0 && _iconSize[1].doubleValue >= 0)
       message:@"iconSize 不能为负"];
    if (_anchorType == AMapNativeAnchorCustom) {
        [r require:_anchorDx >= 0 && _anchorDx <= 1 && _anchorDy >= 0 && _anchorDy <= 1
           message:@"anchor 取值必须在 0 到 1 之间"];
    }
    // R-ANC-1：只要求普通态有箭头
    [r require:_anchorType != AMapNativeAnchorArrowTip || _normal.hasArrow
       message:@"arrowTip 锚点要求普通态设置箭头"];
}

- (AMapNativeMarkerStyle *)selectedOrNormal {
    return _selected ?: _normal;
}

- (NSArray<NSString *> *)imageIds {
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    if (_iconId) [ids addObject:_iconId];
    if (_normal.isImage) [ids addObject:_normal.imageId];
    if (_selected.isImage) [ids addObject:_selected.imageId];
    return [ids.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (void)appendKey:(NSMutableString *)k {
    [k appendFormat:@"content|%lu:%@|%@|", (unsigned long)_text.length, _text ?: @"~", _iconId ?: @"~"];
    if (_iconSize) {
        [k appendFormat:@"%lld,%lld|", AMapLengthUnits(_iconSize[0].doubleValue), AMapLengthUnits(_iconSize[1].doubleValue)];
    } else {
        [k appendString:@"~|"];
    }
    [k appendFormat:@"%lld|normal|", AMapLengthUnits(_iconSpacing)];
    [_normal appendKey:k];
    [k appendString:@"selected|"];
    if (_selected) {
        [_selected appendKey:k];
    } else {
        [k appendString:@"=normal|"];
    }
    [k appendFormat:@"anchor|%ld|%lld|%lld|", (long)_anchorType,
     llround(_anchorDx * AMapNormRatioScale), llround(_anchorDy * AMapNormRatioScale)];
}

@end
