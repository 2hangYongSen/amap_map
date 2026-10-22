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

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Expanded(
              child: AMapWidget(
            initialCameraPosition: _camera,
            markers: _fixtures.take(_count).toSet(),
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
                  : '当前 $_count 个默认图标；切换后等待显示稳定再拖动。'),
              const Text('无连续日志、不显示 FPS。用于点位数量对照，不代表原生文字点位方案性能。',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      );
}
