import 'dart:math';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 原生点位形状示例（S10）：价格气泡、片区圆、长文案省略、价格待定、阴影与批量。
class NativeMarkerShapePage extends StatefulWidget {
  const NativeMarkerShapePage({super.key});

  @override
  State<NativeMarkerShapePage> createState() => _NativeMarkerShapePageState();
}

class _NativeMarkerShapePageState extends State<NativeMarkerShapePage> {
  static const LatLng _center = LatLng(39.909187, 116.397451);
  final Map<String, Marker> _markers = <String, Marker>{};
  bool _shadow = true;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    _markers.addAll(_buildBase());
  }

  /// 价格气泡：白底圆角矩形加箭头，锚点在箭头尖端
  Marker _price(String id, LatLng at, String text, {bool shadow = true}) {
    return Marker(
      markerId: id,
      position: at,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: NativeMarkerStyle(
          background: const NativeMarkerShapeBackground.roundedRect(
            fillColor: Color(0xFFFFFFFF),
            cornerRadius: 6,
            borderColor: Color(0x33000000),
            borderWidth: 1,
          ),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          textColor: const Color(0xFFE53935),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          maxWidth: 96,
          arrow: const NativeMarkerArrow(width: 10, height: 6),
          shadow: shadow
              ? const NativeMarkerShadow(
                  color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2))
              : null,
        ),
      ),
    );
  }

  /// 片区圆：蓝色圆形，居中显示片区名与套数，锚点在圆心
  Marker _area(String id, LatLng at, String text, Color color) {
    return Marker(
      markerId: id,
      position: at,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        style: NativeMarkerStyle(
          background: NativeMarkerShapeBackground.circle(
            diameter: 56,
            fillColor: color,
            borderColor: const Color(0xFFFFFFFF),
            borderWidth: 2,
          ),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          textColor: const Color(0xFFFFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shadow: _shadow
              ? const NativeMarkerShadow(
                  color: Color(0x44000000), blurRadius: 3, offset: Offset(0, 1))
              : null,
        ),
      ),
    );
  }

  Map<String, Marker> _buildBase() {
    const double d = 0.004;
    final List<Marker> list = <Marker>[
      _price('p1', _center, '¥3000', shadow: _shadow),
      _price('p2', LatLng(_center.latitude + d, _center.longitude), '¥12.5万',
          shadow: _shadow),
      _price('p3', LatLng(_center.latitude, _center.longitude + d), '价格待定',
          shadow: _shadow),
      // 超过 maxWidth：尾部省略
      _price('p4', LatLng(_center.latitude - d, _center.longitude),
          '朝阳区望京西园三区超长小区名称',
          shadow: _shadow),
      _area('a1', LatLng(_center.latitude + d, _center.longitude - d * 1.5),
          '望京\n120套', const Color(0xFF1E88E5)),
      _area('a2', LatLng(_center.latitude - d, _center.longitude + d * 1.5),
          '国贸 85', const Color(0xFF43A047)),
    ];
    return <String, Marker>{for (final Marker m in list) m.id: m};
  }

  void _toggleShadow() {
    setState(() {
      _shadow = !_shadow;
      _markers
        ..clear()
        ..addAll(_buildBase());
    });
  }

  /// 同一个点反复改文案，检查整体替换后锚点不漂移
  void _changeText() {
    setState(() {
      _round++;
      _markers['p1'] =
          _price('p1', _center, '¥${3000 + _round * 100}', shadow: _shadow);
    });
  }

  /// 批量 200 个价格气泡，检查分帧应用与滚动流畅度
  void _addBatch() {
    final Random rnd = Random(_round + 7);
    setState(() {
      _round++;
      for (int i = 0; i < 200; i++) {
        final String id = 'b$i';
        _markers[id] = _price(
            id,
            LatLng(_center.latitude + (rnd.nextDouble() - 0.5) * 0.04,
                _center.longitude + (rnd.nextDouble() - 0.5) * 0.06),
            '¥${1000 + rnd.nextInt(9000)}',
            shadow: _shadow);
      }
    });
  }

  void _clearBatch() {
    setState(
        () => _markers.removeWhere((String k, Marker _) => k.startsWith('b')));
  }

  Widget _button(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: AMapWidget(
            initialCameraPosition:
                const CameraPosition(target: _center, zoom: 15),
            markers: Set<Marker>.of(_markers.values),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              _button(_shadow ? '关闭阴影' : '开启阴影', _toggleShadow),
              _button('改文案', _changeText),
              _button('加 200 个', _addBatch),
              _button('清除批量', _clearBatch),
            ],
          ),
        ),
      ],
    );
  }
}
