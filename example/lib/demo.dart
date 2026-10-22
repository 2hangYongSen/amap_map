import 'package:amap_map_example/data/demos.dart';
import 'package:flutter/material.dart';

class DemoPage extends StatelessWidget {
  const DemoPage({super.key, required this.slug});
  final String? slug;

  @override
  Widget build(BuildContext context) {
    final Demo? demo = slugToDemo(context)[slug];
    if (demo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('未找到测试')),
        body: const Center(child: Text('请返回首页选择测试项目。')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(demo.title),
        actions: <Widget>[
          IconButton(
            tooltip: '测试步骤',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: Text(demo.title),
                content: SingleChildScrollView(child: Text(demo.steps)),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('知道了')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
          child: Builder(builder: demo.configurations.first.buildRoute)),
    );
  }
}
