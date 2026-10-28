import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:x_amap_base/x_amap_base.dart';

import 'compare_markers.dart';
import 'flutter_load.dart';
import 'price_png_cache.dart';

/// 一次“推送新价格”的测量结果
class PushResult {
  PushResult({
    required this.scheme,
    required this.count,
    required this.t0,
    required this.buildMs,
  });

  final CompareScheme scheme;
  final int count;

  /// 数据到达时刻（[MarkerDiagnosticsClock]）
  final double t0;

  /// t0 → 点位集合构造完成（PNG 方案含 PNG 生成）
  final double buildMs;

  /// 以下来自原生回执；未收到前为空
  double? t0t1, t2t4, t0t4;
  int draws = 0, bytes = 0;

  /// PNG 方案本次新生成的张数（耗时就是 [buildMs]）
  int pngGenerated = 0;

  /// 推送后 [CompareController.jankWindow] 内的 Flutter 帧统计；统计完成前为空
  int? frames, jankBuild, jankRaster, dropped;
  double? worstFrameMs;
  FlutterLoad load = FlutterLoad.off;

  /// 是否在镜头平移过程中推送
  bool panning = false;

  bool get done => t2t4 != null;
}

/// 对照页的状态与测量逻辑，页面和集成测试共用
class CompareController extends ChangeNotifier {
  CompareController({this.dpr = 3});

  /// 设备像素比，PNG 按它绘制（页面从 MediaQuery 更新）
  double dpr;

  CompareScheme scheme = CompareScheme.native;
  int count = 200;
  FlutterLoad load = FlutterLoad.off;

  /// 推送后统计 Flutter 掉帧的时长
  static const Duration jankWindow = Duration(seconds: 3);

  /// 帧预算按屏幕刷新率（120Hz 设备为 8.3ms）
  final JankMeter _jank = JankMeter(
      budgetMs: 1000 /
          WidgetsBinding.instance.platformDispatcher.views.first.display
              .refreshRate);
  Set<Marker> markers = <Marker>{};
  final PricePngCache pngCache = PricePngCache();
  final List<PushResult> results = <PushResult>[];

  AMapController? map;
  MarkerClockCalibration? _cal;
  int _round = 0;
  bool _busy = false;

  bool _panActive = false;

  /// 推送统计或平移进行中，页面按钮禁用
  bool get busy => _busy || _panActive;
  PushResult? get last => results.isEmpty ? null : results.last;

  void attach(AMapController c) {
    map = c;
    notifyListeners();
  }

  /// 第一次推送前校准时钟（地图刚创建时诊断握手可能未完成）；失败时不给 t0→t4 估算
  Future<void> _calibrate() async {
    if (_cal != null || map == null) return;
    try {
      _cal = await map!.calibrateNativeClock();
    } catch (_) {}
  }

  /// 切换方案：清空点位与两边缓存，下一次推送从冷状态开始
  Future<void> setScheme(CompareScheme s) async {
    if (s == scheme || busy) return;
    scheme = s;
    await reset();
  }

  void setCount(int n) {
    if (n == count || busy) return;
    count = n;
    notifyListeners();
  }

  /// 清空点位、PNG 缓存和原生合成位图缓存
  Future<void> reset() async {
    markers = <Marker>{};
    pngCache.clear();
    _batch = null;
    _selectedId = null;
    notifyListeners();
    try {
      await map?.clearNativeMarkerCaches();
    } catch (_) {} // 握手未完成时报错，此时原生缓存本来就是空的
  }

  /// 叠加在测量点位之外的点（iOS 集成测试的命令点位），不参与测量、不受 reset 影响
  Set<Marker> extra = <Marker>{};

  void setExtra(Set<Marker> m) {
    extra = m;
    notifyListeners();
  }

  void setLoad(FlutterLoad l) {
    if (l == load) return;
    load = l;
    notifyListeners();
  }

  /// 推送一批全新价格（缓存全部未命中），记录 t0；
  /// 返回的 Future 在帧统计窗口结束、最后一批帧耗时上报后完成。
  Future<PushResult> push({bool panning = false}) async {
    _busy = true;
    notifyListeners();
    await _calibrate();
    final PriceBatch b = PriceBatch.fresh(++_round, count);
    final int gen0 = pngCache.generated;
    _jank.start(jankWindow);
    final double t0 = MarkerDiagnosticsClock.nowMs();
    final Set<Marker> next = await buildMarkers(b);
    final PushResult r = PushResult(
        scheme: scheme,
        count: b.length,
        t0: t0,
        buildMs: MarkerDiagnosticsClock.nowMs() - t0)
      ..pngGenerated = pngCache.generated - gen0
      ..load = load
      ..panning = panning;
    results.add(r);
    markers = next;
    notifyListeners();
    if (scheme == CompareScheme.png) {
      // 对应原生的选中态预热（P2）：点位发出后再生成，不推迟首次显示，但计入帧统计窗口
      for (final String t in b.texts) {
        pngCache.get(t, dpr, selected: true);
      }
    }
    // 窗口从 PNG 生成之前开始，所以 PNG 生成造成的卡顿也计入
    await Future<void>.delayed(jankWindow + const Duration(milliseconds: 1500));
    // 原生应用可能比统计窗口还长：再等回执，最多 15s
    for (int i = 0; i < 150 && !r.done && !_disposed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_disposed) return r;
    _jank.stop();
    r
      ..frames = _jank.frames
      ..jankBuild = _jank.jankBuild
      ..jankRaster = _jank.jankRaster
      ..dropped = _jank.dropped
      ..worstFrameMs = _jank.worstMs;
    _busy = false;
    notifyListeners();
    return r;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _jank.stop();
    super.dispose();
  }

  /// 按当前方案把一批数据转成点位，并记下当前批次（点击时要用）
  Future<Set<Marker>> buildMarkers(PriceBatch b) async {
    _batch = b;
    _selectedId = null;
    if (scheme == CompareScheme.native) {
      return <Marker>{
        for (int i = 0; i < b.length; i++)
          nativeCompareMarker(b.ids[i], b.positions[i], b.texts[i],
              onTap: _onNativeTap),
      };
    }
    _icons = await Future.wait(<Future<BitmapDescriptor>>[
      for (final String t in b.texts) pngCache.get(t, dpr),
    ]);
    return _pngMarkers();
  }

  /// PNG 方案：选中点用选中态图标并置顶，其余用普通图标（都是缓存里的同一个对象，未变化的点不重传）
  Set<Marker> _pngMarkers() {
    final PriceBatch b = _batch!;
    return <Marker>{
      for (int i = 0; i < b.length; i++)
        b.ids[i] == _selectedId
            ? pngCompareMarker(b.ids[i], b.positions[i], _selectedIcon!,
                selected: true, onTap: onPngTap)
            : pngCompareMarker(b.ids[i], b.positions[i], _icons[i],
                onTap: onPngTap),
    };
  }

  // ---- 平移中推送 ----

  /// 镜头沿正方形轨迹连续平移（每段 400ms 动画首尾相接），在平移开始 [pushAfter] 后推送一批新价格，
  /// 统计窗口覆盖整个平移过程。结束后镜头回到中心。
  Future<PushResult?> panAndPush(
      {Duration duration = const Duration(seconds: 4),
      Duration pushAfter = const Duration(milliseconds: 800)}) async {
    final AMapController? c = map;
    if (c == null || busy) return null;
    _panActive = true;
    notifyListeners();
    bool panning = true;
    final Future<void> pan = () async {
      const List<Offset> steps = <Offset>[
        Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)
      ];
      for (int i = 0; panning; i++) {
        final Offset d = steps[i % 4] * 0.01; // 约 1km
        final LatLng t = LatLng(compareCenter.latitude + d.dy,
            compareCenter.longitude + d.dx);
        await c.moveCamera(CameraUpdate.newLatLng(t), duration: 400);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }();
    await Future<void>.delayed(pushAfter);
    final Future<PushResult> pushed = push(panning: true);
    await Future<void>.delayed(duration - pushAfter);
    panning = false;
    await pan;
    await c.moveCamera(CameraUpdate.newLatLng(compareCenter), animated: false);
    final PushResult r = await pushed;
    _panActive = false;
    if (!_disposed) notifyListeners();
    return r;
  }

  // ---- 点击选中 ----
  PriceBatch? _batch;
  List<BitmapDescriptor> _icons = <BitmapDescriptor>[];
  String? _selectedId;
  BitmapDescriptor? _selectedIcon;

  /// 点击计时（c1→c2，原生同一时钟）
  final List<MarkerTapReport> taps = <MarkerTapReport>[];

  /// Dart 收到的点击（按顺序），集成测试用来确认点中了哪个点
  final List<String> dartTaps = <String>[];

  /// 原生方案：选中由原生完成，Dart 只记录点击
  void _onNativeTap(String id) => dartTaps.add(id);

  /// PNG 方案的最好做法：从缓存取选中态图标（首次点击某价格时生成），只改这一个点和上一个选中点。
  /// 再次点击同一点取消选中，与原生 deselectOnRetap 默认行为一致。
  Future<void> onPngTap(String id) async {
    dartTaps.add(id);
    final PriceBatch? b = _batch;
    if (b == null) return;
    final int i = b.ids.indexOf(id);
    if (i < 0) return;
    if (_selectedId == id) {
      _selectedId = null;
    } else {
      _selectedIcon = await pngCache.get(b.texts[i], dpr, selected: true);
      if (_batch != b) return; // 等待期间换了批次
      _selectedId = id;
    }
    markers = _pngMarkers();
    notifyListeners();
  }

  void onTapApplied(MarkerTapReport r) {
    taps.add(r);
    notifyListeners();
  }

  /// `onMarkerUpdateApplied`：把回执归到 t0 之后的那次推送。
  /// 同一批拆成多次请求时：计时取最后一条，绘制次数和字节数累加。
  void onUpdateApplied(MarkerUpdateReport rep) {
    final PushResult? r = last;
    final double? t1 = rep.dartT1Ms;
    // 只归集推送统计期间的回执；之后 PNG 方案点击重发图标的回执不算进推送
    if (!_busy || r == null || t1 == null || t1 < r.t0) return;
    r
      ..t0t1 = t1 - r.t0
      ..t2t4 = rep.t2ToT4Ms
      ..t0t4 = _cal?.arrivalToAppliedMs(
          dartT0Ms: r.t0, nativeT4Ms: rep.nativeT4Ms)
      ..draws += rep.drawCount
      ..bytes += rep.bytesReceived;
    notifyListeners();
  }
}
