import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/device_list_controller.dart';
import 'package:myhome/studio/studio_app.dart';

/// Device Studio 页面 (WORK_V3 §22/§30) 渲染测试。
/// 设备根目录注入临时 fixture，不依赖真实 devices/ 状态
/// (真实目录可能被用户移除/删除)。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('studio_page_test_');
    final dir = Directory(p.join(root.path, 'smart_light'))..createSync();
    File(p.join(dir.path, 'device.yaml')).writeAsStringSync('''
device:
  id: smart_light
  name: Smart Light
  model: L100

protocol:
  version: 1

api:
  version: 1

state: {}

commands: []

events: []
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  testWidgets('idle 状态渲染三栏：设备列表 / 提示 / Inspector / Console', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(
            () => DeviceListController(devicesRoot: root),
          ),
        ],
        child: const StudioApp(),
      ),
    );
    await tester.pump();

    // 标题与三栏
    expect(find.text('Device Studio'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Protocol Console'), findsOneWidget);

    // 设备列表：内置 Demo Light + devices/ 扫描的目录设备 (smart_light)
    expect(find.text('Demo Light'), findsOneWidget);
    expect(find.text('Smart Light'), findsOneWidget);
    expect(find.text('L100 · smart_light'), findsOneWidget);

    // 空闲提示
    expect(find.text('选择左侧设备开始模拟'), findsOneWidget);

    // Inspector 占位字段
    expect(find.text('Device ID'), findsOneWidget);
    expect(find.text('UI Version'), findsOneWidget);
    expect(find.text('State'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
  });
}
