import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/foundation.dart' show immutable;

/// 背景形状种类
enum NativeMarkerShapeKind {
  /// 圆形
  circle,

  /// 圆角矩形
  roundedRect,
}

/// 原生点位背景：形状或图片二选一。
@immutable
sealed class NativeMarkerBackground {
  const NativeMarkerBackground();
}

/// 形状背景（圆形或圆角矩形）。
@immutable
final class NativeMarkerShapeBackground extends NativeMarkerBackground {
  /// 圆形背景，[diameter] 为直径（逻辑像素）。
  const NativeMarkerShapeBackground.circle({
    required double this.diameter,
    required this.fillColor,
    this.borderColor,
    this.borderWidth = 0,
  })  : kind = NativeMarkerShapeKind.circle,
        cornerRadius = 0;

  /// 圆角矩形背景，尺寸由内容和样式的宽高决定。
  const NativeMarkerShapeBackground.roundedRect({
    required this.fillColor,
    this.cornerRadius = 0,
    this.borderColor,
    this.borderWidth = 0,
  })  : kind = NativeMarkerShapeKind.roundedRect,
        diameter = null;

  /// 形状种类
  final NativeMarkerShapeKind kind;

  /// 直径，仅圆形有值
  final double? diameter;

  /// 填充色
  final Color fillColor;

  /// 圆角半径，圆形时为 0
  final double cornerRadius;

  /// 描边色，为空表示无描边
  final Color? borderColor;

  /// 描边宽度
  final double borderWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerShapeBackground &&
          kind == other.kind &&
          diameter == other.diameter &&
          fillColor == other.fillColor &&
          cornerRadius == other.cornerRadius &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth;

  @override
  int get hashCode => Object.hash(
      kind, diameter, fillColor, cornerRadius, borderColor, borderWidth);

  @override
  String toString() => 'NativeMarkerShapeBackground{kind: $kind, '
      'diameter: $diameter, fillColor: $fillColor, '
      'cornerRadius: $cornerRadius, borderColor: $borderColor, '
      'borderWidth: $borderWidth}';
}

/// 图片背景。[capInsets] 非空表示九宫格拉伸；为空时按 [size] 或图片逻辑尺寸固定显示。
@immutable
final class NativeMarkerImageBackground extends NativeMarkerBackground {
  const NativeMarkerImageBackground({
    required this.imageId,
    this.size,
    this.capInsets,
  });

  /// 引用的 [MarkerImageResource.id]
  final String imageId;

  /// 固定显示尺寸（逻辑像素）
  final Size? size;

  /// 九宫格边距（逻辑像素）
  final EdgeInsets? capInsets;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerImageBackground &&
          imageId == other.imageId &&
          size == other.size &&
          capInsets == other.capInsets;

  @override
  int get hashCode => Object.hash(imageId, size, capInsets);

  @override
  String toString() => 'NativeMarkerImageBackground{imageId: $imageId, '
      'size: $size, capInsets: $capInsets}';
}

/// 底部居中的箭头。[color] 为空时沿用形状背景的填充色；图片背景下必须显式指定。
@immutable
final class NativeMarkerArrow {
  const NativeMarkerArrow(
      {required this.width, required this.height, this.color});

  final double width;
  final double height;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerArrow &&
          width == other.width &&
          height == other.height &&
          color == other.color;

  @override
  int get hashCode => Object.hash(width, height, color);

  @override
  String toString() =>
      'NativeMarkerArrow{width: $width, height: $height, color: $color}';
}

/// 单层阴影。
@immutable
final class NativeMarkerShadow {
  const NativeMarkerShadow({
    required this.color,
    this.blurRadius = 0,
    this.offset = Offset.zero,
  });

  final Color color;
  final double blurRadius;
  final Offset offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeMarkerShadow &&
          color == other.color &&
          blurRadius == other.blurRadius &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(color, blurRadius, offset);

  @override
  String toString() => 'NativeMarkerShadow{color: $color, '
      'blurRadius: $blurRadius, offset: $offset}';
}
