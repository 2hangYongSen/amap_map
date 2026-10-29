import 'dart:ui' show Color, FontWeight, Offset, Size, TextAlign;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show EdgeInsets;

import 'native_marker_decoration.dart';

export 'native_marker_decoration.dart';

/// 原生点位内容：[text] 与 [iconId] 至少提供一个（由校验器检查），图标固定显示在文字前方。
@immutable
final class NativeMarkerContent {
  const NativeMarkerContent({
    this.text,
    this.iconId,
    this.iconSize,
    this.iconSpacing = 4,
  });

  /// 单行文字，超过最大宽度时尾部省略
  final String? text;

  /// 图标引用的 [MarkerImageResource.id]
  final String? iconId;

  /// 图标显示尺寸（逻辑像素），为空时用图片逻辑尺寸
  final Size? iconSize;

  /// 图标与文字的间距
  final double iconSpacing;

  /// 复制；可空字段用 `clearXxx: true` 清空
  NativeMarkerContent copyWith({
    String? text,
    bool clearText = false,
    String? iconId,
    bool clearIconId = false,
    Size? iconSize,
    bool clearIconSize = false,
    double? iconSpacing,
  }) {
    return NativeMarkerContent(
      text: clearText ? null : (text ?? this.text),
      iconId: clearIconId ? null : (iconId ?? this.iconId),
      iconSize: clearIconSize ? null : (iconSize ?? this.iconSize),
      iconSpacing: iconSpacing ?? this.iconSpacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerContent &&
          text == other.text &&
          iconId == other.iconId &&
          iconSize == other.iconSize &&
          iconSpacing == other.iconSpacing;

  @override
  int get hashCode => Object.hash(text, iconId, iconSize, iconSpacing);

  @override
  String toString() => 'NativeMarkerContent{text: $text, iconId: $iconId, '
      'iconSize: $iconSize, iconSpacing: $iconSpacing}';
}

/// 一个状态下的完整样式；原生端不做样式继承或层叠。
@immutable
final class NativeMarkerStyle {
  const NativeMarkerStyle({
    required this.background,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w400,
    this.textColor = const Color(0xFF000000),
    this.textAlign = TextAlign.center,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.arrow,
    this.shadow,
  });

  /// 背景（形状或图片）
  final NativeMarkerBackground background;

  /// 字号（逻辑像素）
  final double fontSize;

  /// 字重，只允许 w400 / w500 / w600 / w700
  final FontWeight fontWeight;

  final Color textColor;

  /// 只允许 left / center / right
  final TextAlign textAlign;

  /// 主体内容区的内边距（图片背景时即文字安全区）
  final EdgeInsets padding;

  final double? width;
  final double? height;
  final double? minWidth;
  final double? maxWidth;

  /// 底部居中的箭头
  final NativeMarkerArrow? arrow;

  /// 单层阴影
  final NativeMarkerShadow? shadow;

  /// 复制；可空字段用 `clearXxx: true` 清空，例如 `copyWith(clearShadow: true)`
  NativeMarkerStyle copyWith({
    NativeMarkerBackground? background,
    double? fontSize,
    FontWeight? fontWeight,
    Color? textColor,
    TextAlign? textAlign,
    EdgeInsets? padding,
    double? width,
    bool clearWidth = false,
    double? height,
    bool clearHeight = false,
    double? minWidth,
    bool clearMinWidth = false,
    double? maxWidth,
    bool clearMaxWidth = false,
    NativeMarkerArrow? arrow,
    bool clearArrow = false,
    NativeMarkerShadow? shadow,
    bool clearShadow = false,
  }) {
    return NativeMarkerStyle(
      background: background ?? this.background,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textColor: textColor ?? this.textColor,
      textAlign: textAlign ?? this.textAlign,
      padding: padding ?? this.padding,
      width: clearWidth ? null : (width ?? this.width),
      height: clearHeight ? null : (height ?? this.height),
      minWidth: clearMinWidth ? null : (minWidth ?? this.minWidth),
      maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
      arrow: clearArrow ? null : (arrow ?? this.arrow),
      shadow: clearShadow ? null : (shadow ?? this.shadow),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerStyle &&
          background == other.background &&
          fontSize == other.fontSize &&
          fontWeight == other.fontWeight &&
          textColor == other.textColor &&
          textAlign == other.textAlign &&
          padding == other.padding &&
          width == other.width &&
          height == other.height &&
          minWidth == other.minWidth &&
          maxWidth == other.maxWidth &&
          arrow == other.arrow &&
          shadow == other.shadow;

  @override
  int get hashCode => Object.hash(background, fontSize, fontWeight, textColor,
      textAlign, padding, width, height, minWidth, maxWidth, arrow, shadow);

  @override
  String toString() => 'NativeMarkerStyle{background: $background, '
      'fontSize: $fontSize, fontWeight: $fontWeight, textColor: $textColor, '
      'textAlign: $textAlign, padding: $padding, width: $width, '
      'height: $height, minWidth: $minWidth, maxWidth: $maxWidth, '
      'arrow: $arrow, shadow: $shadow}';
}

/// 锚点类型
enum NativeMarkerAnchorType {
  /// 主体中心
  bodyCenter,

  /// 箭头尖端；该状态无箭头时取主体底边中点
  arrowTip,

  /// 自定义，由 [NativeMarkerPresentation.anchor] 指定，按各状态自己的主体框计算
  custom,
}

/// 原生点位的完整展示配置
@immutable
final class NativeMarkerPresentation {
  const NativeMarkerPresentation({
    required this.content,
    required this.style,
    this.selectedStyle,
    this.anchorType = NativeMarkerAnchorType.bodyCenter,
    this.anchor,
  });

  final NativeMarkerContent content;

  /// 普通态样式
  final NativeMarkerStyle style;

  /// 选中态样式；为空表示选中态沿用普通态
  final NativeMarkerStyle? selectedStyle;

  final NativeMarkerAnchorType anchorType;

  /// 仅 [NativeMarkerAnchorType.custom] 时必填，取值 0..1
  final Offset? anchor;

  /// 复制；可空字段用 `clearXxx: true` 清空
  NativeMarkerPresentation copyWith({
    NativeMarkerContent? content,
    NativeMarkerStyle? style,
    NativeMarkerStyle? selectedStyle,
    bool clearSelectedStyle = false,
    NativeMarkerAnchorType? anchorType,
    Offset? anchor,
    bool clearAnchor = false,
  }) {
    return NativeMarkerPresentation(
      content: content ?? this.content,
      style: style ?? this.style,
      selectedStyle:
          clearSelectedStyle ? null : (selectedStyle ?? this.selectedStyle),
      anchorType: anchorType ?? this.anchorType,
      anchor: clearAnchor ? null : (anchor ?? this.anchor),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerPresentation &&
          content == other.content &&
          style == other.style &&
          selectedStyle == other.selectedStyle &&
          anchorType == other.anchorType &&
          anchor == other.anchor;

  @override
  int get hashCode =>
      Object.hash(content, style, selectedStyle, anchorType, anchor);

  @override
  String toString() => 'NativeMarkerPresentation{content: $content, '
      'style: $style, selectedStyle: $selectedStyle, '
      'anchorType: $anchorType, anchor: $anchor}';
}
