import 'dart:ui' show Color, Offset, Size, TextAlign;

import 'package:flutter/painting.dart' show EdgeInsets;

import '../compatibility/color_extensions.dart';
import '../types/marker.dart';
import '../types/marker_selection.dart';
import '../types/native_marker.dart';

/// 新协议版本号（R-PROTO-0）
const int kMarkerProtocolVersion = 2;

/// 该点位是否用到了新能力，用到即需要启用新协议（R-PROTO-0）。
bool markerNeedsProtocolV2(Marker m) =>
    m.nativePresentation != null || m.selectable || m.selectedZIndex != null;

/// 新协议下的点位完整对象（R-PROTO-1/2）：
/// 每个键都存在，空值用显式 null，原生按整体替换处理。
Map<String, dynamic> markerToV2Map(Marker m) {
  final NativeMarkerPresentation? p = m.nativePresentation;
  final Map<String, dynamic> json = m.toMap();
  json['renderMode'] = p == null ? 'icon' : 'native';
  // 两种模式互斥：native 时 icon 为 null，icon 时 presentation 为 null
  json['icon'] = p == null ? m.icon.toMap() : null;
  json['nativePresentation'] = p == null ? null : presentationToMap(p);
  json['selectable'] = m.selectable;
  json['selectedZIndex'] = m.selectedZIndex;
  return json;
}

/// presentation 序列化，Dart 传原始值，规范化由原生完成（R-NORM-3）。
Map<String, dynamic> presentationToMap(NativeMarkerPresentation p) {
  final NativeMarkerStyle? selected = p.selectedStyle;
  return <String, dynamic>{
    'content': _contentToMap(p.content),
    'style': _styleToMap(p.style),
    'selectedStyle': selected == null ? null : _styleToMap(selected),
    'anchorType': p.anchorType.name,
    'anchor': _offset(p.anchor),
  };
}

/// 点位引用的全部图片资源 id（背景图与图标，含选中态）。
Set<String> markerImageDeps(Marker m) {
  final NativeMarkerPresentation? p = m.nativePresentation;
  if (p == null) {
    return const <String>{};
  }
  final Set<String> ids = <String>{};
  final String? iconId = p.content.iconId;
  if (iconId != null) {
    ids.add(iconId);
  }
  for (final NativeMarkerStyle? s in <NativeMarkerStyle?>[
    p.style,
    p.selectedStyle,
  ]) {
    final NativeMarkerBackground? bg = s?.background;
    if (bg is NativeMarkerImageBackground) {
      ids.add(bg.imageId);
    }
  }
  return ids;
}

/// 解析 `marker#nativeError` 载荷；错误码未知时返回 null。
NativeMarkerError? nativeMarkerErrorFromMap(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final Object? code = raw['code'];
  NativeMarkerErrorCode? parsed;
  for (final NativeMarkerErrorCode c in NativeMarkerErrorCode.values) {
    if (c.name == code) {
      parsed = c;
    }
  }
  if (parsed == null) {
    return null;
  }
  return NativeMarkerError(
    code: parsed,
    markerId: raw['markerId'] as String?,
    imageId: raw['imageId'] as String?,
    message: raw['message'] as String? ?? '',
  );
}

// ---------- 内部序列化 ----------

Map<String, dynamic> _contentToMap(NativeMarkerContent c) => <String, dynamic>{
      'text': c.text,
      'iconId': c.iconId,
      'iconSize': _size(c.iconSize),
      'iconSpacing': c.iconSpacing,
    };

Map<String, dynamic> _styleToMap(NativeMarkerStyle s) {
  final NativeMarkerArrow? arrow = s.arrow;
  final NativeMarkerShadow? shadow = s.shadow;
  return <String, dynamic>{
    'background': _backgroundToMap(s.background),
    'fontSize': s.fontSize,
    'fontWeight': s.fontWeight.value,
    'textColor': s.textColor.argbValue,
    'textAlign': _textAlign(s.textAlign),
    'padding': _insets(s.padding),
    'width': s.width,
    'height': s.height,
    'minWidth': s.minWidth,
    'maxWidth': s.maxWidth,
    'arrow': arrow == null
        ? null
        : <String, dynamic>{
            'width': arrow.width,
            'height': arrow.height,
            'color': _color(arrow.color),
          },
    'shadow': shadow == null
        ? null
        : <String, dynamic>{
            'color': shadow.color.argbValue,
            'blurRadius': shadow.blurRadius,
            'offset': _offset(shadow.offset),
          },
  };
}

Map<String, dynamic> _backgroundToMap(NativeMarkerBackground bg) {
  switch (bg) {
    case NativeMarkerShapeBackground():
      return <String, dynamic>{
        'type': 'shape',
        'kind': bg.kind.name,
        'diameter': bg.diameter,
        'fillColor': bg.fillColor.argbValue,
        'cornerRadius': bg.cornerRadius,
        'borderColor': _color(bg.borderColor),
        'borderWidth': bg.borderWidth,
      };
    case NativeMarkerImageBackground():
      return <String, dynamic>{
        'type': 'image',
        'imageId': bg.imageId,
        'size': _size(bg.size),
        'capInsets': _insets(bg.capInsets),
      };
  }
}

// 校验器已限定只有 left/center/right
String _textAlign(TextAlign a) => switch (a) {
      TextAlign.left => 'left',
      TextAlign.right => 'right',
      _ => 'center',
    };

int? _color(Color? c) => c?.argbValue;

List<double>? _size(Size? s) => s == null ? null : <double>[s.width, s.height];

List<double>? _offset(Offset? o) => o == null ? null : <double>[o.dx, o.dy];

// 顺序：left, top, right, bottom
List<double>? _insets(EdgeInsets? e) =>
    e == null ? null : <double>[e.left, e.top, e.right, e.bottom];
