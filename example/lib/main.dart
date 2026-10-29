import 'package:amap_map/amap_map.dart';
import 'package:amap_map_example/const_config.dart';
import 'package:amap_map_example/data/demos.dart';
import 'package:amap_map_example/routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AMapDemoApp());

class AMapDemoApp extends StatelessWidget {
  const AMapDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AMap Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        onGenerateRoute: RouteConfig.onGenerateRoute,
        home: const AMapDemo(),
      );
}

class AMapDemo extends StatelessWidget {
  const AMapDemo({super.key});

  @override
  Widget build(BuildContext context) {
    AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
    AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);
    final Map<String, List<Demo>> groups = <String, List<Demo>>{};
    for (final Demo demo in allDemos()) {
      groups.putIfAbsent(demo.group, () => <Demo>[]).add(demo);
    }
    const String mode =
        kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug');
    return Scaffold(
      appBar: AppBar(title: const Text('高德地图测试示例')),
      body: ListView(
        key: const PageStorageKey<String>('demo-list'),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: Text('$mode · ${allDemos().length} 项测试'),
            subtitle: const Text('性能对比请用真机 Release；每页右上角可查看测试步骤。'),
          ),
          for (final MapEntry<String, List<Demo>> group
              in groups.entries) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(group.key,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  )),
            ),
            for (final Demo demo in group.value)
              ListTile(
                title: Text(demo.title),
                subtitle:
                    Text(demo.subtitle, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed('/${demo.slug}'),
              ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
