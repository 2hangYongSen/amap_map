# Fork 说明

本仓库 fork 自 [kuloud/amap_map](https://github.com/kuloud/amap_map)，用于实现原生点位（Native Marker）能力。

## 远程仓库

| 名称 | 地址 | 用途 |
| --- | --- | --- |
| origin | git@github.com:2hangYongSen/amap_map.git | 本 fork |
| upstream | https://github.com/kuloud/amap_map.git | 上游，只拉取不推送 |

同步上游：`git fetch upstream` 后在独立分支合并或变基，解决冲突后再进主线。

## 固定环境

- Flutter 3.41.4（Dart 3.11.1），不升级。
- 高德 SDK 10.1.200，不升级。
- 旧 `Marker.icon` 行为保持不变；Android 用 Java，iOS 用 Objective-C。

## CI 与发布

- `.github/workflows/ci.yml`：push、PR、手动触发。分两组运行：
  - `locked`：按 `example/pubspec.lock` 锁定版本（`--enforce-lockfile`）。
  - `downgraded`：`flutter pub downgrade` 按最低版本。
- `.github/workflows/publish.yml`：仅 `workflow_dispatch` 手动触发，不再随 push 或 PR 自动发布。
- `example/pubspec.lock` 已纳入版本管理（`.gitignore` 中 `!example/pubspec.lock`），插件根目录的锁文件仍忽略。

## 基线（S0 记录）

| 项目 | 结果 |
| --- | --- |
| 根目录 `flutter analyze` | 143 个 issue（info 为主） |
| `example` 目录 `flutter analyze` | 100 个 issue |
| `example` 目录 `flutter test` | 14 个用例全部通过 |
| 根目录 `flutter test` | 无用例（`test/amap_flutter_map_test.dart` 内容已被注释） |

后续阶段要求：新增文件 analyze 0 issue，已有 14 个用例持续通过。

## Android JVM 单测（S5 起）

插件目录本身不能独立构建，经 example 工程运行（JDK 17）：

```bash
cd example/android && ./gradlew :amap_map:testDebugUnitTest
```

测试位于 `android/src/test/java/`，只依赖 `testImplementation 'junit:junit:4.13.2'`。

## 对照入口

`example/lib/pages/interactive/marker_benchmark_page.dart` 提供点位数量（0/100/200）和图标类型（默认图标 / PNG 图标）切换，用于旧 `Marker.icon` 路径的对照。
