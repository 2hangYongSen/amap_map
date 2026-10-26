import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

const Color _purple = Color(0xFF8540FD);

class _House {
  const _House(this.id, this.name, this.position, this.price, this.address);

  final String id;
  final String name;
  final LatLng position;
  final int price;
  final String address;

  String get priceLabel => price > 0 ? '￥$price/月起' : '价格待定';
}

// 固定演示数据，不依赖房源接口和定位权限。
const List<_House> _houses = <_House>[
  _House('house-1', '静安紫庭公寓', LatLng(31.2304, 121.4537), 3280, '静安区 · 延安中路附近'),
  _House(
      'house-2', '南京西路青年公寓', LatLng(31.2345, 121.4596), 4200, '静安区 · 南京西路附近'),
  _House('house-3', '愚园路阳光公寓', LatLng(31.2268, 121.4460), 2980, '静安区 · 愚园路附近'),
  _House('house-4', '常德路轻居', LatLng(31.2376, 121.4498), 3680, '静安区 · 常德路附近'),
  _House('house-5', '陕西南路悦居', LatLng(31.2242, 121.4608), 0, '静安区 · 陕西南路附近'),
];

/// 小程序地图找房的简化用例：原生价格气泡、可视区聚焦、三档抽屉。
class HouseMapPage extends StatefulWidget {
  const HouseMapPage({super.key});

  @override
  State<HouseMapPage> createState() => _HouseMapPageState();
}

class _HouseMapPageState extends State<HouseMapPage> {
  static const double _half = 0.5;
  static const double _full = 0.94;
  static const Duration _duration = Duration(milliseconds: 280);
  final DraggableScrollableController _sheet = DraggableScrollableController();
  late final Set<Marker> _markers = _houses.map(_marker).toSet();
  AMapController? _map;
  ScrollController? _sheetScroll;
  _House? _selected;
  Size _mapSize = Size.zero;
  int _focusGeneration = 0;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheetChanged);
  }

  Marker _marker(_House house) {
    const NativeMarkerStyle normal = NativeMarkerStyle(
      background: NativeMarkerShapeBackground.roundedRect(
        fillColor: Colors.white,
        cornerRadius: 16,
      ),
      fontSize: 13,
      textColor: Color(0xFF1A1A1A),
      padding: EdgeInsets.all(8),
      arrow: NativeMarkerArrow(width: 10, height: 6),
      shadow: NativeMarkerShadow(
        color: Color(0x24000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    );
    return Marker(
      markerId: house.id,
      position: house.position,
      selectable: true,
      selectedZIndex: 99,
      infoWindowEnable: false,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: house.priceLabel),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: normal,
        selectedStyle: normal.copyWith(
          background: const NativeMarkerShapeBackground.roundedRect(
            fillColor: _purple,
            cornerRadius: 16,
          ),
          textColor: Colors.white,
        ),
      ),
    );
  }

  void _onSelectionChanged(MarkerSelectionChange change) {
    _House? house;
    for (final _House candidate in _houses) {
      if (candidate.id == change.selectedId) house = candidate;
    }
    _showHouse(house);
  }

  void _showHouse(_House? house) {
    if (!mounted || _selected == house) return;
    final int generation = ++_focusGeneration;
    setState(() => _selected = house);
    // 等新房源内容完成布局后再展开；快速切换时只处理最后一次选择。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _focusGeneration) return;
      if (house != null && (_sheetScroll?.hasClients ?? false)) {
        _sheetScroll!.jumpTo(0);
      }
      _animateSheet(house == null ? 0 : _half);
      if (house != null) unawaited(_focusHouse(house, generation));
    });
  }

  void _animateSheet(double size) {
    if (_sheet.isAttached) {
      unawaited(
          _sheet.animateTo(size, duration: _duration, curve: Curves.easeOut));
    }
  }

  Future<void> _focusHouse(_House house, int generation) async {
    final AMapController? map = _map;
    if (map == null || _mapSize.isEmpty) return;
    // Android 投影返回物理像素，iOS 返回 UIKit points。
    final double pixelScale = defaultTargetPlatform == TargetPlatform.android
        ? MediaQuery.of(context).devicePixelRatio
        : 1;
    final double bottomInset = _mapSize.height * _half + 20;
    try {
      final ScreenCoordinate point =
          await map.toScreenCoordinate(house.position);
      if (!mounted || generation != _focusGeneration) return;
      // 相机中心向南偏移，让箭头尖端位于未被抽屉遮挡区域的中央。
      final LatLng target = await map.fromScreenCoordinate(ScreenCoordinate(
        x: point.x,
        y: point.y + (bottomInset * pixelScale / 2).round(),
      ));
      if (!mounted || generation != _focusGeneration) return;
      await map.moveCamera(CameraUpdate.newLatLng(target), duration: 280);
    } catch (error) {
      if (mounted && generation == _focusGeneration) {
        _showError('地图聚焦失败：$error');
      }
    }
  }

  void _onSheetChanged() {
    if (_sheet.isAttached && _sheet.size <= 0.001 && _selected != null) {
      unawaited(_clearSelection());
    }
  }

  Future<void> _clearSelection() async {
    _showHouse(null);
    try {
      await _map?.setSelectedMarker(null);
    } catch (error) {
      if (mounted) _showError('取消选择失败：$error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _focusGeneration++;
    _sheet.removeListener(_onSheetChanged);
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _mapSize = constraints.biggest;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: AMapWidget(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(31.2304, 121.4537),
                    zoom: 14.5,
                  ),
                  markers: _markers,
                  markerSelection: const MarkerSelectionOptions(),
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  touchPoiEnabled: false,
                  onMapCreated: (AMapController controller) =>
                      _map = controller,
                  onMarkerSelectionChanged: _onSelectionChanged,
                  onNativeMarkerError: (NativeMarkerError error) =>
                      _showError('气泡显示失败：${error.message}'),
                ),
              ),
              if (_selected == null)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Material(
                      elevation: 2,
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.apartment_rounded, color: _purple),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text('上海 · 静安区\n5 处示例公寓，点击价格气泡查看房源',
                                  style: TextStyle(fontSize: 13, height: 1.6)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: 0,
                minChildSize: 0,
                maxChildSize: _full,
                snap: true,
                snapSizes: const <double>[0, _half, _full],
                snapAnimationDuration: _duration,
                shouldCloseOnMinExtent: false,
                builder: (BuildContext context, ScrollController scroll) {
                  _sheetScroll = scroll;
                  return Material(
                    key: const ValueKey<String>('house-sheet'),
                    color: Colors.white,
                    elevation: 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: <Widget>[
                        if (_selected != null) ...<Widget>[
                          Center(
                            child: Container(
                              key: const ValueKey<String>('house-sheet-handle'),
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9D9E0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('公寓房源',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                              ),
                              TextButton(
                                onPressed: () => _animateSheet(
                                    _sheet.size > 0.7 ? _half : _full),
                                child: const Text('展开 / 半屏',
                                    style: TextStyle(color: _purple)),
                              ),
                              IconButton(
                                tooltip: '关闭房源',
                                onPressed: _clearSelection,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          _ApartmentHeader(house: _selected!),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text('可租房型 · 示例数据',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          for (int i = 0; i < 8; i++)
                            _RoomTile(house: _selected!, index: i),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
}

class _ApartmentHeader extends StatelessWidget {
  const _ApartmentHeader({required this.house});

  final _House house;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 76,
            height: 92,
            decoration: BoxDecoration(
              color: const Color(0xFFF2EBFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.apartment, size: 40, color: _purple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(house.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(house.priceLabel,
                    style: const TextStyle(
                        color: _purple,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(house.address,
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 12)),
                const SizedBox(height: 8),
                const Text('近地铁 · 独立卫浴 · 可月付',
                    style: TextStyle(color: _purple, fontSize: 12)),
              ],
            ),
          ),
        ],
      );
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.house, required this.index});

  final _House house;
  final int index;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${index.isEven ? '舒适一居室' : '阳光开间'} · ${index + 1} 号房型',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('${25 + index * 3} m² · 精装修 · 随时入住',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            const SizedBox(height: 8),
            Text(house.price > 0 ? '￥${house.price + index * 180}/月' : '价格待定',
                style: const TextStyle(color: _purple)),
          ],
        ),
      );
}
