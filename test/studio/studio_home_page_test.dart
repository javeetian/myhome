import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/device_list_controller.dart';
import 'package:myhome/studio/studio_home_page.dart';

/// 左栏设备列表面板测试：渲染 + ⋮ 菜单 + 新建弹窗流程。
void main() {
  late Directory root;

  void makeDevice(String id, String name, String model) {
    final dir = Directory(p.join(root.path, id))..createSync();
    File(p.join(dir.path, 'device.yaml')).writeAsStringSync('''
device:
  id: $id
  name: $name
  model: $model

protocol:
  version: 1

api:
  version: 1

state: {}

commands: []

events: []
''');
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('studio_home_test_');
    makeDevice('ac_unit', 'AC Unit', 'AC-1');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Widget buildApp() => ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(
            () => DeviceListController(devicesRoot: root),
          ),
        ],
        child: const MaterialApp(home: StudioHomePage()),
      );

  testWidgets('渲染：内置 Demo Light + devices/ 扫描的目录设备卡片', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('设备'), findsOneWidget);
    expect(find.text('Demo Light'), findsOneWidget);
    expect(find.text('AC Unit'), findsOneWidget);
    expect(find.text('AC-1 · ac_unit'), findsOneWidget);
    // 卡片左上角 ⋮ (Demo Light 无 ⋮, 目录设备有 1 个)
    expect(find.byIcon(Icons.more_vert), findsNWidgets(2)); // 头部 1 + 卡片 1
  });

  testWidgets('设备卡片 ⋮ 菜单：移除 / 删除', (tester) async {
    await tester.pumpWidget(buildApp());

    // 点卡片 ⋮ (第二个 more_vert 图标)
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();

    expect(find.text('从列表移除'), findsOneWidget);
    expect(find.text('删除设备目录'), findsOneWidget);
  });

  testWidgets('从列表移除：卡片消失且写入 .removed 标记', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从列表移除'));
    await tester.pumpAndSettle();

    expect(find.text('AC Unit'), findsNothing);
    expect(
      File(p.join(root.path, 'ac_unit', '.removed')).existsSync(),
      isTrue,
    );
  });

  testWidgets('删除设备目录：确认弹窗 → 目录删除', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除设备目录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('此操作不可恢复'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('AC Unit'), findsNothing);
    expect(Directory(p.join(root.path, 'ac_unit')).existsSync(), isFalse);
  });

  testWidgets('头部 ⋮ 菜单：新建设备 / 打开设备目录', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('新建设备'), findsOneWidget);
    expect(find.text('打开设备目录'), findsOneWidget);
  });

  testWidgets('打开设备目录：选择器选中目录 → 设备加入列表', (tester) async {
    // 外部设备目录 fixture
    final external = Directory.systemTemp.createTempSync('external_dev_');
    File(p.join(external.path, 'device.yaml')).writeAsStringSync('''
device:
  id: ext_light
  name: Ext Light
  model: E1

protocol:
  version: 1

api:
  version: 1

state: {}

commands: []

events: []
''');
    addTearDown(() => external.deleteSync(recursive: true));

    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(
            () => DeviceListController(
              devicesRoot: root,
              picker: () async => picked,
            ),
          ),
        ],
        child: const MaterialApp(home: StudioHomePage()),
      ),
    );

    // 取消场景：选择器返回 null → 列表无变化
    picked = null;
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开设备目录'));
    await tester.pumpAndSettle();
    expect(find.text('Ext Light'), findsNothing);

    // 选中场景：设备出现在列表
    picked = external.path;
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开设备目录'));
    await tester.pumpAndSettle();

    expect(find.text('Ext Light'), findsOneWidget);
    expect(find.text('E1 · ext_dev'), findsNothing); // 外部目录副标题是 basename
  });

  testWidgets('新建设备：弹窗填写 → devices/<id>/device.yaml 生成 + 列表刷新', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设备'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'new_light');
    await tester.enterText(find.byType(TextFormField).at(1), 'New Light');
    await tester.enterText(find.byType(TextFormField).at(2), 'N100');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('New Light'), findsOneWidget);
    final yaml = File(p.join(root.path, 'new_light', 'device.yaml'));
    expect(yaml.existsSync(), isTrue);
    expect(yaml.readAsStringSync(), contains('name: New Light'));
  });

  testWidgets('新建设备：非法 ID 弹窗校验拦截', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设备'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Bad-Id');
    await tester.enterText(find.byType(TextFormField).at(1), 'X');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.textContaining('小写字母'), findsOneWidget);
    expect(Directory(p.join(root.path, 'Bad-Id')).existsSync(), isFalse);
  });
}
