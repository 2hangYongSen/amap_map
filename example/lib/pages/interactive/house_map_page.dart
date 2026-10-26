import 'dart:async';
import 'dart:math' as math;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

const Color _purple = Color(0xFF8540FD);
const LatLng _initialTarget = LatLng(31.2304, 121.4537);

class _House {
  const _House(this.id, this.name, this.position, this.price, this.address);

  final String id;
  final String name;
  final LatLng position;
  final int price;
  final String address;

  String get priceLabel => price > 0 ? '￥$price/月起' : '价格待定';
}

// 模拟服务端房源库：固定地理范围、固定随机种子，仅生成一次。
// 查询只筛选坐标，不随视野大小、缩放级别或请求次数改变房源。
final List<_House> _houseCatalog = _createHouseCatalog();

List<_House> _createHouseCatalog() {
  final math.Random random = math.Random(20261026);
  const int columns = 15;
  const int rows = 20;
  // 静安附近约 1.8km × 1.5km 的固定区域，共 300 套模拟房源。
  const double latitudeSpan = 0.016;
  const double longitudeSpan = 0.016;
  return List<_House>.unmodifiable(
      List<_House>.generate(columns * rows, (int i) {
    final double x = (i % columns + 0.15 + random.nextDouble() * 0.7) / columns;
    final double y = (i ~/ columns + 0.15 + random.nextDouble() * 0.7) / rows;
    return _House(
      'house-${i + 1}',
      '示例公寓 ${i + 1}',
      LatLng(
        _initialTarget.latitude + (y - 0.5) * latitudeSpan,
        _initialTarget.longitude + (x - 0.5) * longitudeSpan,
      ),
      i % 29 == 0 ? 0 : 1800 + random.nextInt(65) * 100,
      '静安区 · 示例街区 ${i % 12 + 1}',
    );
  }));
}

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
  static const Duration _debounceDelay = Duration(milliseconds: 250);
  static const Duration _networkDelay = Duration(milliseconds: 700);
  final DraggableScrollableController _sheet = DraggableScrollableController();
  List<_House> _houses = <_House>[];
  Set<Marker> _markers = <Marker>{};
  AMapController? _map;
  ScrollController? _sheetScroll;
  _House? _selected;
  Size _mapSize = Size.zero;
  int _focusGeneration = 0;
  Timer? _refreshDebounce;
  int _requestGeneration = 0;
  int _requestCount = 0;
  int _completedRequest = 0;
  bool _loading = true;
  CameraPosition _camera = const CameraPosition(
    target: _initialTarget,
    zoom: 14.5,
  );
  LatLng? _focusTarget;
  CameraPosition? _queryCamera;

  double get _projectionScale => defaultTargetPlatform == TargetPlatform.android
      ? MediaQuery.of(context).devicePixelRatio
      : 1;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheetChanged);
  }

  void _onMapCreated(AMapController controller) {
    _map = controller;
    _scheduleRefresh();
  }

  void _onCameraMove(CameraPosition camera) {
    if (_sameCamera(camera, _camera)) return;
    _camera = camera;
    // 一开始移动就让旧请求失效，不等下一次请求发出后才丢弃旧结果。
    _cancelRefresh();
    if (_focusTarget == null) _focusGeneration++;
  }

  void _onCameraMoveEnd(CameraPosition camera) {
    _camera = camera;
    _focusTarget = null;
    // SDK 可能在覆盖物更新后再次通知相同视角，避免查询→重建→回调循环。
    if (_sameCamera(camera, _queryCamera)) return;
    _focusGeneration++;
    // 手势移动和点击气泡后的聚焦都查询最终视野；保留选择不再次聚焦。
    _scheduleRefresh();
  }

  void _cancelRefresh() {
    _refreshDebounce?.cancel();
    _requestGeneration++;
    _queryCamera = null;
  }

  bool _sameCamera(CameraPosition a, CameraPosition? b) =>
      b != null &&
      (a.target.latitude - b.target.latitude).abs() < 0.0000001 &&
      (a.target.longitude - b.target.longitude).abs() < 0.0000001 &&
      (a.zoom - b.zoom).abs() < 0.001 &&
      (a.bearing - b.bearing).abs() < 0.01 &&
      (a.tilt - b.tilt).abs() < 0.01;

  void _scheduleRefresh() {
    _cancelRefresh();
    _queryCamera = _camera;
    final int generation = _requestGeneration;
    if (!_loading) setState(() => _loading = true);
    _refreshDebounce = Timer(_debounceDelay, () {
      unawaited(_fetchHouses(generation));
    });
  }

  Future<void> _fetchHouses(int generation) async {
    final AMapController? map = _map;
    if (map == null || _mapSize.isEmpty) return;
    final Size size = _mapSize;
    final double scale = _projectionScale;
    try {
      // 以原生投影读取完整视野，作为模拟接口的经纬度查询范围。
      final List<LatLng> corners = await Future.wait(<Future<LatLng>>[
        map.fromScreenCoordinate(const ScreenCoordinate(x: 0, y: 0)),
        map.fromScreenCoordinate(ScreenCoordinate(
          x: (size.width * scale).round(),
          y: (size.height * scale).round(),
        )),
      ]);
      if (!mounted || generation != _requestGeneration) return;
      final int request = ++_requestCount;
      // 模拟已发出的网络请求；即使旧请求稍后返回，也不能覆盖新视野。
      await Future<void>.delayed(_networkDelay);
      if (!mounted || generation != _requestGeneration) return;
      final List<_House> houses = _queryHouses(corners.first, corners.last);
      if (_selected != null && !houses.contains(_selected)) {
        // 房源移出查询范围后收起抽屉；不额外补点，也不保留范围外的选中点。
        unawaited(_clearSelection());
      }
      setState(() {
        _houses = houses;
        _markers = houses.map(_marker).toSet();
        _completedRequest = request;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
        _showError('加载房源失败：$error');
      }
    }
  }

  List<_House> _queryHouses(LatLng northwest, LatLng southeast) =>
      _houseCatalog.where((_House house) {
        final LatLng point = house.position;
        final bool inLongitude = northwest.longitude <= southeast.longitude
            ? point.longitude >= northwest.longitude &&
                point.longitude <= southeast.longitude
            : point.longitude >= northwest.longitude ||
                point.longitude <= southeast.longitude;
        return point.latitude >= southeast.latitude &&
            point.latitude <= northwest.latitude &&
            inLongitude;
      }).toList();

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
    if (house != null) _cancelRefresh();
    setState(() {
      _selected = house;
      if (house != null) _loading = false;
    });
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
    final double pixelScale = _projectionScale;
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
      _focusTarget = target;
      await map.moveCamera(CameraUpdate.newLatLng(target), duration: 280);
    } catch (error) {
      if (mounted && generation == _focusGeneration) {
        _focusTarget = null;
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
    _cancelRefresh();
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
                    target: _initialTarget,
                    zoom: 14.5,
                  ),
                  markers: _markers,
                  markerSelection: const MarkerSelectionOptions(),
                  markerTransition: const MarkerTransition.replaceWhenReady(
                      timeout: Duration(milliseconds: 1000)),
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  touchPoiEnabled: false,
                  onMapCreated: _onMapCreated,
                  onCameraMove: _onCameraMove,
                  onCameraMoveEnd: _onCameraMoveEnd,
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
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.apartment_rounded, color: _purple),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  _loading
                                      ? '正在查询附近房源…\n保留上次 ${_houses.length} 套 · 模拟请求 700ms'
                                      : _houses.isEmpty
                                          ? '当前视野暂无房源\n模拟房源位于上海静安，缩小或移回查看'
                                          : '当前视野 ${_houses.length} 套 · 房源库共 ${_houseCatalog.length} 套\n第 $_completedRequest 次查询 · 拖动或缩放地图更新',
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.6)),
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
