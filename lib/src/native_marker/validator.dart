import 'dart:ui' show FontWeight, Offset, Size, TextAlign;

import 'package:flutter/painting.dart' show EdgeInsets;

import '../types/marker.dart';
import '../types/marker_image_resource.dart';
import '../types/marker_selection.dart';
import '../types/native_marker.dart';
import 'normalize.dart';

/// 原生点位的运行时校验（R-VAL-1～10）。
///
/// 校验失败抛出 [ArgumentError]，消息含 markerId 与字段路径。
/// 用普通 `throw` 而不是 `assert`，debug 与 release 行为一致。
/// 调用方应在发送前整体校验，失败则本次更新整体不发送。
class NativeMarkerValidator {
  const NativeMarkerValidator._();

  static const List<FontWeight> _allowedWeights = <FontWeight>[
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
  ];

  /// replaceWhenReady 的超时上限
  static const Duration maxTransitionTimeout = Duration(seconds: 5);

  /// 校验一次发送涉及的全部点位与图片资源。
  static void validate({
    required Iterable<Marker> markers,
    required Iterable<MarkerImageResource> images,
  }) {
    final Set<String> imageIds = _validateImages(images);
    final Set<String> markerIds = <String>{};
    for (final Marker marker in markers) {
      // R-VAL-9：同一集合内 id 不重复
      if (!markerIds.add(marker.id)) {
        throw ArgumentError("Marker '${marker.id}': id 重复");
      }
      _validateMarker(marker, imageIds);
    }
  }

  /// 校验过渡策略：timeout 须大于 0 且不超过 5s。
  static void validateTransition(MarkerTransition transition) {
    if (!transition.replaceWhenReadyEnabled) {
      return;
    }
    final Duration? t = transition.timeout;
    if (t == null || t <= Duration.zero || t > maxTransitionTimeout) {
      throw ArgumentError(
          'markerTransition.timeout 必须大于 0 且不超过 5 秒，实际为 $t');
    }
  }

  // ---------- 图片资源 ----------

  static Set<String> _validateImages(Iterable<MarkerImageResource> images) {
    final Map<String, MarkerImageResource> byId =
        <String, MarkerImageResource>{};
    for (final MarkerImageResource r in images) {
      final _Ctx ctx = _Ctx("image '${r.id}'");
      // R-VAL-1/2/10：像素比有限，规范化后必须 > 0
      if (ctx.ratio('pixelRatio', r.pixelRatio) <= 0) {
        ctx.fail('pixelRatio', '规范化后必须大于 0，实际为 ${r.pixelRatio}');
      }
      // R-VAL-9 / R-BYTES-5：同 id 的来源必须一致
      final MarkerImageResource? old = byId[r.id];
      if (old == null) {
        byId[r.id] = r;
      } else if (old.type != r.type ||
          old.assetName != r.assetName ||
          old.package != r.package ||
          old.pixelRatio != r.pixelRatio) {
        ctx.fail('id', '对应了不同的来源（assetName/package/pixelRatio/类型不一致）');
      }
    }
    return byId.keys.toSet();
  }

  // ---------- 点位 ----------

  static void _validateMarker(Marker marker, Set<String> imageIds) {
    final _Ctx ctx = _Ctx("Marker '${marker.id}'");
    final double? selectedZ = marker.selectedZIndex;
    if (selectedZ != null) {
      ctx.finite('selectedZIndex', selectedZ);
    }
    final NativeMarkerPresentation? p = marker.nativePresentation;
    if (p == null) {
      return;
    }
    ctx.finite('zIndex', marker.zIndex);
    _validateContent(ctx, p.content, imageIds);
    _validateStyle(ctx, 'style', p.style, imageIds);
    final NativeMarkerStyle? selected = p.selectedStyle;
    if (selected != null) {
      _validateStyle(ctx, 'selectedStyle', selected, imageIds);
    }
    _validateAnchor(ctx, p);
  }

  static void _validateContent(
      _Ctx ctx, NativeMarkerContent c, Set<String> imageIds) {
    // R-VAL-8：文字和图标不能同时为空
    final bool hasText = c.text != null && c.text!.isNotEmpty;
    if (!hasText && c.iconId == null) {
      ctx.fail('content', 'text 与 iconId 至少提供一个');
    }
    if (ctx.length('content.iconSpacing', c.iconSpacing) < 0) {
      ctx.fail('content.iconSpacing', '不能为负，实际为 ${c.iconSpacing}');
    }
    final Size? iconSize = c.iconSize;
    if (iconSize != null) {
      ctx.nonNegSize('content.iconSize', iconSize);
    }
    final String? iconId = c.iconId;
    if (iconId != null && !imageIds.contains(iconId)) {
      // R-VAL-7
      ctx.fail('content.iconId', "引用了不存在的图片资源 '$iconId'");
    }
  }

  static void _validateStyle(
      _Ctx ctx, String path, NativeMarkerStyle s, Set<String> imageIds) {
    // 字号：规范化后必须 > 0
    if (ctx.length('$path.fontSize', s.fontSize) <= 0) {
      ctx.fail('$path.fontSize', '规范化后必须大于 0，实际为 ${s.fontSize}');
    }
    if (!_allowedWeights.contains(s.fontWeight)) {
      ctx.fail('$path.fontWeight', '只允许 w400/w500/w600/w700，实际为 ${s.fontWeight}');
    }
    if (s.textAlign != TextAlign.left &&
        s.textAlign != TextAlign.center &&
        s.textAlign != TextAlign.right) {
      ctx.fail('$path.textAlign', '只允许 left/center/right，实际为 ${s.textAlign}');
    }
    _validatePadding(ctx, '$path.padding', s.padding);
    _validateSizes(ctx, path, s);
    _validateBackground(ctx, path, s, imageIds);
    _validateArrowAndShadow(ctx, path, s);
  }

  static void _validatePadding(_Ctx ctx, String path, EdgeInsets e) {
    for (final double v in <double>[e.left, e.top, e.right, e.bottom]) {
      if (ctx.length(path, v) < 0) {
        ctx.fail(path, '不能为负，实际为 $e');
      }
    }
  }

  /// R-VAL-2/3/4：尺寸非负、区间合理、圆形不带 width/height（均按规范化后的值）。
  static void _validateSizes(_Ctx ctx, String path, NativeMarkerStyle s) {
    final int? w = _optNonNeg(ctx, '$path.width', s.width);
    final int? h = _optNonNeg(ctx, '$path.height', s.height);
    final int? minW = _optNonNeg(ctx, '$path.minWidth', s.minWidth);
    final int? maxW = _optNonNeg(ctx, '$path.maxWidth', s.maxWidth);
    if (minW != null && maxW != null && minW > maxW) {
      ctx.fail('$path.minWidth',
          '不能大于 maxWidth（${s.minWidth} > ${s.maxWidth}）');
    }
    if (w != null &&
        ((minW != null && w < minW) || (maxW != null && w > maxW))) {
      ctx.fail('$path.width',
          '必须落在 minWidth 与 maxWidth 之间，实际为 ${s.width}');
    }
    if (s.background is NativeMarkerShapeBackground &&
        (s.background as NativeMarkerShapeBackground).kind ==
            NativeMarkerShapeKind.circle) {
      if (w != null) {
        ctx.fail('$path.width', '圆形背景不允许设置 width');
      }
      if (h != null) {
        ctx.fail('$path.height', '圆形背景不允许设置 height');
      }
    }
  }

  static int? _optNonNeg(_Ctx ctx, String path, double? v) {
    if (v == null) {
      return null;
    }
    final int u = ctx.length(path, v);
    if (u < 0) {
      ctx.fail(path, '不能为负，实际为 $v');
    }
    return u;
  }

  static void _validateBackground(_Ctx ctx, String path, NativeMarkerStyle s,
      Set<String> imageIds) {
    final NativeMarkerBackground bg = s.background;
    final String bgPath = '$path.background';
    switch (bg) {
      case NativeMarkerShapeBackground():
        if (bg.kind == NativeMarkerShapeKind.circle) {
          final double? d = bg.diameter;
          if (d == null || ctx.length('$bgPath.diameter', d) <= 0) {
            ctx.fail('$bgPath.diameter', '规范化后必须大于 0，实际为 $d');
          }
        }
        if (ctx.length('$bgPath.cornerRadius', bg.cornerRadius) < 0) {
          ctx.fail('$bgPath.cornerRadius', '不能为负，实际为 ${bg.cornerRadius}');
        }
        if (ctx.length('$bgPath.borderWidth', bg.borderWidth) < 0) {
          ctx.fail('$bgPath.borderWidth', '不能为负，实际为 ${bg.borderWidth}');
        }
      case NativeMarkerImageBackground():
        if (!imageIds.contains(bg.imageId)) {
          // R-VAL-7
          ctx.fail('$bgPath.imageId', "引用了不存在的图片资源 '${bg.imageId}'");
        }
        final Size? size = bg.size;
        if (size != null) {
          ctx.nonNegSize('$bgPath.size', size);
        }
        final EdgeInsets? cap = bg.capInsets;
        if (cap != null) {
          // R-VAL-5：Dart 端只能校验非负且有限，超限由原生在资源就绪后检测
          _validatePadding(ctx, '$bgPath.capInsets', cap);
        }
    }
  }

  static void _validateArrowAndShadow(
      _Ctx ctx, String path, NativeMarkerStyle s) {
    final NativeMarkerArrow? arrow = s.arrow;
    if (arrow != null) {
      if (ctx.length('$path.arrow.width', arrow.width) < 0) {
        ctx.fail('$path.arrow.width', '不能为负，实际为 ${arrow.width}');
      }
      if (ctx.length('$path.arrow.height', arrow.height) < 0) {
        ctx.fail('$path.arrow.height', '不能为负，实际为 ${arrow.height}');
      }
      // 图片背景下箭头单独绘制，颜色必须显式指定
      if (s.background is NativeMarkerImageBackground && arrow.color == null) {
        ctx.fail('$path.arrow.color', '图片背景下箭头必须指定颜色');
      }
    }
    final NativeMarkerShadow? shadow = s.shadow;
    if (shadow != null) {
      if (ctx.length('$path.shadow.blurRadius', shadow.blurRadius) < 0) {
        ctx.fail('$path.shadow.blurRadius', '不能为负，实际为 ${shadow.blurRadius}');
      }
      // 偏移允许为负，只要求有限且能规范化
      final Offset o = shadow.offset;
      ctx.length('$path.shadow.offset', o.dx);
      ctx.length('$path.shadow.offset', o.dy);
    }
  }

  /// R-VAL-6：锚点。
  static void _validateAnchor(_Ctx ctx, NativeMarkerPresentation p) {
    final Offset? a = p.anchor;
    if (a != null) {
      ctx.finite('anchor', a.dx);
      ctx.finite('anchor', a.dy);
    }
    switch (p.anchorType) {
      case NativeMarkerAnchorType.custom:
        if (a == null) {
          ctx.fail('anchor', 'custom 锚点必须提供 anchor');
        }
        for (final double v in <double>[a.dx, a.dy]) {
          final int u = ctx.ratio('anchor', v);
          if (u < 0 || u > kRatioScale) {
            ctx.fail('anchor', '取值必须在 0 到 1 之间，实际为 $a');
          }
        }
      case NativeMarkerAnchorType.arrowTip:
        // R-ANC-1：只要求普通态有箭头，选中态可省略
        if (p.style.arrow == null) {
          ctx.fail('style.arrow', 'arrowTip 锚点要求普通态设置箭头');
        }
      case NativeMarkerAnchorType.bodyCenter:
        break;
    }
  }
}

/// 一个校验对象的上下文：负责拼接带 owner 与字段路径的错误信息。
class _Ctx {
  const _Ctx(this.owner);

  final String owner;

  Never fail(String path, String message) =>
      throw ArgumentError('$owner: $path $message');

  /// R-VAL-1：必须有限
  void finite(String path, double v) {
    if (!v.isFinite) {
      fail(path, '必须是有限数值，实际为 $v');
    }
  }

  /// 长度类：先查有限，再返回规范化整数单位（过大时报错）
  int length(String path, double v) {
    finite(path, v);
    try {
      return normalizeLengthUnits(v);
    } on ArgumentError {
      fail(path, '数值过大，无法规范化：$v');
    }
  }

  /// 比例/像素比：先查有限，再返回规范化整数单位
  int ratio(String path, double v) {
    finite(path, v);
    try {
      return normalizeRatioUnits(v);
    } on ArgumentError {
      fail(path, '数值过大，无法规范化：$v');
    }
  }

  void nonNegSize(String path, Size s) {
    if (length(path, s.width) < 0 || length(path, s.height) < 0) {
      fail(path, '宽高不能为负，实际为 $s');
    }
  }
}
