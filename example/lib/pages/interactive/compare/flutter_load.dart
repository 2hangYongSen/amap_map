import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 模拟业务页面的 Flutter 负载档位
enum FlutterLoad {
  off('无负载', 0, 0),
  // 空转毫秒数要低于一帧预算（120Hz 为 8.3ms），否则负载本身就让每帧都卡，比不出差异
  light('轻负载', 2, 24),
  heavy('重负载', 5, 300);

  const FlutterLoad(this.label, this.uiBusyMs, this.particles);
  final String label;

  /// 界面线程：每帧同步空转的毫秒数（模拟业务逻辑、列表构建、JSON 解析）
  final int uiBusyMs;

  /// 绘制线程：叠加动画里的半透明粒子数（模拟筛选面板、加载动画）
  final int particles;
}

/// 叠在地图上的负载层：持续动画驱动每帧重建，build 时空转 [FlutterLoad.uiBusyMs]，
/// 绘制若干带模糊的半透明粒子。不拦截触摸。
class FlutterLoadLayer extends StatefulWidget {
  const FlutterLoadLayer({super.key, required this.load});
  final FlutterLoad load;

  @override
  State<FlutterLoadLayer> createState() => _FlutterLoadLayerState();
}

class _FlutterLoadLayerState extends State<FlutterLoadLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(FlutterLoadLayer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.load == FlutterLoad.off) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.load == FlutterLoad.off) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, __) {
          _spin(widget.load.uiBusyMs);
          return CustomPaint(
              size: Size.infinite,
              painter: _Particles(_a.value, widget.load.particles));
        },
      ),
    );
  }

  /// 同步空转，占住界面线程
  static void _spin(int ms) {
    final Stopwatch w = Stopwatch()..start();
    while (w.elapsedMicroseconds < ms * 1000) {}
  }
}

class _Particles extends CustomPainter {
  _Particles(this.t, this.n);
  final double t;
  final int n;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (int i = 0; i < n; i++) {
      // 每个粒子沿自己的圆轨道运动，位置由 i 和 t 决定
      final double a = 2 * pi * (t + i / n);
      final double r = 40 + (i * 37 % 160);
      final Offset c = Offset(size.width / 2 + cos(a * (1 + i % 3)) * r,
          size.height / 2 + sin(a) * r);
      p.color = Color.fromARGB(60, (i * 53) % 256, (i * 97) % 256, 200);
      canvas.drawCircle(c, 6 + (i % 5) * 2, p);
    }
  }

  @override
  bool shouldRepaint(_Particles old) => old.t != t || old.n != n;
}

/// Flutter 帧耗时统计：统计 vsync 落在 [start, start+window] 内、构建或绘制超过一帧预算的帧。
/// 引擎按批（约 1 秒）上报帧耗时，所以按帧自带的 vsync 时间戳过滤，而不是按回调到达时间。
/// 窗口起点取下一帧的 [SchedulerBinding.currentSystemFrameTimeStamp]（引擎下发的原始 vsync 时刻），
/// 与 [ui.FramePhase.vsyncStart] 同一个时钟，不和 Dart 的 Stopwatch 混用。
class JankMeter {
  JankMeter({this.budgetMs = 1000 / 60});

  /// 单帧预算（默认 60Hz）；高刷设备可传 1000/120
  final double budgetMs;

  int frames = 0, jankBuild = 0, jankRaster = 0;
  double worstMs = 0;
  // 起点确定前为最大值，丢弃所有帧
  int _from = 1 << 62, _to = 0;

  /// 开始一个统计窗口；窗口结束后再等约 1.5 秒，引擎才会把最后一批帧报上来
  void start(Duration window) {
    frames = jankBuild = jankRaster = 0;
    worstMs = 0;
    _from = 1 << 62;
    final SchedulerBinding b = SchedulerBinding.instance;
    b.scheduleFrameCallback((_) {
      _from = b.currentSystemFrameTimeStamp.inMicroseconds;
      _to = _from + window.inMicroseconds;
    });
    b
      ..scheduleFrame()
      ..removeTimingsCallback(_onTimings)
      ..addTimingsCallback(_onTimings);
  }

  void stop() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  int get janky => jankBuild + jankRaster;

  /// 整帧被跳过的数量：窗口内应有帧数（时长 ÷ 帧预算）减实际帧数。
  /// 卡顿帧只统计“出了但慢”的帧，主线程被占满时帧根本不出，只能靠它看到
  int get dropped => max(0, ((_to - _from) / 1000 / budgetMs).round() - frames);

  void _onTimings(List<ui.FrameTiming> ts) {
    for (final ui.FrameTiming t in ts) {
      final int v = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      if (v < _from || v > _to) continue;
      frames++;
      final double b = t.buildDuration.inMicroseconds / 1000.0;
      final double r = t.rasterDuration.inMicroseconds / 1000.0;
      // 一帧只记一次，按超时的那条线程归类
      if (b > budgetMs) {
        jankBuild++;
      } else if (r > budgetMs) {
        jankRaster++;
      }
      worstMs = max(worstMs, max(b, r));
    }
  }

  @override
  String toString() =>
      '$frames 帧，卡顿 $janky（界面 $jankBuild / 绘制 $jankRaster），最长 ${worstMs.toStringAsFixed(1)}ms';
}
