import 'dart:typed_data';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/protocol.dart';
import 'package:amap_map/src/native_marker/sync_diff.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

const NativeMarkerStyle _full = NativeMarkerStyle(
  background: NativeMarkerShapeBackground.roundedRect(
      fillColor: Color(0xFFFFFFFF), cornerRadius: 4),
  arrow: NativeMarkerArrow(width: 10, height: 5),
  shadow: NativeMarkerShadow(color: Color(0x33000000), blurRadius: 2),
);

final NativeMarkerPresentation _presentation = NativeMarkerPresentation(
  content: const NativeMarkerContent(text: 'p', iconId: 'icon'),
  style: _full,
  selectedStyle: _full.copyWith(textColor: const Color(0xFFFFFFFF)),
  anchorType: NativeMarkerAnchorType.arrowTip,
);

Marker _native({NativeMarkerPresentation? p, double? selectedZ}) => Marker(
      markerId: 'm',
      position: const LatLng(30, 120),
      nativePresentation: p ?? _presentation,
      selectable: true,
      selectedZIndex: selectedZ,
    );

void main() {
  group('T-PROTO-1 渲染模式往返与清空', () {
    test('native → icon → native，renderMode 与互斥字段正确', () {
      final Marker n = _native(selectedZ: 99);
      final Marker i = n.copyWith(clearNativePresentation: true);
      final Marker back = i.copyWith(nativePresentationParam: _presentation);
      final Map<String, dynamic> a = markerToV2Map(n);
      final Map<String, dynamic> b = markerToV2Map(i);
      final Map<String, dynamic> c = markerToV2Map(back);
      expect(a['renderMode'], 'native');
      expect(a.containsKey('icon'), isTrue);
      expect(a['icon'], isNull);
      expect(a['selectedZIndex'], 99.0);
      expect(b['renderMode'], 'icon');
      expect(b.containsKey('nativePresentation'), isTrue);
      expect(b['nativePresentation'], isNull);
      expect(b['icon'], <dynamic>['defaultMarker']);
      expect(c, a);
    });

    Map<String, dynamic> styleOf(NativeMarkerPresentation p) =>
        presentationToMap(p)['style'] as Map<String, dynamic>;

    test('清空 selectedStyle', () {
      final Map<String, dynamic> m = presentationToMap(
          _presentation.copyWith(clearSelectedStyle: true));
      expect(m.containsKey('selectedStyle'), isTrue);
      expect(m['selectedStyle'], isNull);
    });

    test('清空 arrow 与 shadow', () {
      final Map<String, dynamic> s = styleOf(_presentation.copyWith(
          style: _full.copyWith(clearArrow: true, clearShadow: true)));
      expect(s.containsKey('arrow'), isTrue);
      expect(s['arrow'], isNull);
      expect(s.containsKey('shadow'), isTrue);
      expect(s['shadow'], isNull);
    });

    test('清空 iconId', () {
      final Map<String, dynamic> content = presentationToMap(
          _presentation.copyWith(
              content: _presentation.content.copyWith(clearIconId: true)))[
          'content'] as Map<String, dynamic>;
      expect(content.containsKey('iconId'), isTrue);
      expect(content['iconId'], isNull);
    });

    test('清空 selectedZIndex', () {
      final Map<String, dynamic> m = markerToV2Map(
          _native(selectedZ: 99).copyWith(clearSelectedZIndex: true));
      expect(m.containsKey('selectedZIndex'), isTrue);
      expect(m['selectedZIndex'], isNull);
    });

    test('样式字段编码', () {
      final Map<String, dynamic> s = styleOf(_presentation);
      expect(s['fontWeight'], 400);
      expect(s['textColor'], 0xFF000000);
      expect(s['textAlign'], 'center');
      expect(s['padding'], <double>[0, 0, 0, 0]);
      expect((s['background'] as Map<String, dynamic>)['kind'], 'roundedRect');
      expect(presentationToMap(_presentation)['anchorType'], 'arrowTip');
    });
  });

  group('资源差异', () {
    final MarkerImageResource img =
        MarkerImageResource.bytes(Uint8List.fromList(<int>[1, 2, 3]));
    Marker withBg(String imageId, {String text = 't'}) => Marker(
          markerId: 'c',
          position: const LatLng(30, 120),
          nativePresentation: NativeMarkerPresentation(
            content: NativeMarkerContent(text: text),
            style: NativeMarkerStyle(
                background: NativeMarkerImageBackground(imageId: imageId)),
          ),
        );

    test('被保留点位仍引用的资源不释放（R-RES-3）', () {
      const MarkerImageResource other = MarkerImageResource.asset(
          id: 'other', assetName: 'assets/o.png');
      // C 使用 img，目标改为 C 使用 other 并移除 img
      final MarkerSyncDiff d = computeMarkerDiff(
        confirmed: <String, Marker>{'c': withBg(img.id)},
        rejected: <String, Marker>{},
        confirmedImages: <String, MarkerImageResource>{img.id: img},
        target: <String, Marker>{'c': withBg('other')},
        targetImages: <String, MarkerImageResource>{'other': other},
      );
      expect(d.imagesToAdd.keys, <String>['other']);
      // 修改可能被拒绝，旧依赖本次不能释放
      expect(d.imagesToRelease, isEmpty);
      // 修改确认后再算一次即可释放
      final MarkerSyncDiff after = computeMarkerDiff(
        confirmed: <String, Marker>{'c': withBg('other')},
        rejected: <String, Marker>{},
        confirmedImages: <String, MarkerImageResource>{
          img.id: img,
          'other': other,
        },
        target: <String, Marker>{'c': withBg('other')},
        targetImages: <String, MarkerImageResource>{'other': other},
      );
      expect(after.imagesToRelease, <String>{img.id});
      expect(after.adds.isEmpty && after.changes.isEmpty, isTrue);
    });

    test('资源字节只出现在 imagesToAdd，点位只带 id', () {
      final MarkerSyncDiff d = computeMarkerDiff(
        confirmed: <String, Marker>{},
        rejected: <String, Marker>{},
        confirmedImages: <String, MarkerImageResource>{},
        target: <String, Marker>{'c': withBg(img.id)},
        targetImages: <String, MarkerImageResource>{img.id: img},
      );
      final Map<String, dynamic> p = d.toV2Payload(1);
      expect((p['imagesToAdd'] as List<dynamic>).single['data'],
          isA<Uint8List>());
      expect(p['imageIdsToRelease'], isEmpty);
      final Map<String, dynamic> m = (p['markersToAdd'] as List<dynamic>).single;
      expect(m['nativePresentation']['style']['background']['imageId'], img.id);
    });
  });
}
