import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 原生点位选择与集合替换示例（S12）：点击选中、重复点击取消、片区点只回调、
/// 价格层与片区层 replaceWhenReady 切换。
class NativeMarkerSelectionPage extends StatefulWidget {
  const NativeMarkerSelectionPage({super.key});

  @override
  State<NativeMarkerSelectionPage> createState() =>
      _NativeMarkerSelectionPageState();
}

class _NativeMarkerSelectionPageState extends State<NativeMarkerSelectionPage> {
  static const LatLng _center = LatLng(39.909187, 116.397451);
  AMapController? _controller;
  bool _priceLayer = true;
  bool _replace = true;
  String _log = '点击价格气泡选中，再点一次取消；片区圆只回调';

  /// 价格气泡：选中态换红底白字并置顶（selectedZIndex）
  Marker _price(String id, LatLng at, String text) {
    const NativeMarkerShapeBackground white =
        NativeMarkerShapeBackground.roundedRect(
            fillColor: Color(0xFFFFFFFF), cornerRadius: 6);
    const NativeMarkerShapeBackground red =
        NativeMarkerShapeBackground.roundedRect(
            fillColor: Color(0xFFE53935), cornerRadius: 6);
    const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    const NativeMarkerShadow shadow = NativeMarkerShadow(
        color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2));
    return Marker(
      markerId: id,
      position: at,
      selectable: true,
      zIndex: 1,
      selectedZIndex: 99,
      onTap: (String id) => _note('onTap $id'),
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: const NativeMarkerStyle(
          background: white,
          fontSize: 13,
          textColor: Color(0xFFE53935),
          padding: pad,
          arrow: NativeMarkerArrow(width: 10, height: 6),
          shadow: shadow,
        ),
        selectedStyle: const NativeMarkerStyle(
          background: red,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          textColor: Color(0xFFFFFFFF),
          padding: pad,
          arrow: NativeMarkerArrow(width: 10, height: 6),
          shadow: shadow,
        ),
      ),
    );
  }

  /// 片区圆：不可选中，点击只走 Marker.onTap（R-SEL-2）
  Marker _area(String id, LatLng at, String text) {
    return Marker(
      markerId: id,
      position: at,
      onTap: (String id) => _note('片区 onTap $id（选择不变）'),
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        style: const NativeMarkerStyle(
          background: NativeMarkerShapeBackground.circle(
              diameter: 56, fillColor: Color(0xFF1E88E5)),
          fontSize: 12,
          textColor: Color(0xFFFFFFFF),
        ),
      ),
    );
  }

  Set<Marker> _markers() {
    const double d = 0.004;
    if (_priceLayer) {
      return <Marker>{
        _price('p1', _center, '¥3000'),
        _price('p2', LatLng(_center.latitude + d, _center.longitude), '¥5200'),
        // 与 p1 部分重叠：选中后应压在上面
        _price(
            'p3',
            LatLng(_center.latitude + 0.0003, _center.longitude + 0.0006),
            '¥4100'),
        _area('d1', LatLng(_center.latitude - d, _center.longitude), '望京 120套'),
      };
    }
    return <Marker>{
      _area('d2', LatLng(_center.latitude + d, _center.longitude - d), '国贸 85'),
      _area(
          'd3', LatLng(_center.latitude - d, _center.longitude + d), '三里屯 40'),
    };
  }

  /// 保留最近两行，能看出 selectionChanged 先于 onTap（R-SEL-3）
  void _note(String s) {
    if (mounted) {
      setState(() => _log = '${_log.split('\n').last}\n$s');
    }
  }

  Future<void> _selectApi(String? id) async {
    final int? rev = await _controller?.setSelectedMarker(id);
    _note('setSelectedMarker($id) → revision $rev');
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
            markers: _markers(),
            markerSelection: const MarkerSelectionOptions(),
            // 建议值 1000ms（E-A6）
            markerTransition: _replace
                ? const MarkerTransition.replaceWhenReady(
                    timeout: Duration(milliseconds: 1000))
                : const MarkerTransition.immediate(),
            onMapCreated: (AMapController c) => _controller = c,
            onMarkerSelectionChanged: (MarkerSelectionChange c) =>
                _note('选择 ${c.previousId} → ${c.selectedId}（${c.reason.name}，'
                    'rev ${c.revision}）'),
            onNativeMarkerError: (NativeMarkerError e) =>
                _note('错误 ${e.code.name} ${e.markerId ?? ''}'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_log, textAlign: TextAlign.center),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              _button(_priceLayer ? '切到片区层' : '切到价格层',
                  () => setState(() => _priceLayer = !_priceLayer)),
              _button(_replace ? '过渡：就绪后替换' : '过渡：立即',
                  () => setState(() => _replace = !_replace)),
              _button('选中 p2', () => _selectApi('p2')),
              _button('取消选择', () => _selectApi(null)),
            ],
          ),
        ),
      ],
    );
  }
}
