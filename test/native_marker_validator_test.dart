import 'dart:typed_data';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/validator.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

// T-VAL-1：表驱动，覆盖 R-VAL-1～10 的合法与非法边界。
// 校验器抛出的是普通 ArgumentError，不依赖 assert，release 下行为相同。
const NativeMarkerArrow _arrow = NativeMarkerArrow(width: 10, height: 5);

NativeMarkerStyle _style({NativeMarkerBackground? bg}) => NativeMarkerStyle(
      background: bg ??
          const NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF)),
      height: 26,
      // 图片背景的箭头必须显式给颜色，基线样式对图片背景不带箭头
      arrow: bg is NativeMarkerImageBackground ? null : _arrow,
    );

NativeMarkerPresentation _pres({
  NativeMarkerContent content = const NativeMarkerContent(text: 'A'),
  NativeMarkerStyle? style,
  NativeMarkerStyle? selectedStyle,
  NativeMarkerAnchorType anchorType = NativeMarkerAnchorType.bodyCenter,
  Offset? anchor,
}) =>
    NativeMarkerPresentation(
      content: content,
      style: style ?? _style(),
      selectedStyle: selectedStyle,
      anchorType: anchorType,
      anchor: anchor,
    );

Marker _marker(NativeMarkerPresentation? p,
        {String id = 'h:1', double? selectedZIndex}) =>
    Marker(
      markerId: id,
      position: const LatLng(40, 116),
      nativePresentation: p,
      selectedZIndex: selectedZIndex,
    );

final List<MarkerImageResource> _images = <MarkerImageResource>[
  const MarkerImageResource.asset(id: 'bg', assetName: 'a/bg.png'),
  const MarkerImageResource.asset(id: 'ic', assetName: 'a/ic.png'),
];

void _validate(Iterable<Marker> markers, Iterable<MarkerImageResource> images) =>
    NativeMarkerValidator.validate(markers: markers, images: images);

/// 非法：抛 ArgumentError，且消息包含 markerId 与字段路径
void _invalid(String name, NativeMarkerPresentation p, String path,
    {Iterable<MarkerImageResource>? images, double? selectedZIndex}) {
  test('非法 $name', () {
    expect(
      () => _validate(<Marker>[_marker(p, selectedZIndex: selectedZIndex)],
          images ?? _images),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'message',
          allOf(contains('h:1'), contains(path)))),
    );
  });
}

/// 资源级非法：与具体点位无关，消息只需包含资源 id 与字段路径
void _invalidImages(String name, List<MarkerImageResource> images, String path) {
  test('非法 $name', () {
    expect(
      () => _validate(<Marker>[_marker(_pres())], images),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'message',
          allOf(contains('bg'), contains(path)))),
    );
  });
}

void _valid(String name, NativeMarkerPresentation p,
    {Iterable<MarkerImageResource>? images}) {
  test('合法 $name', () {
    expect(() => _validate(<Marker>[_marker(p)], images ?? _images),
        returnsNormally);
  });
}

void main() {
  test('基线样例合法', () {
    expect(() => _validate(<Marker>[_marker(_pres())], _images),
        returnsNormally);
  });

  test('没有原生配置的点位不做展示校验', () {
    expect(() => _validate(<Marker>[_marker(null)], const <MarkerImageResource>[]),
        returnsNormally);
  });

  group('R-VAL-1 非有限值', () {
    final Map<String, double> bad = <String, double>{
      'NaN': double.nan,
      '+inf': double.infinity,
      '-inf': double.negativeInfinity,
    };
    bad.forEach((String label, double v) {
      _invalid('fontSize=$label',
          _pres(style: _style().copyWith(fontSize: v)), 'style.fontSize');
      _invalid('width=$label', _pres(style: _style().copyWith(width: v)),
          'style.width');
      _invalid('maxWidth=$label',
          _pres(style: _style().copyWith(maxWidth: v)), 'style.maxWidth');
      _invalid(
          'padding=$label',
          _pres(style: _style().copyWith(padding: EdgeInsets.only(left: v))),
          'style.padding');
      _invalid(
          'shadow.offset=$label',
          _pres(
              style: _style().copyWith(
                  shadow: NativeMarkerShadow(
                      color: const Color(0xFF000000), offset: Offset(v, 0)))),
          'style.shadow.offset');
      _invalid(
          'iconSpacing=$label',
          _pres(content: NativeMarkerContent(text: 'A', iconSpacing: v)),
          'content.iconSpacing');
      _invalid(
          'anchor.dx=$label',
          _pres(
              anchorType: NativeMarkerAnchorType.custom, anchor: Offset(v, 0)),
          'anchor');
      _invalid('selectedZIndex=$label', _pres(), 'selectedZIndex',
          selectedZIndex: v);
      _invalid(
          'selectedStyle.height=$label',
          _pres(selectedStyle: _style().copyWith(height: v)),
          'selectedStyle.height');
    });
  });

  group('R-VAL-2 非负与正数', () {
    _valid('width=0', _pres(style: _style().copyWith(width: 0)));
    _invalid('width<0', _pres(style: _style().copyWith(width: -1)),
        'style.width');
    _invalid('height<0', _pres(style: _style().copyWith(height: -1)),
        'style.height');
    _invalid('minWidth<0', _pres(style: _style().copyWith(minWidth: -1)),
        'style.minWidth');
    _invalid('maxWidth<0', _pres(style: _style().copyWith(maxWidth: -1)),
        'style.maxWidth');
    _invalid(
        'iconSpacing<0',
        _pres(content: const NativeMarkerContent(text: 'A', iconSpacing: -1)),
        'content.iconSpacing');
    _invalid(
        'iconSize<0',
        _pres(
            content: const NativeMarkerContent(
                iconId: 'ic', iconSize: Size(-1, 10))),
        'content.iconSize');
    _invalid(
        'cornerRadius<0',
        _pres(
            style: _style(
                bg: const NativeMarkerShapeBackground.roundedRect(
                    fillColor: Color(0xFFFFFFFF), cornerRadius: -1))),
        'cornerRadius');
    _invalid(
        'borderWidth<0',
        _pres(
            style: _style(
                bg: const NativeMarkerShapeBackground.roundedRect(
                    fillColor: Color(0xFFFFFFFF), borderWidth: -1))),
        'borderWidth');
    _invalid(
        'shadow.blurRadius<0',
        _pres(
            style: _style().copyWith(
                shadow: const NativeMarkerShadow(
                    color: Color(0xFF000000), blurRadius: -1))),
        'style.shadow.blurRadius');
    _valid(
        'shadow.offset 可为负',
        _pres(
            style: _style().copyWith(
                shadow: const NativeMarkerShadow(
                    color: Color(0xFF000000), offset: Offset(-2, -3)))));
    _invalid(
        'padding<0',
        _pres(style: _style().copyWith(padding: const EdgeInsets.only(top: -1))),
        'style.padding');
    _invalid(
        'arrow.width<0',
        _pres(
            style: _style().copyWith(
                arrow: const NativeMarkerArrow(width: -1, height: 5))),
        'style.arrow.width');
    _invalid(
        'arrow.height<0',
        _pres(
            style: _style().copyWith(
                arrow: const NativeMarkerArrow(width: 10, height: -1))),
        'style.arrow.height');
    _invalid('fontSize=0', _pres(style: _style().copyWith(fontSize: 0)),
        'style.fontSize');
    _invalid('fontSize<0', _pres(style: _style().copyWith(fontSize: -1)),
        'style.fontSize');
    _valid('fontSize=1/64', _pres(style: _style().copyWith(fontSize: 1 / 64)));
    _invalid(
        'diameter=0',
        _pres(
            style: const NativeMarkerStyle(
                background: NativeMarkerShapeBackground.circle(
                    diameter: 0, fillColor: Color(0xFFFFFFFF)))),
        'diameter');
    _invalid(
        'diameter<0',
        _pres(
            style: const NativeMarkerStyle(
                background: NativeMarkerShapeBackground.circle(
                    diameter: -4, fillColor: Color(0xFFFFFFFF)))),
        'diameter');
    _invalid(
        'image.size<0',
        _pres(
            style: _style(
                bg: const NativeMarkerImageBackground(
                    imageId: 'bg', size: Size(10, -1)))),
        'background.size');
    _invalidImages('pixelRatio=0', const <MarkerImageResource>[
      MarkerImageResource.asset(id: 'bg', assetName: 'a.png', pixelRatio: 0),
    ], 'pixelRatio');
    _invalidImages('pixelRatio<0', const <MarkerImageResource>[
      MarkerImageResource.asset(id: 'bg', assetName: 'a.png', pixelRatio: -2),
    ], 'pixelRatio');
    _invalidImages('pixelRatio=NaN', <MarkerImageResource>[
      const MarkerImageResource.asset(
          id: 'bg', assetName: 'a.png', pixelRatio: double.nan),
    ], 'pixelRatio');
    _invalidImages('pixelRatio=inf', <MarkerImageResource>[
      const MarkerImageResource.asset(
          id: 'bg', assetName: 'a.png', pixelRatio: double.infinity),
    ], 'pixelRatio');
  });

  group('R-VAL-3 宽度区间', () {
    _valid('min==max',
        _pres(style: _style().copyWith(minWidth: 40, maxWidth: 40)));
    _invalid('min>max',
        _pres(style: _style().copyWith(minWidth: 41, maxWidth: 40)), 'minWidth');
    _valid(
        'width 在区间内',
        _pres(
            style: _style().copyWith(width: 50, minWidth: 40, maxWidth: 60)));
    _valid(
        'width 等于边界',
        _pres(
            style: _style().copyWith(width: 40, minWidth: 40, maxWidth: 60)));
    _invalid(
        'width<min',
        _pres(
            style: _style().copyWith(width: 39, minWidth: 40, maxWidth: 60)),
        'style.width');
    _invalid(
        'width>max',
        _pres(
            style: _style().copyWith(width: 61, minWidth: 40, maxWidth: 60)),
        'style.width');
    _invalid('width>仅有的 max',
        _pres(style: _style().copyWith(width: 61, maxWidth: 60)), 'style.width');
    _invalid('width<仅有的 min',
        _pres(style: _style().copyWith(width: 39, minWidth: 40)), 'style.width');
    _invalid(
        'selectedStyle 同样检查',
        _pres(
            selectedStyle:
                _style().copyWith(minWidth: 41, maxWidth: 40)),
        'selectedStyle.minWidth');
  });

  group('R-VAL-4 圆形不允许 width/height', () {
    NativeMarkerStyle circle({double? w, double? h}) => NativeMarkerStyle(
          background: const NativeMarkerShapeBackground.circle(
              diameter: 20, fillColor: Color(0xFFFFFFFF)),
          width: w,
          height: h,
        );
    _valid('circle 无尺寸', _pres(style: circle()));
    _invalid('circle+width', _pres(style: circle(w: 20)), 'style.width');
    _invalid('circle+height', _pres(style: circle(h: 20)), 'style.height');
    _invalid('circle+width=0', _pres(style: circle(w: 0)), 'style.width');
  });

  group('R-VAL-5 capInsets', () {
    NativeMarkerStyle nine(EdgeInsets e) => _style(
        bg: NativeMarkerImageBackground(imageId: 'bg', capInsets: e));
    _valid('capInsets 全 0', _pres(style: nine(EdgeInsets.zero)));
    _valid('capInsets 正常', _pres(style: nine(const EdgeInsets.all(8))));
    _invalid('capInsets<0', _pres(style: nine(const EdgeInsets.only(left: -1))),
        'capInsets');
    _invalid('capInsets=NaN',
        _pres(style: nine(const EdgeInsets.only(top: double.nan))), 'capInsets');
    _invalid('capInsets=inf',
        _pres(style: nine(const EdgeInsets.only(right: double.infinity))), 'capInsets');
  });

  group('R-VAL-6 锚点', () {
    _invalid('custom 缺 anchor',
        _pres(anchorType: NativeMarkerAnchorType.custom), 'anchor');
    _valid(
        'custom (0,0)',
        _pres(
            anchorType: NativeMarkerAnchorType.custom, anchor: Offset.zero));
    _valid(
        'custom (1,1)',
        _pres(
            anchorType: NativeMarkerAnchorType.custom,
            anchor: const Offset(1, 1)));
    _invalid(
        'custom dx>1',
        _pres(
            anchorType: NativeMarkerAnchorType.custom,
            anchor: const Offset(1.001, 0.5)),
        'anchor');
    _invalid(
        'custom dy<0',
        _pres(
            anchorType: NativeMarkerAnchorType.custom,
            anchor: const Offset(0.5, -0.001)),
        'anchor');
    _valid(
        'custom dx=1+1e-9 舍入后为 1',
        _pres(
            anchorType: NativeMarkerAnchorType.custom,
            anchor: const Offset(1.000000001, 0.5)));
    _invalid(
        'arrowTip 普通态无箭头',
        _pres(
            anchorType: NativeMarkerAnchorType.arrowTip,
            style: _style().copyWith(clearArrow: true)),
        'style.arrow');
    _valid(
        'arrowTip 选中态无箭头',
        _pres(
            anchorType: NativeMarkerAnchorType.arrowTip,
            selectedStyle: _style().copyWith(clearArrow: true)));
    _valid(
        'arrowTip 两态箭头尺寸不同',
        _pres(
            anchorType: NativeMarkerAnchorType.arrowTip,
            selectedStyle: _style().copyWith(
                arrow: const NativeMarkerArrow(width: 16, height: 8))));
  });

  group('R-VAL-7 资源引用', () {
    _valid(
        '引用存在',
        _pres(
            content: const NativeMarkerContent(text: 'A', iconId: 'ic'),
            style: _style(bg: const NativeMarkerImageBackground(imageId: 'bg')),
            selectedStyle:
                _style(bg: const NativeMarkerImageBackground(imageId: 'bg'))));
    _invalid(
        '背景图缺失',
        _pres(
            style:
                _style(bg: const NativeMarkerImageBackground(imageId: 'nope'))),
        'style.background.imageId');
    _invalid(
        '选中态背景图缺失',
        _pres(
            selectedStyle:
                _style(bg: const NativeMarkerImageBackground(imageId: 'nope'))),
        'selectedStyle.background.imageId');
    _invalid(
        '图标缺失',
        _pres(content: const NativeMarkerContent(text: 'A', iconId: 'nope')),
        'content.iconId');
    _invalid(
        '没有任何资源时引用图标',
        _pres(content: const NativeMarkerContent(iconId: 'ic')),
        'content.iconId',
        images: const <MarkerImageResource>[]);
  });

  group('R-VAL-8 内容与字体', () {
    _invalid('文字图标都为空', _pres(content: const NativeMarkerContent()),
        'content');
    _invalid('文字为空串且无图标',
        _pres(content: const NativeMarkerContent(text: '')), 'content');
    _valid('只有文字', _pres(content: const NativeMarkerContent(text: 'A')));
    _valid('只有图标', _pres(content: const NativeMarkerContent(iconId: 'ic')));
    for (final FontWeight w in <FontWeight>[
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      _valid('fontWeight=$w', _pres(style: _style().copyWith(fontWeight: w)));
    }
    for (final FontWeight w in <FontWeight>[
      FontWeight.w100,
      FontWeight.w300,
      FontWeight.w800,
      FontWeight.w900,
    ]) {
      _invalid('fontWeight=$w', _pres(style: _style().copyWith(fontWeight: w)),
          'style.fontWeight');
    }
    _invalid(
        'selectedStyle.fontWeight',
        _pres(selectedStyle: _style().copyWith(fontWeight: FontWeight.w900)),
        'selectedStyle.fontWeight');
    for (final TextAlign a in <TextAlign>[
      TextAlign.left,
      TextAlign.center,
      TextAlign.right,
    ]) {
      _valid('textAlign=$a', _pres(style: _style().copyWith(textAlign: a)));
    }
    for (final TextAlign a in <TextAlign>[
      TextAlign.justify,
      TextAlign.start,
      TextAlign.end,
    ]) {
      _invalid('textAlign=$a', _pres(style: _style().copyWith(textAlign: a)),
          'style.textAlign');
    }
  });

  group('R-VAL-9 重复与一致性', () {
    test('同集合 Marker id 重复', () {
      expect(
        () => _validate(<Marker>[
          _marker(_pres(), id: 'dup'),
          _marker(_pres(), id: 'dup'),
        ], _images),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => e.toString(), 'message', contains('dup'))),
      );
    });
    test('不同 id 合法', () {
      expect(
        () => _validate(<Marker>[
          _marker(_pres(), id: 'a'),
          _marker(_pres(), id: 'b'),
        ], _images),
        returnsNormally,
      );
    });
    test('同 id 同来源合法', () {
      expect(
        () => _validate(<Marker>[_marker(_pres())], <MarkerImageResource>[
          const MarkerImageResource.asset(id: 'bg', assetName: 'a.png'),
          const MarkerImageResource.asset(id: 'bg', assetName: 'a.png'),
        ]),
        returnsNormally,
      );
    });
    final Map<String, MarkerImageResource> conflicts =
        <String, MarkerImageResource>{
      'assetName 不同':
          const MarkerImageResource.asset(id: 'bg', assetName: 'other.png'),
      'package 不同': const MarkerImageResource.asset(
          id: 'bg', assetName: 'a.png', package: 'p'),
      'pixelRatio 不同': const MarkerImageResource.asset(
          id: 'bg', assetName: 'a.png', pixelRatio: 2),
    };
    conflicts.forEach((String label, MarkerImageResource other) {
      test('同 id $label', () {
        expect(
          () => _validate(<Marker>[_marker(_pres())], <MarkerImageResource>[
            const MarkerImageResource.asset(id: 'bg', assetName: 'a.png'),
            other,
          ]),
          throwsA(isA<ArgumentError>().having(
              (ArgumentError e) => e.toString(), 'message', contains('bg'))),
        );
      });
    });
    test('同 id 类型不同（asset 与 bytes）', () {
      final MarkerImageResource bytes =
          MarkerImageResource.bytes(Uint8List.fromList(<int>[1, 2, 3]));
      expect(
        () => _validate(const <Marker>[], <MarkerImageResource>[
          MarkerImageResource.asset(id: bytes.id, assetName: 'a.png'),
          bytes,
        ]),
        throwsArgumentError,
      );
    });
  });

  group('R-VAL-10 规范化后再校验', () {
    _invalid('fontSize=0.001 规范化为 0',
        _pres(style: _style().copyWith(fontSize: 0.001)), 'style.fontSize');
    _invalid(
        'diameter=0.001 规范化为 0',
        _pres(
            style: const NativeMarkerStyle(
                background: NativeMarkerShapeBackground.circle(
                    diameter: 0.001, fillColor: Color(0xFFFFFFFF)))),
        'diameter');
    _invalidImages('pixelRatio=0.0001 规范化为 0', const <MarkerImageResource>[
      MarkerImageResource.asset(
          id: 'bg', assetName: 'a.png', pixelRatio: 0.0001),
    ], 'pixelRatio');
    _valid('min=10.004 max=10 规范化后相等',
        _pres(style: _style().copyWith(minWidth: 10.004, maxWidth: 10)));
    _invalid('min=10.02 max=10 规范化后仍 min>max',
        _pres(style: _style().copyWith(minWidth: 10.02, maxWidth: 10)),
        'minWidth');
    _valid('width=10.004 min=10 max=10',
        _pres(style: _style().copyWith(width: 10.004, minWidth: 10, maxWidth: 10)));
    _valid('负值 -0.001 规范化为 0 视为合法',
        _pres(style: _style().copyWith(width: -0.001)));
    _invalid('有限但过大的值无法规范化',
        _pres(style: _style().copyWith(width: 1e300)), 'style.width');
  });

  group('图片背景的箭头', () {
    _invalid(
        '图片背景的箭头缺颜色',
        _pres(
            style: _style(bg: const NativeMarkerImageBackground(imageId: 'bg'))
                .copyWith(arrow: _arrow)),
        'style.arrow.color');
    _valid(
        '图片背景的箭头有颜色',
        _pres(
            style: _style(bg: const NativeMarkerImageBackground(imageId: 'bg'))
                .copyWith(
                    arrow: const NativeMarkerArrow(
                        width: 10, height: 5, color: Color(0xFFFF0000)))));
    _valid('形状背景的箭头可沿用填充色', _pres());
    // D-1：形状背景的箭头颜色只能为空或等于 fillColor
    _valid(
        '形状背景的箭头颜色等于填充色',
        _pres(
            style: _style().copyWith(
                arrow: const NativeMarkerArrow(
                    width: 10, height: 5, color: Color(0xFFFFFFFF)))));
    _invalid(
        '形状背景的箭头颜色与填充色不同',
        _pres(
            style: _style().copyWith(
                arrow: const NativeMarkerArrow(
                    width: 10, height: 5, color: Color(0xFFFF0000)))),
        'style.arrow.color');
  });

  group('D-4 单行文字', () {
    for (final String t in <String>['望京\n120套', 'a\rb', 'a\r\nb']) {
      _invalid('文字含换行 ${t.codeUnits}',
          _pres(content: NativeMarkerContent(text: t)), 'content.text');
    }
    _valid('单行文字', _pres(content: const NativeMarkerContent(text: '望京 120套')));
  });

  group('MarkerTransition', () {
    void transition(String name, MarkerTransition t, {required bool ok}) {
      test('${ok ? "合法" : "非法"} $name', () {
        void run() => NativeMarkerValidator.validateTransition(t);
        ok ? expect(run, returnsNormally) : expect(run, throwsArgumentError);
      });
    }

    transition('immediate', const MarkerTransition.immediate(), ok: true);
    transition('1s',
        const MarkerTransition.replaceWhenReady(timeout: Duration(seconds: 1)),
        ok: true);
    transition('正好 5s',
        const MarkerTransition.replaceWhenReady(timeout: Duration(seconds: 5)),
        ok: true);
    transition(
        '5s+1ms',
        const MarkerTransition.replaceWhenReady(
            timeout: Duration(seconds: 5, milliseconds: 1)),
        ok: false);
    transition('0',
        const MarkerTransition.replaceWhenReady(timeout: Duration.zero),
        ok: false);
    transition('负数',
        const MarkerTransition.replaceWhenReady(timeout: Duration(seconds: -1)),
        ok: false);
  });
}
