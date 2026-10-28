import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';

/// 缓存 PNG 方案（对照组的最好水平）：
/// - 按“文字 + 普通/选中 + 像素比”缓存，同一价格只生成一次；
/// - 缓存的是同一个 [BitmapDescriptor] 对象，Marker 比较相等时不会重传字节；
/// - 并发请求同一个 key 时共用一个 Future，不重复生成。
class PricePngCache {
  PricePngCache({this.maxEntries = 2400});

  /// 条目上限（最近最少使用淘汰），与原生缓存有预算对等；业务里也不会无限缓存
  final int maxEntries;

  // Dart 的 Map 按插入顺序遍历：命中时移到末尾，超限时淘汰最前面的
  final Map<String, Future<BitmapDescriptor>> _cache =
      <String, Future<BitmapDescriptor>>{};

  /// 累计生成张数。生成是并发的，单张耗时相加没有意义，总耗时看调用方测的实际经过时间
  int generated = 0;

  int get size => _cache.length;

  void clear() {
    _cache.clear();
    generated = 0;
  }

  Future<BitmapDescriptor> get(String text, double dpr,
      {bool selected = false}) {
    final String key = '$text|${selected ? 1 : 0}|$dpr';
    final Future<BitmapDescriptor>? hit = _cache.remove(key);
    final Future<BitmapDescriptor> f = hit ?? _generate(text, dpr, selected);
    _cache[key] = f;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first); // 已显示的点仍持有自己的图标对象，淘汰不影响显示
    }
    return f;
  }

  Future<BitmapDescriptor> _generate(
      String text, double dpr, bool selected) async {
    final Uint8List png = await drawPricePng(text, dpr, selected: selected);
    generated++;
    return BitmapDescriptor.fromBytes(png);
  }
}

/// 价格气泡 PNG：圆角白底 + 红字 + 箭头，与原生方案的 [comparePriceStyle] 外观一致。
/// 与 integration_test/s18_support.dart 的 legacyPricePng 相同（那边在测试目录，页面引用不到）。
Future<Uint8List> drawPricePng(String text, double dpr,
    {bool selected = false}) async {
  final TextPainter tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 13 * dpr,
            color: Color(selected ? 0xFFFFFFFF : 0xFFE53935))),
    textDirection: TextDirection.ltr,
  )..layout();
  final double w = tp.width + 16 * dpr, h = tp.height + 8 * dpr;
  final double arrow = 6 * dpr;
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  final Paint fill = Paint()
    ..color = Color(selected ? 0xFFE53935 : 0xFFFFFFFF);
  c.drawRRect(RRect.fromLTRBR(0, 0, w, h, Radius.circular(6 * dpr)), fill);
  c.drawPath(
      Path()
        ..moveTo(w / 2 - 5 * dpr, h)
        ..lineTo(w / 2, h + arrow)
        ..lineTo(w / 2 + 5 * dpr, h)
        ..close(),
      fill);
  tp.paint(c, Offset(8 * dpr, 4 * dpr));
  final ui.Image img =
      await rec.endRecording().toImage(w.ceil(), (h + arrow).ceil());
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}
