import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// Refresh only the log panel; map movement must not rebuild the map widget.
class MapEventsPage extends StatefulWidget {
  const MapEventsPage({super.key});

  @override
  State<MapEventsPage> createState() => _MapEventsPageState();
}

class _MapEventsPageState extends State<MapEventsPage> {
  final ValueNotifier<List<String>> _logs =
      ValueNotifier<List<String>>(<String>[]);
  final Stopwatch _clock = Stopwatch()..start();
  int _lastCameraLog = -250;

  void _log(String message) {
    if (!mounted) return;
    _logs.value = <String>[message, ..._logs.value.take(49)];
  }

  @override
  void dispose() {
    _clock.stop();
    _logs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: AMapWidget(
              onMapCreated: (AMapController controller) => _log('地图已就绪'),
              onTap: (LatLng position) => _log('点击：$position'),
              onLongPress: (LatLng position) => _log('长按：$position'),
              onPoiTouched: (AMapPoi poi) => _log('POI：${poi.name}'),
              onCameraMove: (CameraPosition position) {
                if (_clock.elapsedMilliseconds - _lastCameraLog < 250) return;
                _lastCameraLog = _clock.elapsedMilliseconds;
                _log('移动：zoom=${position.zoom.toStringAsFixed(1)}');
              },
              onCameraMoveEnd: (CameraPosition position) => _log(
                  '移动结束：${position.target} zoom=${position.zoom.toStringAsFixed(1)}'),
            ),
          ),
          Row(
            children: <Widget>[
              const Expanded(
                  child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('事件记录（最多 50 条，相机日志间隔 250ms）'),
              )),
              IconButton(
                tooltip: '清空日志',
                onPressed: () => _logs.value = <String>[],
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Expanded(
            flex: 2,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: _logs,
              builder:
                  (BuildContext context, List<String> logs, Widget? child) =>
                      logs.isEmpty
                          ? const Center(child: Text('操作地图查看事件'))
                          : ListView.builder(
                              itemCount: logs.length,
                              itemBuilder: (BuildContext context, int index) =>
                                  Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                child: Text(logs[index],
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
            ),
          ),
        ],
      );
}
