import 'dart:typed_data';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x_amap_base/x_amap_base.dart';

class CustomMapStylePage extends StatefulWidget {
  const CustomMapStylePage({super.key});

  @override
  State<CustomMapStylePage> createState() => _CustomMapStyleState();
}

class _CustomMapStyleState extends State<CustomMapStylePage> {
  Uint8List? _style;
  Uint8List? _extra;
  bool _enabled = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    try {
      final ByteData style = await rootBundle.load('assets/style.data');
      final ByteData extra = await rootBundle.load('assets/style_extra.data');
      if (!mounted) return;
      setState(() {
        _style =
            style.buffer.asUint8List(style.offsetInBytes, style.lengthInBytes);
        _extra =
            extra.buffer.asUint8List(extra.offsetInBytes, extra.lengthInBytes);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '样式资源加载失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Expanded(
              child: AMapWidget(
            initialCameraPosition: const CameraPosition(
              target: LatLng(31.230378, 121.473658),
              zoom: 14,
            ),
            customStyleOptions: CustomStyleOptions(
              _enabled,
              styleData: _style,
              styleExtraData: _extra,
            ),
            onMapCreated: (AMapController controller) {
              if (mounted) setState(() => _ready = true);
            },
          )),
          SwitchListTile(
            title: Text(_enabled ? '自定义样式：开启' : '自定义样式：关闭（普通底图）'),
            subtitle: Text(_error ??
                (_style == null
                    ? '正在加载样式文件…'
                    : '样式文件已读取（${_style!.length} 字节），切换开关比较同一视野。')),
            value: _enabled,
            onChanged: _ready && _style != null
                ? (bool value) => setState(() => _enabled = value)
                : null,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
                '文件读取成功不代表 SDK 已应用。若开关前后仍相同，请换成高德平台导出的有效样式文件，并检查 SDK 日志。',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      );
}
