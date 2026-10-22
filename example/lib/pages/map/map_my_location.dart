import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:x_amap_base/x_amap_base.dart';

class MyLocationPage extends StatefulWidget {
  const MyLocationPage({super.key});
  @override
  State<MyLocationPage> createState() => _BodyState();
}

class _BodyState extends State<MyLocationPage> {
  AMapController? _controller;
  LatLng? _lastLocation;
  bool _permissionGranted = false;
  bool _requesting = false;
  bool _centered = false;
  String _status = '等待定位权限';

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final PermissionStatus permission = await Permission.location.request();
      if (!mounted) return;
      setState(() {
        _permissionGranted = permission.isGranted;
        _status =
            _permissionGranted ? '权限已授予，等待定位。请确认系统定位已开启。' : '未获得定位权限，请授权后重试。';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '权限请求失败：$error');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _locate() async {
    final AMapController? controller = _controller;
    final LatLng? position = _lastLocation;
    if (controller == null || position == null) return;
    _centered = true;
    try {
      await controller.moveCamera(CameraUpdate.newLatLngZoom(position, 16));
    } catch (error) {
      if (!mounted) return;
      _centered = false;
      setState(() => _status = '移动视野失败：$error');
    }
  }

  void _onLocation(AMapLocation location) {
    if (!mounted || !isLocationValid(location)) return;
    setState(() {
      _lastLocation = location.latLng;
      _status = '定位成功：${location.latLng.latitude.toStringAsFixed(5)}, '
          '${location.latLng.longitude.toStringAsFixed(5)}';
    });
    if (!_centered) _locate();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Expanded(
            child: !_permissionGranted
                ? const Center(child: Text('授予定位权限后加载定位地图'))
                : AMapWidget(
                    myLocationStyleOptions: MyLocationStyleOptions(
                      true,
                      circleFillColor: const Color(0x2233AAFF),
                      circleStrokeColor: Colors.blue,
                      circleStrokeWidth: 1,
                    ),
                    onLocationChanged: _onLocation,
                    onMapCreated: (AMapController controller) {
                      if (!mounted) return;
                      setState(() => _controller = controller);
                      // A location may arrive before the map-ready callback.
                      if (!_centered) _locate();
                    },
                  ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton(
                onPressed: _controller != null && _lastLocation != null
                    ? _locate
                    : null,
                child: const Text('回到我的位置'),
              ),
              if (!_permissionGranted) ...<Widget>[
                TextButton(
                    onPressed: _requesting ? null : _requestPermission,
                    child: const Text('重新请求权限')),
                TextButton(
                    onPressed: openAppSettings, child: const Text('打开应用设置')),
              ],
            ],
          ),
        ],
      );
}
