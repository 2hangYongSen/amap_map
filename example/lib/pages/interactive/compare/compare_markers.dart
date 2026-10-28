import 'dart:math';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 对照页的地图中心
const LatLng compareCenter = LatLng(39.909187, 116.397451);

/// 两种方案
enum CompareScheme {
  native('原生点位'),
  png('缓存 PNG');

  const CompareScheme(this.label);
  final String label;
}

/// 原生价格气泡样式，与 [drawPricePng] 外观一致（都不带阴影，保证两边绘制量对等）
NativeMarkerStyle comparePriceStyle({bool selected = false}) =>
    NativeMarkerStyle(
      background: NativeMarkerShapeBackground.roundedRect(
          fillColor: Color(selected ? 0xFFE53935 : 0xFFFFFFFF),
          cornerRadius: 6),
      fontSize: 13,
      textColor: Color(selected ? 0xFFFFFFFF : 0xFFE53935),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      arrow: const NativeMarkerArrow(width: 10, height: 6),
    );

/// 分位数（线性插值），样本为空返回 NaN
double percentile(List<double> xs, double p) {
  if (xs.isEmpty) return double.nan;
  final List<double> s = List<double>.of(xs)..sort();
  final double k = (s.length - 1) * p;
  final int lo = k.floor(), hi = k.ceil();
  return s[lo] + (s[hi] - s[lo]) * (k - lo);
}

/// 一批点位的数据：id、位置、价格文字。两种方案用同一批数据。
class PriceBatch {
  PriceBatch(this.round, this.ids, this.positions, this.texts);

  /// 第 [round] 批、[count] 个点：价格各不相同（冷场景），位置在中心周围随机分布。
  /// 同一 round 生成的数据固定，方便两种方案对比同一批数据。
  factory PriceBatch.fresh(int round, int count) {
    final Random r = Random(round * 7919 + count);
    final List<String> ids = <String>[];
    final List<LatLng> pos = <LatLng>[];
    final List<String> texts = <String>[];
    for (int i = 0; i < count; i++) {
      ids.add('r${round}_$i');
      // 约 ±3.3km 范围（纬度 0.03°），zoom 13 下大致铺满一屏
      pos.add(LatLng(compareCenter.latitude + (r.nextDouble() - 0.5) * 0.06,
          compareCenter.longitude + (r.nextDouble() - 0.5) * 0.06));
      // 价格不重复：round 和序号共同决定，保证跨批次也不重复（缓存全部未命中）
      texts.add('¥${(round * 1000 + i) * 3 + 1000}');
    }
    return PriceBatch(round, ids, pos, texts);
  }

  final int round;
  final List<String> ids;
  final List<LatLng> positions;
  final List<String> texts;

  int get length => ids.length;
}

/// 原生方案的一个价格点
Marker nativeCompareMarker(String id, LatLng at, String text,
        {void Function(String)? onTap}) =>
    Marker(
      markerId: id,
      position: at,
      selectable: true,
      zIndex: 1,
      selectedZIndex: 99,
      infoWindowEnable: false,
      onTap: onTap,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: comparePriceStyle(),
        selectedStyle: comparePriceStyle(selected: true),
      ),
    );

/// PNG 方案的一个价格点；锚点在箭头尖端（底边中点）
Marker pngCompareMarker(String id, LatLng at, BitmapDescriptor icon,
        {bool selected = false, void Function(String)? onTap}) =>
    Marker(
      markerId: id,
      position: at,
      icon: icon,
      anchor: const Offset(0.5, 1),
      zIndex: selected ? 99 : 1,
      infoWindowEnable: false,
      onTap: onTap,
    );
