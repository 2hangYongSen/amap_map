import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';

import 'compare/compare_controller.dart';
import 'compare/compare_markers.dart';
import 'compare/flutter_load.dart';

/// AM-P02：原生点位 vs 缓存 PNG 对照页。
/// 同一张地图、同一批数据，按钮切换方案；切换时清空点位和两边缓存。
class MarkerComparePage extends StatefulWidget {
  const MarkerComparePage({super.key, this.controller});

  /// 集成测试传入以驱动页面；为空时页面自己创建
  final CompareController? controller;

  @override
  State<MarkerComparePage> createState() => _MarkerComparePageState();
}

class _MarkerComparePageState extends State<MarkerComparePage> {
  late final CompareController _c = widget.controller ?? CompareController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.dpr = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (BuildContext context, _) => Column(children: <Widget>[
          Expanded(
            child: Stack(children: <Widget>[
              AMapWidget(
                initialCameraPosition:
                    const CameraPosition(target: compareCenter, zoom: 13),
                markers: _c.extra.isEmpty
                    ? _c.markers
                    : <Marker>{..._c.markers, ..._c.extra},
                // 诊断回调非空即开启回执；两种方案都开，口径一致
                onMarkerUpdateApplied: _c.onUpdateApplied,
                onMarkerTapApplied: _c.onTapApplied,
                // 原生方案的选中由原生完成；PNG 点位不是 selectable，不受影响
                markerSelection: const MarkerSelectionOptions(),
                onMapCreated: _c.attach,
              ),
              // 负载层叠在地图上，不拦截触摸
              Positioned.fill(child: FlutterLoadLayer(load: _c.load)),
            ]),
          ),
          _panel(),
        ]),
      );

  Widget _panel() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
                for (final CompareScheme s in CompareScheme.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _c.scheme == s,
                    onSelected: _ready ? (_) => _c.setScheme(s) : null,
                  ),
                for (final int n in <int>[200, 500, 1000])
                  ChoiceChip(
                    label: Text('$n 点'),
                    selected: _c.count == n,
                    onSelected: _ready ? (_) => _c.setCount(n) : null,
                  ),
                for (final FlutterLoad l in FlutterLoad.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _c.load == l,
                    onSelected: _ready ? (_) => _c.setLoad(l) : null,
                  ),
              ]),
              Wrap(spacing: 8, children: <Widget>[
                FilledButton(
                    onPressed: _ready ? _c.push : null,
                    child: const Text('推送新价格')),
                FilledButton.tonal(
                    onPressed: _ready ? _c.panAndPush : null,
                    child: const Text('平移中推送')),
                OutlinedButton(
                    onPressed: _ready ? _c.reset : null,
                    child: const Text('清空')),
              ]),
              Text(_resultText(), style: const TextStyle(fontSize: 12)),
              Text(_tapText(), style: const TextStyle(fontSize: 12)),
            ]),
      );

  bool get _ready => _c.map != null && !_c.busy;

  String _ms(double? v) => v == null ? '-' : v.toStringAsFixed(1);

  /// 点击计时：最近一次，以及当前方案对应路径的 P50 / P95
  String _tapText() {
    final MarkerTapPath path = _c.scheme == CompareScheme.native
        ? MarkerTapPath.native
        : MarkerTapPath.icon;
    final List<double> xs = <double>[
      for (final MarkerTapReport t in _c.taps)
        if (t.path == path) t.c1ToC2Ms
    ];
    if (xs.isEmpty) return '点击点位查看 c1→c2（原生收到点击 → 选中外观提交）';
    final MarkerTapReport t = _c.taps.lastWhere((MarkerTapReport t) => t.path == path);
    return '点击 ${xs.length} 次：最近 ${_ms(t.c1ToC2Ms)}ms（绘制 ${t.drawCount}），'
        'P50 ${_ms(percentile(xs, 0.5))}ms，P95 ${_ms(percentile(xs, 0.95))}ms';
  }

  String _resultText() {
    final PushResult? r = _c.last;
    if (_c.map == null) return '等待地图就绪…';
    if (r == null) return '当前：${_c.scheme.label}，${_c.count} 点。点“推送新价格”开始。';
    return <String>[
      '${r.scheme.label} ${r.count} 点${r.panning ? '（平移中）' : ''}：构造 ${_ms(r.buildMs)}ms'
          '${r.scheme == CompareScheme.png ? '（含生成 PNG ${r.pngGenerated} 张）' : ''}',
      '到达→发送 ${_ms(r.t0t1)}ms，原生应用 ${_ms(r.t2t4)}ms，'
          '到达→应用（估算）${_ms(r.t0t4)}ms',
      '原生绘制 ${r.draws} 次，传输 ${(r.bytes / 1024).toStringAsFixed(1)}KB',
      r.frames == null
          ? 'Flutter 帧统计中（到回执后 ${CompareController.jankTail.inSeconds}s）…'
          : '${r.load.label}：${r.frames} 帧，卡顿 ${r.jankBuild! + r.jankRaster!}'
              '（界面 ${r.jankBuild} / 绘制 ${r.jankRaster}），最长 ${_ms(r.worstFrameMs)}ms',
    ].join('\n');
  }
}
