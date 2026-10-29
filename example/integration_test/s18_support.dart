// S18 集成测试公共部分：等待、主机命令、结果落盘、价格点、旧路径 PNG、截图像素统计。
// 结果写到 App 临时目录 s18/ 下（iOS 由 devicectl 取回，Android 由 logcat 中的 S18R 行汇总）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

const LatLng s18Center = LatLng(39.909187, 116.397451);

/// 原生绑定与绘制都是异步的：按真实时间等待，期间持续刷帧
Future<void> settle(WidgetTester tester, int ms) async {
  final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// 轮询直到条件成立或超时；返回是否成立
Future<bool> waitFor(WidgetTester tester, bool Function() ok,
    {int timeoutMs = 10000}) async {
  final DateTime end = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (!ok() && DateTime.now().isBefore(end)) {
    await settle(tester, 50);
  }
  return ok();
}

/// 结果与日志：每行打印到控制台（Android logcat 前缀 S18R），同时追加到 App tmp/s18/<name>
class S18Out {
  S18Out(this.name) {
    final Directory dir = Directory('${Directory.systemTemp.path}/s18')
      ..createSync(recursive: true);
    file = File('${dir.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }

  final String name;
  late final File file;
  int _seq = 0;

  /// 一条 JSON 记录
  void record(Map<String, Object?> m) => line(jsonEncode(m));

  /// 给主机的命令（Android 主机脚本读 logcat 执行：tap / meminfo / gfxreset / gfxdump / done）
  void command(String op, [String args = '']) {
    // ignore: avoid_print
    print('S18CMD ${++_seq} $op $args');
  }

  /// 保存 PNG：写 tmp/s18/<name>.png（iOS 取回）；Android 按 800 字符分块打印
  /// （logcat 单行上限约 1000 字符），由主机拼回
  void image(String name, Uint8List png) {
    File('${file.parent.path}/$name.png').writeAsBytesSync(png, flush: true);
    if (!Platform.isAndroid) return;
    const int k = 800;
    final String b64 = base64Encode(png);
    final int n = (b64.length / k).ceil();
    for (int i = 0; i < n; i++) {
      // ignore: avoid_print
      print('S18IMG $name $i/$n '
          '${b64.substring(i * k, (i * k + k).clamp(0, b64.length))}');
      // logcat 有速率限制（chatty），分块过快会丢；每 20 块停 30ms
      if (i % 20 == 19) sleep(const Duration(milliseconds: 30));
    }
  }

  void line(String s) {
    // ignore: avoid_print
    print('S18R $name $s');
    file.writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
  }
}

/// 拦截发往原生地图通道（amap_map_<id>）的方法调用，可改写参数后再转发。
/// 测试绑定的 defaultBinaryMessenger 是 TestDefaultBinaryMessenger，allMessagesHandler 覆盖全部发送。
class S18Channel {
  static const StandardMethodCodec _codec = StandardMethodCodec();

  /// 改写函数：返回新参数；返回 null 表示原样转发
  static Object? Function(String method, Object? args)? rewrite;

  /// 每个方法的调用次数（便于断言）
  static final Map<String, int> calls = <String, int>{};

  /// 最近一个地图的 id（从通道名 amap_map_<id> 得到）
  static int? lastMapId;

  static void install() {
    final TestDefaultBinaryMessenger m =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.allMessagesHandler =
        (String channel, MessageHandler? mock, ByteData? message) {
      if (channel == 'flutter/platform_views' && message != null) {
        return m.delegate.send(channel, _rewriteCreate(message));
      }
      if (!channel.startsWith('amap_map_') || message == null) {
        return m.delegate.send(channel, message);
      }
      lastMapId = int.tryParse(channel.substring('amap_map_'.length));
      final MethodCall call = _codec.decodeMethodCall(message);
      calls[call.method] = (calls[call.method] ?? 0) + 1;
      final Object? next = rewrite?.call(call.method, call.arguments);
      return m.delegate.send(
          channel,
          next == null
              ? message
              : _codec.encodeMethodCall(MethodCall(call.method, next)));
    };
  }

  /// 平台视图 create 的 params 是 StandardMessageCodec 编码的创建参数：解码后交给改写函数
  static ByteData _rewriteCreate(ByteData message) {
    final MethodCall call = _codec.decodeMethodCall(message);
    final Object? args = call.arguments;
    if (call.method != 'create' || rewrite == null || args is! Map) {
      return message;
    }
    final Object? raw = args['params'];
    if (raw is! Uint8List) return message;
    const StandardMessageCodec mc = StandardMessageCodec();
    final Object? params = mc.decodeMessage(ByteData.sublistView(raw));
    final Object? next = rewrite!('create', params);
    if (next == null) return message;
    final ByteData enc = mc.encodeMessage(next)!;
    final Map<Object?, Object?> out = Map<Object?, Object?>.of(args)
      ..['params'] =
          enc.buffer.asUint8List(enc.offsetInBytes, enc.lengthInBytes);
    return _codec.encodeMethodCall(MethodCall('create', out));
  }

  /// 直接调用最近一个地图的方法（例如 map#takeSnapshot），不经过页面控制器
  static Future<T?> invoke<T>(String method, [Object? args]) =>
      MethodChannel('amap_map_$lastMapId').invokeMethod<T>(method, args);

  static void uninstall() {
    rewrite = null;
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.allMessagesHandler = null;
  }
}

/// 价格气泡普通态 / 选中态（与选择示例页相同）
NativeMarkerStyle priceStyle({bool selected = false}) => NativeMarkerStyle(
      background: NativeMarkerShapeBackground.roundedRect(
          fillColor: Color(selected ? 0xFFE53935 : 0xFFFFFFFF),
          cornerRadius: 6),
      fontSize: 13,
      textColor: Color(selected ? 0xFFFFFFFF : 0xFFE53935),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      arrow: const NativeMarkerArrow(width: 10, height: 6),
      shadow: const NativeMarkerShadow(
          color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
    );

/// 第 i 个点的位置：20 列网格，间距约 220m
LatLng gridPos(int i, {double step = 0.002}) => LatLng(
    s18Center.latitude + (i ~/ 20 - 4.5) * step,
    s18Center.longitude + (i % 20 - 9.5) * step);

/// 新路径价格点
Marker nativePrice(String id, LatLng at, String text,
        {bool selectable = false, void Function(String)? onTap}) =>
    Marker(
      markerId: id,
      position: at,
      selectable: selectable,
      zIndex: 1,
      selectedZIndex: selectable ? 99 : null,
      infoWindowEnable: false,
      onTap: onTap,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: text),
        anchorType: NativeMarkerAnchorType.arrowTip,
        style: priceStyle(),
        selectedStyle: selectable ? priceStyle(selected: true) : null,
      ),
    );

/// 旧路径：Dart 画价格气泡 PNG（文字 + 圆角底 + 箭头），与业务现状相同；按设备像素比绘制
Future<BitmapDescriptor> legacyPricePng(String text, double dpr,
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
  final Paint fill = Paint()..color = Color(selected ? 0xFFE53935 : 0xFFFFFFFF);
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
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

/// 解码 PNG 为 RGBA，便于取像素
class Rgba {
  Rgba(this.width, this.height, this.bytes);
  final int width, height;
  final ByteData bytes;

  static Future<Rgba> decode(Uint8List png) async {
    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.Image img = (await codec.getNextFrame()).image;
    final ByteData data =
        (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final Rgba r = Rgba(img.width, img.height, data);
    img.dispose();
    return r;
  }

  /// (x, y) 处的 0xAARRGGBB
  int at(int x, int y) {
    final int i = (y * width + x) * 4;
    return bytes.getUint8(i + 3) << 24 |
        bytes.getUint8(i) << 16 |
        bytes.getUint8(i + 1) << 8 |
        bytes.getUint8(i + 2);
  }

  /// 矩形区域内与 [argb] 的 RGB 每通道差都 ≤ [tol] 的像素数
  int count(Rect r, int argb, {int tol = 24}) {
    int n = 0;
    for (int y = r.top.floor().clamp(0, height - 1);
        y < r.bottom.ceil().clamp(0, height);
        y++) {
      for (int x = r.left.floor().clamp(0, width - 1);
          x < r.right.ceil().clamp(0, width);
          x++) {
        final int p = at(x, y);
        if (((p >> 16 & 0xFF) - (argb >> 16 & 0xFF)).abs() <= tol &&
            ((p >> 8 & 0xFF) - (argb >> 8 & 0xFF)).abs() <= tol &&
            ((p & 0xFF) - (argb & 0xFF)).abs() <= tol) {
          n++;
        }
      }
    }
    return n;
  }
}

/// 分位数（线性插值），样本为空返回 NaN
double pct(List<double> xs, double p) {
  if (xs.isEmpty) return double.nan;
  final List<double> s = List<double>.of(xs)..sort();
  final double k = (s.length - 1) * p;
  final int lo = k.floor(), hi = k.ceil();
  return s[lo] + (s[hi] - s[lo]) * (k - lo);
}
