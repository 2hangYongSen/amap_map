import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

NativeMarkerStyle _style() => const NativeMarkerStyle(
      background: NativeMarkerShapeBackground.roundedRect(
          fillColor: Color(0xFFFFFFFF), cornerRadius: 13),
      arrow: NativeMarkerArrow(width: 10, height: 5),
      shadow: NativeMarkerShadow(color: Color(0x33000000), blurRadius: 4),
      width: 60,
      height: 26,
      minWidth: 20,
      maxWidth: 100,
    );

NativeMarkerPresentation _presentation() => NativeMarkerPresentation(
      content: const NativeMarkerContent(text: '300万', iconId: 'i'),
      style: _style(),
      selectedStyle: _style().copyWith(fontSize: 14),
      anchorType: NativeMarkerAnchorType.custom,
      anchor: const Offset(0.5, 1),
    );

void main() {
  group('NativeMarkerStyle', () {
    test('== 与 hashCode', () {
      expect(_style(), _style());
      expect(_style().hashCode, _style().hashCode);
      expect(_style(), isNot(_style().copyWith(fontSize: 13)));
    });

    test('copyWith 可清空可空字段', () {
      final NativeMarkerStyle s = _style();
      expect(s.copyWith(clearArrow: true).arrow, isNull);
      expect(s.copyWith(clearShadow: true).shadow, isNull);
      expect(s.copyWith(clearWidth: true).width, isNull);
      expect(s.copyWith(clearHeight: true).height, isNull);
      expect(s.copyWith(clearMinWidth: true).minWidth, isNull);
      expect(s.copyWith(clearMaxWidth: true).maxWidth, isNull);
      // 不传参数保持原值
      expect(s.copyWith(), s);
    });
  });

  group('NativeMarkerContent / Presentation', () {
    test('Content copyWith 清空', () {
      const NativeMarkerContent c =
          NativeMarkerContent(text: 'a', iconId: 'i', iconSize: Size(10, 10));
      expect(c.copyWith(clearText: true).text, isNull);
      expect(c.copyWith(clearIconId: true).iconId, isNull);
      expect(c.copyWith(clearIconSize: true).iconSize, isNull);
      expect(c.copyWith(text: 'b').text, 'b');
    });

    test('Presentation copyWith 清空', () {
      final NativeMarkerPresentation p = _presentation();
      expect(p.copyWith(clearSelectedStyle: true).selectedStyle, isNull);
      expect(p.copyWith(clearAnchor: true).anchor, isNull);
      expect(p.copyWith(), p);
      expect(p, _presentation());
    });

    test('背景 == 区分形状与图片', () {
      expect(
          const NativeMarkerShapeBackground.circle(
              diameter: 10, fillColor: Color(0xFF000000)),
          const NativeMarkerShapeBackground.circle(
              diameter: 10, fillColor: Color(0xFF000000)));
      expect(
          const NativeMarkerShapeBackground.circle(
              diameter: 10, fillColor: Color(0xFF000000)),
          isNot(const NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFF000000))));
      expect(const NativeMarkerImageBackground(imageId: 'a'),
          isNot(const NativeMarkerImageBackground(imageId: 'b')));
    });
  });

  group('Marker 扩展', () {
    Marker base() => Marker(
          markerId: 'h:1',
          position: const LatLng(40, 116),
          nativePresentation: _presentation(),
          selectable: true,
          selectedZIndex: 99,
        );

    test('markerId 作为 id，空串抛错，缺省自动生成', () {
      expect(base().id, 'h:1');
      expect(() => Marker(markerId: '', position: const LatLng(1, 1)),
          throwsArgumentError);
      expect(Marker(position: const LatLng(1, 1)).id, isNotEmpty);
    });

    test('== 覆盖新字段', () {
      expect(base(), base());
      expect(base().hashCode, base().hashCode);
      expect(base(), isNot(base().copyWith(selectableParam: false)));
      expect(base(), isNot(base().copyWith(selectedZIndexParam: 50)));
      expect(
          base(),
          isNot(base().copyWith(
              nativePresentationParam:
                  _presentation().copyWith(clearSelectedStyle: true))));
    });

    test('copyWith 可清空新字段并可修改 zIndex', () {
      final Marker m = base();
      expect(
          m.copyWith(clearNativePresentation: true).nativePresentation, isNull);
      expect(m.copyWith(clearSelectedZIndex: true).selectedZIndex, isNull);
      expect(m.copyWith(zIndexParam: 5).zIndex, 5);
      expect(m.copyWith().zIndex, m.zIndex);
      expect(m.copyWith().id, 'h:1');
      expect(m.clone(), m);
    });

    test('新字段不参与序列化（S1 阶段）', () {
      final Map<String, dynamic> map = base().toMap();
      for (final String k in <String>[
        'nativePresentation',
        'selectable',
        'selectedZIndex',
        'renderMode',
      ]) {
        expect(map.containsKey(k), isFalse, reason: k);
      }
    });

    test('同一集合内 id 重复抛 ArgumentError', () {
      final Marker a = Marker(markerId: 'x', position: const LatLng(1, 1));
      final Marker b =
          Marker(markerId: 'x', position: const LatLng(2, 2), visible: false);
      expect(() => keyByMarkerId(<Marker>[a, b]), throwsArgumentError);
      expect(() => MarkerUpdates.from(<Marker>{a}, <Marker>{a, b}),
          throwsArgumentError);
      expect(keyByMarkerId(<Marker>[a]).keys, <String>['x']);
    });
  });

  group('选择与过渡类型', () {
    test('== 与默认值', () {
      expect(const MarkerSelectionOptions(), const MarkerSelectionOptions());
      expect(const MarkerSelectionOptions().deselectOnMapTap, isTrue);
      expect(const MarkerTransition.immediate(),
          const MarkerTransition.immediate());
      expect(
          const MarkerTransition.replaceWhenReady(
              timeout: Duration(seconds: 1)),
          isNot(const MarkerTransition.immediate()));
      expect(
          const MarkerSelectionChange(
              selectedId: 'a',
              previousId: null,
              reason: MarkerSelectionReason.api,
              revision: 1),
          const MarkerSelectionChange(
              selectedId: 'a',
              previousId: null,
              reason: MarkerSelectionReason.api,
              revision: 1));
      expect(
          const NativeMarkerError(
              code: NativeMarkerErrorCode.invalidConfig, message: 'm'),
          const NativeMarkerError(
              code: NativeMarkerErrorCode.invalidConfig, message: 'm'));
    });
  });
}
