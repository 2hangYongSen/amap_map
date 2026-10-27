//
//  AMapNativeMarkerStyle.m
//  amap_map
//
//  单个状态的规范化样式，与 Android NormStyle 字段、校验、key 顺序一致。
//

#import "AMapNativeMarkerSpec.h"
#import "AMapNativeMarkerSpec+Private.h"
#import "AMapSpecReader.h"

static void AppendNum(NSMutableString *k, NSNumber *_Nullable v) {
    if (v == nil) {
        [k appendString:@"~|"];
    } else {
        [k appendFormat:@"%lld|", AMapLengthUnits(v.doubleValue)];
    }
}

static void AppendLen(NSMutableString *k, double v) {
    [k appendFormat:@"%lld|", AMapLengthUnits(v)];
}

static void AppendLens(NSMutableString *k, NSArray<NSNumber *> *_Nullable vs) {
    if (vs == nil) {
        [k appendString:@"~|"];
        return;
    }
    [k appendString:@"["];
    for (NSNumber *v in vs) {
        AppendLen(k, v.doubleValue);
    }
    [k appendString:@"]|"];
}

@implementation AMapNativeMarkerStyle

- (instancetype)initWithDict:(NSDictionary *)s reader:(AMapSpecReader *)r {
    self = [super init];
    NSDictionary *bg = [r map:s key:@"background" required:YES];
    id type = bg[@"type"];
    if ([@"shape" isEqual:type]) {
        BOOL circle = [@"circle" isEqual:bg[@"kind"]];
        [r require:circle || [@"roundedRect" isEqual:bg[@"kind"]] message:@"background.kind 非法"];
        _bgType = circle ? AMapNativeBackgroundCircle : AMapNativeBackgroundRect;
        _diameter = circle ? [r length:bg key:@"diameter"] : 0;
        _fillColor = [r color:bg key:@"fillColor"];
        _cornerRadius = circle ? 0 : [r length:bg key:@"cornerRadius" or:0];
        _borderColor = [r optColor:bg key:@"borderColor"];
        _borderWidth = [r length:bg key:@"borderWidth" or:0];
    } else {
        [r require:[@"image" isEqual:type] message:[NSString stringWithFormat:@"background.type 非法: %@", type]];
        _bgType = AMapNativeBackgroundImage;
        _imageId = [r optString:bg key:@"imageId"];
        [r require:_imageId.length > 0 message:@"background.imageId 不能为空"];
        _imageSize = [r optLengths:bg key:@"size" count:2];
        _capInsets = [r optLengths:bg key:@"capInsets" count:4];
    }
    _fontSize = [r length:s key:@"fontSize" or:12];
    id w = AMapNonNull(s[@"fontWeight"]);
    _fontWeight = w == nil ? 400 : (NSInteger)[r number:w path:@"fontWeight"];
    NSNumber *tc = [r optColor:s key:@"textColor"];
    _textColor = tc == nil ? 0xFF000000 : tc.unsignedIntValue;
    NSString *align = [r optString:s key:@"textAlign"];
    _textAlign = align ?: @"center";
    NSArray<NSNumber *> *pad = [r optLengths:s key:@"padding" count:4];
    _padL = pad ? pad[0].doubleValue : 0;
    _padT = pad ? pad[1].doubleValue : 0;
    _padR = pad ? pad[2].doubleValue : 0;
    _padB = pad ? pad[3].doubleValue : 0;
    _width = [r optLength:s key:@"width"];
    _height = [r optLength:s key:@"height"];
    _minWidth = [r optLength:s key:@"minWidth"];
    _maxWidth = [r optLength:s key:@"maxWidth"];

    NSDictionary *arrow = [r map:s key:@"arrow" required:NO];
    _hasArrow = arrow != nil;
    _arrowWidth = _hasArrow ? [r length:arrow key:@"width"] : 0;
    _arrowHeight = _hasArrow ? [r length:arrow key:@"height"] : 0;
    _arrowColor = _hasArrow ? [r optColor:arrow key:@"color"] : nil;

    NSDictionary *shadow = [r map:s key:@"shadow" required:NO];
    _hasShadow = shadow != nil;
    _shadowColor = _hasShadow ? [r color:shadow key:@"color"] : 0;
    _shadowBlur = _hasShadow ? [r length:shadow key:@"blurRadius" or:0] : 0;
    NSArray<NSNumber *> *off = _hasShadow ? [r optLengths:shadow key:@"offset" count:2] : nil;
    _shadowDx = off ? off[0].doubleValue : 0;
    _shadowDy = off ? off[1].doubleValue : 0;
    [self validate:r];
    return self;
}

- (BOOL)isImage {
    return _bgType == AMapNativeBackgroundImage;
}

/// R-VAL-2/3/4/8 与 D-1，全部对规范化后的值执行
- (void)validate:(AMapSpecReader *)r {
    [r require:_fontSize > 0 message:@"fontSize 规范化后必须大于 0"];
    [r require:(_fontWeight == 400 || _fontWeight == 500 || _fontWeight == 600 || _fontWeight == 700)
       message:@"fontWeight 只允许 400/500/600/700"];
    [r require:[@[@"left", @"center", @"right"] containsObject:_textAlign]
       message:@"textAlign 只允许 left/center/right"];
    BOOL circle = _bgType == AMapNativeBackgroundCircle;
    [r require:!circle || _diameter > 0 message:@"diameter 规范化后必须大于 0"];
    [r require:!circle || (_width == nil && _height == nil) message:@"圆形背景不允许设置 width/height"];
    NSMutableArray<NSNumber *> *all = [NSMutableArray arrayWithArray:@[
        @(_padL), @(_padT), @(_padR), @(_padB), @(_cornerRadius), @(_borderWidth),
        @(_arrowWidth), @(_arrowHeight), @(_shadowBlur)]];
    for (NSNumber *v in @[_width ?: @0, _height ?: @0, _minWidth ?: @0, _maxWidth ?: @0]) {
        [all addObject:v];
    }
    [all addObjectsFromArray:_imageSize ?: @[]];
    [all addObjectsFromArray:_capInsets ?: @[]];
    for (NSNumber *v in all) {
        [r require:v.doubleValue >= 0 message:@"尺寸不能为负"];
    }
    [r require:_minWidth == nil || _maxWidth == nil || _minWidth.doubleValue <= _maxWidth.doubleValue
       message:@"minWidth 不能大于 maxWidth"];
    [r require:_width == nil || ((_minWidth == nil || _width.doubleValue >= _minWidth.doubleValue)
                                 && (_maxWidth == nil || _width.doubleValue <= _maxWidth.doubleValue))
       message:@"width 必须落在 minWidth 与 maxWidth 之间"];
    [r require:!_hasArrow || !self.isImage || _arrowColor != nil message:@"图片背景下箭头必须指定颜色"];
    [r require:!_hasArrow || self.isImage || _arrowColor == nil || _arrowColor.unsignedIntValue == _fillColor
       message:@"形状背景的 arrow.color 只能为空或等于 fillColor"];
}

- (void)appendKey:(NSMutableString *)k {
    [k appendFormat:@"%ld|", (long)_bgType];
    AppendLen(k, _diameter);
    [k appendFormat:@"%u|", _fillColor];
    AppendLen(k, _cornerRadius);
    [k appendFormat:@"%@|", _borderColor ?: @"~"];
    AppendLen(k, _borderWidth);
    [k appendFormat:@"%@|", _imageId ?: @"~"];
    AppendLens(k, _imageSize);
    AppendLens(k, _capInsets);
    AppendLen(k, _fontSize);
    [k appendFormat:@"%ld|%u|%@|", (long)_fontWeight, _textColor, _textAlign];
    AppendLens(k, @[@(_padL), @(_padT), @(_padR), @(_padB)]);
    AppendNum(k, _width);
    AppendNum(k, _height);
    AppendNum(k, _minWidth);
    AppendNum(k, _maxWidth);
    [k appendFormat:@"%d|", _hasArrow];
    AppendLen(k, _arrowWidth);
    AppendLen(k, _arrowHeight);
    [k appendFormat:@"%@|%d|%u|", _arrowColor ?: @"~", _hasShadow, _shadowColor];
    AppendLen(k, _shadowBlur);
    AppendLen(k, _shadowDx);
    AppendLen(k, _shadowDy);
}

@end
