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

/// 图片背景，有两种用法：
///
/// - **九宫格**（[capInsets] 非空）：宽高随文字变化，规则与圆角矩形相同
///   （文字宽 + `padding`，受 `width`/`minWidth`/`maxWidth` 约束）。图片按
///   [capInsets] 切成 9 块：四角不拉伸，四边单向拉伸，中间双向拉伸（只拉伸、不平铺）。
///   适合渐变、装饰边框等形状背景画不出来、且文字长度不固定的气泡。
/// - **固定尺寸**（[capInsets] 为空）：按 [size] 显示，未设置时用图片逻辑尺寸
///   （像素 / `pixelRatio`）。图片自带箭头时用这种方式，不配置 `arrow`，
///   改用 `NativeMarkerAnchorType.custom` 锚点指向箭头尖端。
///
/// 纯色加描边的气泡请用 [NativeMarkerShapeBackground]：主体与箭头是同一条路径，
/// 不需要加载资源。
///
/// ```dart
/// NativeMarkerImageBackground(
///   imageId: 'bubble', // 图片 96x72 像素、pixelRatio 2，即逻辑 48x36
///   capInsets: EdgeInsets.all(10), // 左右 10+10 < 48，上下 10+10 < 36
/// )
/// ```
@immutable
final class NativeMarkerImageBackground extends NativeMarkerBackground {
  const NativeMarkerImageBackground({
    required this.imageId,
    this.size,
    this.capInsets,
  });

  /// 引用的 [MarkerImageResource.id]
  final String imageId;

  /// 固定显示尺寸（逻辑像素），仅在 [capInsets] 为空时生效；图片按此尺寸整体缩放。
  /// 资源加载失败降级时也保持这个尺寸，布局不跳动。
  final Size? size;

  /// 九宫格边距（逻辑像素），即四角不拉伸区域的大小。
  ///
  /// - 原生端乘以资源的 `pixelRatio` 换算成图片像素。
  /// - 必须满足 `left + right < 图片逻辑宽`、`top + bottom < 图片逻辑高`。
  ///   图片尺寸要等资源加载完成才知道，所以 Dart 端只检查非负；超限时该点按默认
  ///   白色背景显示，并通过 `AMapWidget.onNativeMarkerError` 报一次
  ///   `NativeMarkerErrorCode.invalidConfig`，修改配置或替换资源后重新判断。
  /// - 不要把箭头画进图片底边中间，它会随中间区域被拉宽；用 [NativeMarkerArrow]
  ///   单独绘制。
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

/// 主体底部居中的箭头，不参与九宫格拉伸。
///
/// - 形状背景：箭头与主体是同一条闭合路径，一次填充、描边和投影，没有接缝。
///   [color] 只能为空（沿用 `fillColor`）或等于 `fillColor`，否则校验报错。
/// - 图片背景：箭头单独画成三角形，[color] 必须显式指定。要与图片接成一体，
///   图片底边颜色需与 [color] 一致；图片带描边或渐变底边时，箭头处会断开。
@immutable
final class NativeMarkerArrow {
  const NativeMarkerArrow(
      {required this.width, required this.height, this.color});

  /// 底边宽度（逻辑像素）
  final double width;

  /// 高度（逻辑像素），尖端到主体底边的距离
  final double height;

  /// 箭头颜色，规则见类说明
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
