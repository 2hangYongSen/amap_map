import 'dart:async';

import 'package:amap_map/src/core/amap_flutter_platform.dart';
import 'package:amap_map/src/core/method_channel_amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 只替换平台视图，其余走真实 MethodChannel（由 mock handler 应答）。
class ChannelPlatform extends MethodChannelAMapFlutterMap
    with MockPlatformInterfaceMixin {
  int nextId = 0;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers,
    void Function(int) onPlatformViewCreated,
  ) =>
      _PlatformView(onCreated: () => onPlatformViewCreated(nextId++));
}

/// 每个 State 只回调一次创建，模拟平台视图生命周期
class _PlatformView extends StatefulWidget {
  const _PlatformView({required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<_PlatformView> createState() => _PlatformViewState();
}

class _PlatformViewState extends State<_PlatformView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCreated());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// 单张地图通道的 mock 原生端
class FakeNative {
  FakeNative(this.tester, this.mapId);

  final WidgetTester tester;
  final int mapId;
  final List<MethodCall> calls = <MethodCall>[];

  /// 按方法名挂起应答；未挂起的方法立即按默认值返回
  final Map<String, Completer<Object?>> held = <String, Completer<Object?>>{};

  String get channelName => 'amap_map_$mapId';

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channelName), (MethodCall call) async {
      calls.add(call);
      final Completer<Object?>? hold = held.remove(call.method);
      if (hold != null) {
        return hold.future;
      }
      return defaultReply(call);
    });
  }

  /// 让下一次 [method] 调用挂起，返回用于放行的 Completer
  Completer<Object?> hold(String method) =>
      held[method] = Completer<Object?>();

  static Object? defaultReply(MethodCall call) {
    switch (call.method) {
      case 'markers#attach':
        return attachReply();
      case 'markers#update':
      case 'markers#resync':
        final Object? args = call.arguments;
        return <String, Object?>{
          'syncId': args is Map ? args['syncId'] : null,
          'accepted': true,
          'rejectedMarkerIds': <String>[],
        };
      case 'markers#setSelected':
        return <String, Object?>{'revision': 1};
    }
    return null;
  }

  static Map<String, Object?> attachReply() => <String, Object?>{
        'protocolVersion': 2,
        'syncId': 0,
        'rejectedMarkerIds': <String>[],
        'lastEventSeq': 0,
      };

  /// 原生 → Dart 事件
  Future<void> emit(String method, Map<String, Object?> args) async {
    final ByteData data =
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage(channelName, data, (_) {});
  }

  /// 点位相关调用（排除折线、多边形等原有行为）
  List<String> markerMethods() => calls
      .map((MethodCall c) => c.method)
      .where((String m) =>
          m.startsWith('markers#') || m == 'map#waitForMap' || m == 'map#update')
      .toList();

  Map<Object?, Object?> lastArgs(String method) => calls
      .lastWhere((MethodCall c) => c.method == method)
      .arguments as Map<Object?, Object?>;
}

/// 可从测试里替换子 Widget 并触发重建的宿主
class Host extends StatefulWidget {
  const Host({super.key, required this.builder});

  final Widget Function() builder;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  late Widget Function() _builder = widget.builder;

  void rebuildWith(Widget Function() builder) =>
      setState(() => _builder = builder);

  @override
  Widget build(BuildContext context) => _builder();
}

/// 安装平台替身（每个测试文件 main 中调用一次）
ChannelPlatform installChannelPlatform() {
  final ChannelPlatform p = ChannelPlatform();
  AMapFlutterPlatform.instance = p;
  return p;
}
