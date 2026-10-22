import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

class MarkerBenchmarkPage extends StatefulWidget {
  const MarkerBenchmarkPage({super.key});

  @override
  State<MarkerBenchmarkPage> createState() => _MarkerBenchmarkPageState();
}

class _MarkerBenchmarkPageState extends State<MarkerBenchmarkPage> {
  static const CameraPosition _camera = CameraPosition(
    target: LatLng(39.917998, 116.397164),
    zoom: 12,
  );
  late final List<Marker> _fixtures;
  AMapController? _controller;
  int _count = 0;
  // 旧路径对照：false 为默认图标，true 为 Dart 端绘制的 PNG（Marker.icon + fromBytes）。
  bool _usePng = false;
  BitmapDescriptor? _pngIcon;

  @override
  void initState() {
    super.initState();
    // Fixed coordinates and stable IDs across count switches.
    _fixtures = List<Marker>.generate(
        200,
        (int index) => Marker(
              position: LatLng(
                _camera.target.latitude + (index ~/ 20 - 4.5) * 0.004,
                _camera.target.longitude + (index % 20 - 9.5) * 0.004,
              ),
              infoWindowEnable: false,
            ));
  }

  // 绘制一个 48x48 的圆形 PNG，作为旧 Marker.icon 路径的对照图标。
  Future<BitmapDescriptor> _buildPngIcon() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(24, 24), 22, Paint()..color = Colors.orange);
    canvas.drawCircle(
        const Offset(24, 24),
        22,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final ui.Image image = await recorder.endRecording().toImage(48, 48);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _setUsePng(bool value) async {
    if (value && _pngIcon == null) {
      try {
        _pngIcon = await _buildPngIcon();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('生成 PNG 图标失败：$error')));
        return;
      }
    }
    if (mounted) setState(() => _usePng = value);
  }

  Set<Marker> _currentMarkers() => _fixtures
      .take(_count)
      .map((Marker m) => _usePng && _pngIcon != null
          ? m.copyWith(iconParam: _pngIcon)
          : m)
      .toSet();

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Expanded(
              child: AMapWidget(
            initialCameraPosition: _camera,
            markers: _currentMarkers(),
            onMapCreated: (AMapController controller) {
              if (mounted) setState(() => _controller = controller);
            },
          )),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: <Widget>[
              Wrap(spacing: 8, children: <Widget>[
                for (final int count in <int>[0, 100, 200])
                  ChoiceChip(
                    label: Text('$count 点'),
                    selected: _count == count,
                    onSelected: _controller == null
                        ? null
                        : (bool selected) {
                            if (selected) setState(() => _count = count);
                          },
                  ),
                for (final bool png in <bool>[false, true])
                  ChoiceChip(
                    label: Text(png ? 'PNG 图标' : '默认图标'),
                    selected: _usePng == png,
                    onSelected: _controller == null
                        ? null
                        : (bool selected) {
                            if (selected) _setUsePng(png);
                          },
                  ),
                TextButton(
                  onPressed: _controller == null
                      ? null
                      : () async {
                          try {
                            await _controller!.moveCamera(
                                CameraUpdate.newCameraPosition(_camera),
                                animated: false);
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('重置视野失败：$error')));
                          }
                        },
                  child: const Text('重置视野'),
                ),
              ]),
              Text(_controller == null
                  ? '等待地图就绪…'
                  : '当前 $_count 个${_usePng ? "PNG" : "默认"}图标；切换后等待显示稳定再拖动。'),
              const Text('无连续日志、不显示 FPS。用于点位数量对照，不代表原生文字点位方案性能。',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      );
}
