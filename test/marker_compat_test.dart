import 'package:amap_map/amap_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

// T-COMPAT-1：Marker 序列化与 1.0.15 逐键一致，新字段不参与序列化。
void main() {
  // 1.0.15 的 Marker.toMap 全部键（快照）
  const Set<String> legacyKeys = <String>{
    'id',
    'alpha',
    'anchor',
    'clickable',
    'draggable',
    'icon',
    'infoWindowEnable',
    'infoWindow',
    'position',
    'rotation',
    'visible',
    'zIndex',
  };

  Marker legacyMarker() {
    return Marker(
      markerId: 'm1',
      position: const LatLng(40, 116),
      alpha: 0.5,
      anchor: const Offset(0.25, 0.75),
      clickable: false,
      draggable: true,
      infoWindowEnable: false,
      infoWindow: const InfoWindow(title: 't', snippet: 's'),
      rotation: 30,
      visible: false,
      zIndex: 2,
    );
  }

  test('Marker.toMap 与 1.0.15 快照一致', () {
    expect(legacyMarker().toMap(), <String, dynamic>{
      'id': 'm1',
      'alpha': 0.5,
      'anchor': <dynamic>[0.25, 0.75],
      'clickable': false,
      'draggable': true,
      'icon': <dynamic>['defaultMarker'],
      'infoWindowEnable': false,
      'infoWindow': <String, dynamic>{'title': 't', 'snippet': 's'},
      'position': <dynamic>[40.0, 116.0],
      'rotation': 30.0,
      'visible': false,
      'zIndex': 2.0,
    });
  });

  test('MarkerUpdates.toMap 只有 1.0.15 的三个键', () {
    final Marker a = legacyMarker();
    final Marker b = Marker(markerId: 'm2', position: const LatLng(1, 2));
    final Marker aChanged = a.copyWith(visibleParam: true);
    final MarkerUpdates updates = MarkerUpdates.from(
      <Marker>{a, b}.toSet(),
      <Marker>{aChanged}.toSet(),
    );
    final Map<String, dynamic> map = updates.toMap();
    expect(map.keys.toSet(),
        <String>{'markersToAdd', 'markersToChange', 'markerIdsToRemove'});
    expect(map['markerIdsToRemove'], <String>['m2']);
    expect(map['markersToAdd'], isEmpty);
    final List<dynamic> changed = map['markersToChange'] as List<dynamic>;
    expect((changed.single as Map<String, dynamic>).keys.toSet(), legacyKeys);
  });
}
