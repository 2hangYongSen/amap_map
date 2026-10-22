import 'package:amap_map_example/widgets/amap_switch_button.dart';
import 'package:flutter/material.dart';

import 'package:amap_map/amap_map.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'dart:math';

class MarkerConfigDemoPage extends StatefulWidget {
  const MarkerConfigDemoPage({super.key});

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<MarkerConfigDemoPage> {
  static const LatLng mapCenter = LatLng(39.909187, 116.397451);

  final Map<String, Marker> _markers = <String, Marker>{};
  BitmapDescriptor? _markerIcon;
  String? selectedMarkerId;

  Future<void> _onMapCreated(AMapController controller) async {
    LatLng latLng = LatLng(mapCenter.latitude + sin(pi / 12.0) / 20.0,
        mapCenter.longitude + cos(pi / 12.0) / 20.0);
    try {
      print('-latLng---------$latLng');
      ScreenCoordinate coordinate = await controller.toScreenCoordinate(latLng);
      print('-coordinate---------$coordinate');
      LatLng reLatLng = await controller.fromScreenCoordinate(coordinate);
      print('-reLatLng---------$reLatLng');
    } catch (e) {
      print(e.toString());
    }
  }

  void _add() {
    final int markerCount = _markers.length;
    LatLng markPostion = LatLng(
        mapCenter.latitude + sin(markerCount * pi / 12.0) / 20.0,
        mapCenter.longitude + cos(markerCount * pi / 12.0) / 20.0);
    final Marker marker = Marker(
      position: markPostion,
      icon: _markerIcon!,
      infoWindow: InfoWindow(title: '第 $markerCount 个Marker'),
      onTap: (String markerId) => _onMarkerTapped(markerId),
      onDragEnd: (String markerId, LatLng endPosition) =>
          _onMarkerDragEnd(markerId, endPosition),
    );

    setState(() {
      _markers[marker.id] = marker;
    });
  }

  void _onMarkerTapped(String markerId) {
    final Marker? tappedMarker = _markers[markerId];
    if (!mounted || tappedMarker == null) return;
    final String? title = tappedMarker.infoWindow.title;
    print('$title 被点击了,markerId: $markerId');
    setState(() {
      selectedMarkerId = markerId;
    });
  }

  void _onMarkerDragEnd(String markerId, LatLng position) {
    final Marker? tappedMarker = _markers[markerId];
    if (!mounted || tappedMarker == null) return;
    final String? title = tappedMarker.infoWindow.title;
    print('$title markerId: $markerId 被拖拽到了: $position');
  }

  void _remove() {
    final Marker? selectedMarker = _markers[selectedMarkerId];
    //有选中的Marker
    if (selectedMarker != null) {
      setState(() {
        _markers.remove(selectedMarkerId);
        selectedMarkerId = null;
      });
    } else {
      print('无选中的Marker，无法删除');
    }
  }

  void _removeAll() {
    if (_markers.isNotEmpty) {
      setState(() {
        _markers.clear();
        selectedMarkerId = null;
      });
    }
  }

  void _changeInfo() async {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    final String newTitle = '${marker.infoWindow.title ?? ''}*';
    if (selectedMarkerId != null) {
      setState(() {
        _markers[selectedMarkerId!] = marker.copyWith(
          infoWindowParam: marker.infoWindow.copyWith(
            titleParam: newTitle,
          ),
        );
      });
    }
  }

  void _changeAnchor() {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    final Offset currentAnchor = marker.anchor;
    double dx = 0;
    double dy = 0;
    if (currentAnchor.dx < 1) {
      dx = currentAnchor.dx + 0.1;
    } else {
      dx = 0;
    }
    if (currentAnchor.dy < 1) {
      dy = currentAnchor.dy + 0.1;
    } else {
      dy = 0;
    }
    final Offset newAnchor = Offset(dx, dy);
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        anchorParam: newAnchor,
      );
    });
  }

  void _changePosition() {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    final LatLng current = marker.position;
    final Offset offset = Offset(
      mapCenter.latitude - current.latitude,
      mapCenter.longitude - current.longitude,
    );
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        positionParam: LatLng(
          mapCenter.latitude + offset.dy,
          mapCenter.longitude + offset.dx,
        ),
      );
    });
  }

  Future<void> _changeAlpha() async {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    final double current = marker.alpha;
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        alphaParam: current < 0.1 ? 1.0 : current * 0.75,
      );
    });
  }

  Future<void> _changeRotation() async {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    final double current = marker.rotation;
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        rotationParam: current == 330.0 ? 0.0 : current + 30.0,
      );
    });
  }

  Future<void> _toggleVisible(value) async {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        visibleParam: value,
      );
    });
  }

  Future<void> _toggleDraggable(value) async {
    final Marker? marker = _markers[selectedMarkerId];
    if (marker == null) return;
    setState(() {
      _markers[selectedMarkerId!] = marker.copyWith(
        draggableParam: value,
      );
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ///以下几种获取自定图片的方式使用其中一种即可。
    //最简单的方式
    _markerIcon ??= BitmapDescriptor.fromIconPath('assets/location_marker.png');

    final AMapWidget map = AMapWidget(
      onMapCreated: _onMapCreated,
      markers: Set<Marker>.of(_markers.values),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            width: MediaQuery.of(context).size.width,
            child: map,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Column(
                        children: <Widget>[
                          TextButton(
                            onPressed: _add,
                            child: Text('添加（当前 ${_markers.length} 个）'),
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _remove,
                            child: const Text('移除'),
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _changeInfo,
                            child: const Text('更新InfoWidow'),
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _changeAnchor,
                            child: const Text('修改锚点'),
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _changeAlpha,
                            child: const Text('修改透明度'),
                          ),
                        ],
                      ),
                      Column(
                        children: <Widget>[
                          TextButton(
                            onPressed: _markers.isNotEmpty ? _removeAll : null,
                            child: const Text('全部移除'),
                          ),
                          AMapSwitchButton(
                            label: const Text('允许拖动'),
                            onSwitchChanged:
                                (!_markers.containsKey(selectedMarkerId))
                                    ? null
                                    : _toggleDraggable,
                            defaultValue: false,
                          ),
                          AMapSwitchButton(
                            label: const Text('显示'),
                            onSwitchChanged:
                                (!_markers.containsKey(selectedMarkerId))
                                    ? null
                                    : _toggleVisible,
                            defaultValue: true,
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _changePosition,
                            child: const Text('修改坐标'),
                          ),
                          TextButton(
                            onPressed: (!_markers.containsKey(selectedMarkerId))
                                ? null
                                : _changeRotation,
                            child: const Text('修改旋转角度'),
                          ),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
