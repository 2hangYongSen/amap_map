import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 原生点位图片示例（S11）：asset 九宫格气泡、bytes 来源的景点图标、
/// 固定尺寸图钉加 custom 锚点、资源解码失败时的降级展示。
class NativeMarkerImagePage extends StatefulWidget {
  const NativeMarkerImagePage({super.key});

  @override
  State<NativeMarkerImagePage> createState() => _NativeMarkerImagePageState();
}

class _NativeMarkerImagePageState extends State<NativeMarkerImagePage> {
  static const LatLng _center = LatLng(39.909187, 116.397451);
  static const double _d = 0.004;

  /// 九宫格气泡：96x72 像素、pixelRatio 2（逻辑 48x36），圆角区约 8 逻辑像素
  static const MarkerImageResource _bubble = MarkerImageResource.asset(
      id: 'nm.bubble',
      assetName: 'assets/native_marker/bubble_9.png',
      pixelRatio: 2);

  /// 自带箭头的图钉：80x100 像素（逻辑 40x50），尖端在底边中点
  static const MarkerImageResource _pin = MarkerImageResource.asset(
      id: 'nm.pin', assetName: 'assets/native_marker/pin.png', pixelRatio: 2);

  /// bytes 资源构造时计算摘要，必须缓存，不能每次 build 重新创建
  MarkerImageResource? _scenic;

  /// 内容无法解码的 bytes 资源：演示 R-RES-6 降级（默认白色圆角背景，保留文字）
  final MarkerImageResource _broken = MarkerImageResource.bytes(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      pixelRatio: 2);

  bool _repaired = false;
  final List<String> _errors = <String>[];

  @override
  void initState() {
    super.initState();
    rootBundle
        .load('assets/native_marker/scenic_icon.png')
        .then((ByteData data) {
      if (!mounted) {
        return;
      }
      setState(() => _scenic =
          MarkerImageResource.bytes(data.buffer.asUint8List(), pixelRatio: 2));
    });
  }

  /// 九宫格气泡：宽度随文字变化，四角不拉伸；箭头单独绘制，颜色必须显式指定
  Marker _bubbleMarker(String id, LatLng at, String text, String imageId,
      {Color textColor = const Color(0xFFFFFFFF)}) {
    return Marker(
      markerId: id,
      position: at,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: NativeMarkerStyle(
          background: NativeMarkerImageBackground(
              imageId: imageId, capInsets: const EdgeInsets.all(10)),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          textColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          maxWidth: 160,
          arrow: const NativeMarkerArrow(
              width: 10, height: 6, color: Color(0xFFFF7043)),
          shadow: const NativeMarkerShadow(
              color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
        ),
      ),
    );
  }

  /// 景点：白色胶囊背景 + bytes 图标在文字前
  Marker _scenicMarker(String id, LatLng at, String text, String iconId) {
    return Marker(
      markerId: id,
      position: at,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(
            text: text, iconId: iconId, iconSize: const Size(18, 18)),
        style: const NativeMarkerStyle(
          background: NativeMarkerShapeBackground.roundedRect(
              fillColor: Color(0xFFFFFFFF), cornerRadius: 14),
          fontSize: 12,
          textColor: Color(0xFF2E7D32),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          shadow: NativeMarkerShadow(
              color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
        ),
      ),
    );
  }

  /// 固定尺寸图钉：图片自带箭头，不配置 arrow，用 custom 锚点 (0.5, 1) 指向尖端
  Marker _pinMarker(String id, LatLng at) {
    return Marker(
      markerId: id,
      position: at,
      nativePresentation: NativeMarkerPresentation(
        content: const NativeMarkerContent(text: 'P'),
        anchorType: NativeMarkerAnchorType.custom,
        anchor: const Offset(0.5, 1),
        style: NativeMarkerStyle(
          background: NativeMarkerImageBackground(
              imageId: _pin.id, size: const Size(40, 50)),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          textColor: const Color(0xFF1E88E5),
          padding: const EdgeInsets.only(bottom: 10), // 文字落在圆心
        ),
      ),
    );
  }

  Set<Marker> _markers() {
    final MarkerImageResource? scenic = _scenic;
    return <Marker>{
      _bubbleMarker('b1', _center, '¥3000', _bubble.id),
      _bubbleMarker('b2', LatLng(_center.latitude + _d, _center.longitude),
          '望京 SOHO 新房 120 套', _bubble.id),
      if (scenic != null) ...<Marker>[
        _scenicMarker('s1', LatLng(_center.latitude, _center.longitude - _d),
            '故宫', scenic.id),
        _scenicMarker(
            's2',
            LatLng(_center.latitude - _d, _center.longitude - _d),
            '景山公园',
            scenic.id),
      ],
      _pinMarker('pin', LatLng(_center.latitude - _d, _center.longitude)),
      // 失败降级：修复前引用损坏资源，修复后改为引用正常气泡
      _bubbleMarker('f1', LatLng(_center.latitude, _center.longitude + _d),
          _repaired ? '已修复' : '资源损坏', _repaired ? _bubble.id : _broken.id,
          // 默认降级背景是白色：这个点用深色文字，降级后文字仍可见
          textColor: const Color(0xFF5D4037)),
    };
  }

  void _onError(NativeMarkerError e) {
    setState(() {
      _errors.insert(0, '${e.code.name} ${e.markerId ?? e.imageId ?? ''}');
      if (_errors.length > 3) {
        _errors.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MarkerImageResource? scenic = _scenic;
    return Column(
      children: <Widget>[
        Expanded(
          child: AMapWidget(
            initialCameraPosition:
                const CameraPosition(target: _center, zoom: 15),
            markers: _markers(),
            markerImages: <MarkerImageResource>{
              _bubble,
              _pin,
              if (scenic != null) scenic,
              if (!_repaired) _broken,
            },
            onNativeMarkerError: _onError,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              TextButton(
                onPressed: () => setState(() => _repaired = !_repaired),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue),
                child: Text(_repaired ? '恢复损坏' : '修复资源'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_errors.isEmpty ? '暂无原生错误' : _errors.join('\n'),
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
