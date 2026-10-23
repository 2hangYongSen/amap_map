import 'dart:typed_data';

import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/native_marker/sync_queue.dart';
import 'package:flutter/painting.dart';
import 'package:x_amap_base/x_amap_base.dart';

import 'fake_marker_transport.dart';

export 'fake_marker_transport.dart';

const NativeMarkerStyle _style = NativeMarkerStyle(
  background: NativeMarkerShapeBackground.roundedRect(
      fillColor: Color(0xFFFFFFFF), cornerRadius: 4),
);

Marker nm(String id, String text,
        {String? iconId,
        bool selectable = false,
        ArgumentCallback<String>? onTap}) =>
    Marker(
      markerId: id,
      position: const LatLng(30, 120),
      selectable: selectable,
      onTap: onTap,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text, iconId: iconId),
        style: _style,
      ),
    );

Marker im(String id, {double lat = 30}) =>
    Marker(markerId: id, position: LatLng(lat, 120));

MarkerImageResource asset(String id) =>
    MarkerImageResource.asset(id: id, assetName: 'assets/$id.png');

final MarkerImageResource bytesImage =
    MarkerImageResource.bytes(Uint8List.fromList(<int>[1, 2, 3]));

List<String> methods(FakeMarkerTransport t) =>
    t.calls.map((SentCall c) => c.method).toList();

List<String> imageIds(Map<String, dynamic> p, [String key = 'imagesToAdd']) =>
    (p[key] as List<dynamic>)
        .map((dynamic m) => (m as Map<String, dynamic>)['id'] as String)
        .toList();

/// 握手返回
Map<Object?, Object?> snapshot({
  List<String> ready = const <String>[],
  List<String> failed = const <String>[],
  List<String> pending = const <String>[],
  int lastEventSeq = 0,
  List<Map<String, Object?>> errors = const <Map<String, Object?>>[],
}) =>
    <Object?, Object?>{
      'protocolVersion': 2,
      'syncId': 0,
      'rejectedMarkerIds': <String>[],
      'images': <String, Object?>{
        'ready': ready,
        'failed': <Map<String, Object?>>[
          for (final String id in failed)
            <String, Object?>{'id': id, 'code': 'imageDecodeFailed'},
        ],
        'pending': pending,
      },
      'selection': <String, Object?>{'selectedId': null, 'revision': 0},
      'lastEventSeq': lastEventSeq,
      'errors': errors,
    };

MarkerProtocolMessage imagesResult(int seq,
        {List<String> ready = const <String>[],
        List<String> failed = const <String>[]}) =>
    msg('marker#imagesResult', seq, <String, Object?>{
      'ready': ready,
      'failed': <Map<String, Object?>>[
        for (final String id in failed) <String, Object?>{'id': id},
      ],
    });

MarkerProtocolMessage decodeError(int seq, String imageId) =>
    msg('marker#nativeError', seq, <String, Object?>{
      'code': 'imageDecodeFailed',
      'imageId': imageId,
      'message': 'decode failed',
    });