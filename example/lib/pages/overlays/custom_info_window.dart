import 'package:flutter/material.dart';

import 'package:amap_map/amap_map.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'dart:math';

/// 自定义[InfoWindow]用例
class CustomInfoWindowDemoPage extends StatefulWidget {
  const CustomInfoWindowDemoPage();

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<CustomInfoWindowDemoPage> {
  static const LatLng mapCenter = LatLng(39.909187, 116.397451);

  final Map<String, Marker> _markers = <String, Marker>{};
  BitmapDescriptor? _markerIcon;
  String? selectedMarkerId;
  AMapController? _controller;

  Marker? get _selectedMarker => _markers[selectedMarkerId];

  void _onMapCreated(AMapController controller) {
    if (!mounted) return;
    setState(() {
      _controller = controller;
    });
  }

  void _add() {
    final int markerCount = _markers.length;
    LatLng markPostion = LatLng(
        mapCenter.latitude + sin(markerCount * pi / 12.0) / 20.0,
        mapCenter.longitude + cos(markerCount * pi / 12.0) / 20.0);
    final Marker marker = Marker(
      position: markPostion,
      icon: _markerIcon!,
      // 使用 Flutter 自定义窗口，避免同时显示原生气泡。
      infoWindowEnable: false,
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
    setState(() {
      _markers[markerId] = tappedMarker.copyWith(positionParam: position);
    });
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

  void _changeInfo() {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;
    final String newTitle = '${marker.infoWindow.title ?? ''}*';
    if (selectedMarkerId != null) {
      setState(() {
        _markers[marker.id] = marker.copyWith(
          infoWindowParam: marker.infoWindow.copyWith(
            titleParam: newTitle,
          ),
        );
      });
    }
  }

  void _changeAnchor() {
    final Marker? marker = _selectedMarker;
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
      _markers[marker.id] = marker.copyWith(
        anchorParam: newAnchor,
      );
    });
  }

  void _changePosition() {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;
    final LatLng current = marker.position;
    final Offset offset = Offset(
      mapCenter.latitude - current.latitude,
      mapCenter.longitude - current.longitude,
    );
    setState(() {
      _markers[marker.id] = marker.copyWith(
        positionParam: LatLng(
          mapCenter.latitude + offset.dy,
          mapCenter.longitude + offset.dx,
        ),
      );
    });
  }

  void _changeAlpha() {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;
    final double current = marker.alpha;
    setState(() {
      _markers[marker.id] = marker.copyWith(
        alphaParam: current < 0.1 ? 1.0 : current * 0.75,
      );
    });
  }

  void _changeRotation() {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;
    final double current = marker.rotation;
    setState(() {
      _markers[marker.id] = marker.copyWith(
        rotationParam: current == 330.0 ? 0.0 : current + 30.0,
      );
    });
  }

  void _toggleVisible(bool value) {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;

    setState(() {
      _markers[marker.id] = marker.copyWith(
        visibleParam: value,
      );
    });
  }

  void _toggleDraggable(bool value) {
    final Marker? marker = _selectedMarker;
    if (marker == null) return;
    setState(() {
      _markers[marker.id] = marker.copyWith(
        draggableParam: value,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ///以下几种获取自定图片的方式使用其中一种即可。
    //最简单的方式
    _markerIcon ??= BitmapDescriptor.fromIconPath('assets/location_marker.png');

    final Marker? selectedMarker = _selectedMarker;
    AMapWidget map = AMapWidget(
      onMapCreated: _onMapCreated,
      markers: Set<Marker>.of(_markers.values),
      infoWindowAdapter: CustomInfoWindowAdapter(_controller, selectedMarkerId),
    );
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
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
                            onPressed:
                                (selectedMarker == null) ? null : _remove,
                            child: const Text('移除'),
                          ),
                          TextButton(
                            onPressed:
                                (selectedMarker == null) ? null : _changeInfo,
                            child: const Text('更新InfoWindow'),
                          ),
                          TextButton(
                            onPressed:
                                (selectedMarker == null) ? null : _changeAnchor,
                            child: const Text('修改锚点'),
                          ),
                          TextButton(
                            onPressed:
                                (selectedMarker == null) ? null : _changeAlpha,
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('允许拖动'),
                              Switch(
                                value: selectedMarker?.draggable ?? false,
                                onChanged: selectedMarker == null
                                    ? null
                                    : _toggleDraggable,
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('显示'),
                              Switch(
                                value: selectedMarker?.visible ?? true,
                                onChanged: selectedMarker == null
                                    ? null
                                    : _toggleVisible,
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: (selectedMarker == null)
                                ? null
                                : _changePosition,
                            child: const Text('修改坐标'),
                          ),
                          TextButton(
                            onPressed: (selectedMarker == null)
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

class CustomInfoWindowAdapter extends BaseInfoWindowAdapter {
  CustomInfoWindowAdapter(super.controller, this.selectedMarkerId);

  final String? selectedMarkerId;

  @override
  Widget? buildInfoWindowContent(BuildContext context, Marker marker) {
    if (marker.id != selectedMarkerId || !marker.visible) {
      return null;
    }
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        boxShadow: <BoxShadow>[
          const BoxShadow(
            color: Colors.black26,
            blurRadius: 4.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            marker.infoWindow.title ?? 'No Title',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            marker.infoWindow.snippet ?? 'No Snippet',
          ),
        ],
      ),
    );
  }
}
