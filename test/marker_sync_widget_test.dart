import 'package:amap_map/amap_map.dart';
import 'package:amap_map/src/core/amap_flutter_platform.dart';
import 'package:amap_map/src/core/method_channel_amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 只替换平台视图，其余走真实 MethodChannel（由 mock handler 应答）。
class _ChannelPlatform extends MethodChannelAMapFlutterMap
    with MockPlatformInterfaceMixin {
  int nextId = 0;
  int buildCount = 0;
  final Set<Map<String, dynamic>> creationParamsSeen =
      Set<Map<String, dynamic>>.identity();
  bool _created = false;

  void reset() => _created = false;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers,
    void Function(int) onPlatformViewCreated,
  ) {
    buildCount++;
    creationParamsSeen.add(creationParams);
    if (!_created) {
      _created = true;
      final int id = nextId++;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onPlatformViewCreated(id));
    }
    return const SizedBox.expand();
  }
}

const NativeMarkerStyle _style = NativeMarkerStyle(
  background: NativeMarkerShapeBackground.roundedRect(
      fillColor: Color(0xFFFFFFFF), cornerRadius: 4),
);

Marker _native(String id, {ArgumentCallback<String>? onTap, String? iconId}) =>
    Marker(
      markerId: id,
      position: const LatLng(30, 120),
      onTap: onTap,
      nativePresentation: NativeMarkerPresentation(
        content: NativeMarkerContent(text: id, iconId: iconId),
        style: _style,
      ),
    );

void main() {
  final _ChannelPlatform platform = _ChannelPlatform();
  AMapFlutterPlatform.instance = platform;
  final List<MethodCall> calls = <MethodCall>[];
  late int mapId;

  /// 打开地图并接管该地图通道的应答
  Future<void> open(WidgetTester tester, Widget Function() map) async {
    platform.reset();
    mapId = platform.nextId;
    calls.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('amap_map_$mapId'), (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'markers#attach':
          return <String, Object?>{
            'protocolVersion': 2,
            'syncId': 0,
            'rejectedMarkerIds': <String>[],
          };
        case 'markers#update':
        case 'markers#resync':
          final Object? args = call.arguments;
          return <String, Object?>{
            'syncId': args is Map ? args['syncId'] : null,
            'accepted': true,
            'rejectedMarkerIds': <String>[],
          };
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: _Host(builder: map)));
    await tester.pumpAndSettle();
  }

  Future<void> rebuild(WidgetTester tester, Widget Function() map) async {
    tester.state<_HostState>(find.byType(_Host)).rebuildWith(map);
    await tester.pumpAndSettle();
  }

  // 折线、多边形每次重建都会发送（原有行为，不在本阶段范围），只看点位与初始化
  List<String> methods() => calls
      .map((MethodCall c) => c.method)
      .where((String m) => m.startsWith('markers#') || m == 'map#waitForMap')
      .toList();

  testWidgets('T-SYNC-2 只换 onTap 或相同内容重建时通道调用为 0',
      (WidgetTester tester) async {
    await open(tester,
        () => AMapWidget(markers: <Marker>{_native('a', onTap: (_) {})}));
    expect(methods(), <String>['map#waitForMap', 'markers#attach']);
    calls.clear();
    for (int i = 0; i < 3; i++) {
      await rebuild(tester,
          () => AMapWidget(markers: <Marker>{_native('a', onTap: (_) {})}));
    }
    expect(methods(), isEmpty);
  });

  testWidgets('T-SYNC-4 带字节资源 build 50 次，创建参数只计算 1 次',
      (WidgetTester tester) async {
    final MarkerImageResource icon =
        MarkerImageResource.bytes(Uint8List.fromList(<int>[1, 2, 3, 4]));
    final int digests = MarkerImageResource.debugDigestComputeCount;
    platform.creationParamsSeen.clear();
    platform.buildCount = 0;
    Widget map() => AMapWidget(
          markers: <Marker>{_native('a', iconId: icon.id)},
          markerImages: <MarkerImageResource>{icon},
        );
    await open(tester, map);
    for (int i = 0; i < 49; i++) {
      await rebuild(tester, map);
    }
    expect(platform.buildCount, greaterThanOrEqualTo(50));
    expect(platform.creationParamsSeen, hasLength(1));
    final Map<String, dynamic> params = platform.creationParamsSeen.single;
    expect(params['protocolVersion'], 2);
    expect((params['imagesToAdd'] as List<dynamic>).single['id'], icon.id);
    expect(MarkerImageResource.debugDigestComputeCount, digests);
    expect(methods().where((String m) => m == 'markers#update'), isEmpty);
  });

  testWidgets('T-SYNC-7 已接受的点收到 invalidConfig，不重发且回调一次',
      (WidgetTester tester) async {
    final List<NativeMarkerError> errors = <NativeMarkerError>[];
    Widget map() => AMapWidget(
          markers: <Marker>{_native('d')},
          onNativeMarkerError: errors.add,
        );
    await open(tester, map);
    calls.clear();
    final ByteData event = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('marker#nativeError', <String, Object?>{
      'code': 'invalidConfig',
      'markerId': 'd',
      'message': 'capInsets 超出图片尺寸',
    }));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('amap_map_$mapId', event, (_) {});
    await tester.pumpAndSettle();
    await rebuild(tester, map);
    expect(errors, hasLength(1));
    expect(errors.single.code, NativeMarkerErrorCode.invalidConfig);
    expect(errors.single.markerId, 'd');
    expect(methods(), isEmpty);
  });

  testWidgets('T-VAL-2 校验失败时整体不发送 markers#update',
      (WidgetTester tester) async {
    await open(tester, () => AMapWidget(markers: <Marker>{_native('a')}));
    calls.clear();
    final Marker bad = Marker(
      markerId: 'bad',
      position: const LatLng(30, 120),
      nativePresentation: NativeMarkerPresentation(
        content: const NativeMarkerContent(text: 'x'),
        style: _style.copyWith(fontSize: 0),
      ),
    );
    await rebuild(tester,
        () => AMapWidget(markers: <Marker>{_native('a'), _native('b'), bad}));
    expect(tester.takeException(), isA<ArgumentError>());
    expect(methods(), isNot(contains('markers#update')));
    // 地图状态保留，没有因异常重建平台视图
    expect(platform.nextId, mapId + 1);
    // 修正后正常发送，非法值从未进入基准
    await rebuild(
        tester, () => AMapWidget(markers: <Marker>{_native('a'), _native('b')}));
    expect(methods(), <String>['markers#update']);
  });

  testWidgets('诊断回调开启新协议；回执与点击计时经通道交付', (WidgetTester tester) async {
    platform.creationParamsSeen.clear();
    final List<MarkerUpdateReport> reports = <MarkerUpdateReport>[];
    final List<MarkerTapReport> taps = <MarkerTapReport>[];
    final List<String> tapped = <String>[];
    await open(
        tester,
        () => AMapWidget(
              markers: <Marker>{
                Marker(
                    markerId: 'i',
                    position: const LatLng(30, 120),
                    onTap: tapped.add)
              },
              onMarkerUpdateApplied: reports.add,
              onMarkerTapApplied: taps.add,
            ));
    final Map<String, dynamic> params = platform.creationParamsSeen.single;
    expect(params['protocolVersion'], 2);
    expect(params['markerDiagnostics'], isTrue);
    Future<void> send(String method, Map<String, Object?> args) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'amap_map_$mapId',
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
          (_) {});
      await tester.pumpAndSettle();
    }

    await send('marker#onTap', <String, Object?>{'markerId': 'i', 'tapId': 1});
    expect(tapped, <String>['i'], reason: '业务 onTap 照常');
    await send('markers#applied', <String, Object?>{
      'eventSeq': 1,
      'syncId': 0,
      'nativeT2Ms': 1.0,
      'nativeT4Ms': 2.0,
      't2ToT3Ms': 0.5,
      't2ToT4Ms': 1.0,
    });
    await send('markers#tapApplied', <String, Object?>{
      'eventSeq': 2,
      'tapId': 1,
      'markerId': 'i',
      'c1Ms': 10.0,
      'c2Ms': 12.0,
      'path': 'icon',
    });
    expect(reports.single.syncId, 0);
    expect(taps.single.c1ToC2Ms, 2.0);
  });

  testWidgets('T-COMPAT-1 纯旧协议地图创建参数与更新载荷不含新键',
      (WidgetTester tester) async {
    platform.creationParamsSeen.clear();
    Marker icon(double lat) =>
        Marker(markerId: 'i', position: LatLng(lat, 120));
    await open(tester, () => AMapWidget(markers: <Marker>{icon(30)}));
    final Map<String, dynamic> params = platform.creationParamsSeen.single;
    expect(params.containsKey('protocolVersion'), isFalse);
    expect(params.containsKey('imagesToAdd'), isFalse);
    await rebuild(tester, () => AMapWidget(markers: <Marker>{icon(31)}));
    expect(methods(), <String>['map#waitForMap', 'markers#update']);
    final Map<Object?, Object?> payload = calls
        .lastWhere((MethodCall c) => c.method == 'markers#update')
        .arguments as Map<Object?, Object?>;
    expect(payload.keys.toSet(),
        <String>{'markersToAdd', 'markersToChange', 'markerIdsToRemove'});
  });
}

/// 可从测试里替换子 Widget 并触发重建的宿主
class _Host extends StatefulWidget {
  const _Host({required this.builder});

  final Widget Function() builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Widget Function() _builder = widget.builder;

  void rebuildWith(Widget Function() builder) =>
      setState(() => _builder = builder);

  @override
  Widget build(BuildContext context) => _builder();
}
