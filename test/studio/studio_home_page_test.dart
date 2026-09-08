import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/device/virtual_light.dart';
import 'package:myhome/studio/device_list_controller.dart';
import 'package:myhome/studio/studio_controller.dart';
import 'package:myhome/studio/studio_home_page.dart';
import 'package:myhome/ui_runtime/ui_cache.dart';

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

    // 点卡片 ⋮ (底部列表是懒构建滚动区，先滚到可见)
    final cardMenu = find.byIcon(Icons.more_vert).last;
    await tester.ensureVisible(cardMenu);
    await tester.pumpAndSettle();
    await tester.tap(cardMenu);
    await tester.pumpAndSettle();

    expect(find.text('从列表移除'), findsOneWidget);
    expect(find.text('删除设备目录'), findsOneWidget);
  });

  testWidgets('从列表移除：卡片消失且写入 .removed 标记', (tester) async {
    await tester.pumpWidget(buildApp());

    final cardMenu = find.byIcon(Icons.more_vert).last;
    await tester.ensureVisible(cardMenu);
    await tester.pumpAndSettle();
    await tester.tap(cardMenu);
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

    final cardMenu = find.byIcon(Icons.more_vert).last;
    await tester.ensureVisible(cardMenu);
    await tester.pumpAndSettle();
    await tester.tap(cardMenu);
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

    // 新卡片在底部滚动区，滚到可见再断言
    await tester.scrollUntilVisible(
      find.text('Ext Light'),
      40,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ext Light'), findsOneWidget);
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

    await tester.scrollUntilVisible(
      find.text('New Light'),
      40,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('New Light'), findsOneWidget);
    final yaml = File(p.join(root.path, 'new_light', 'device.yaml'));
    expect(yaml.existsSync(), isTrue);
    expect(yaml.readAsStringSync(), contains('name: New Light'));
  });

  testWidgets('分割线可拖拽调整栏宽 (带上下限)', (tester) async {
    await tester.pumpWidget(buildApp());

    // 设备列表 | 文件树 分割线：向右拖 60 → 设备列表变宽
    final devPanel = find.byKey(StudioHomePage.deviceListDividerKey);
    final widthBefore =
        tester.getSize(find.byType(StudioHomePage).first).width;

    await tester.drag(devPanel, const Offset(60, 0));
    await tester.pumpAndSettle();
    final devListWidth = tester.getSize(
      find.descendant(
        of: find.byType(StudioHomePage),
        matching: find.text('设备'),
      ).first,
    );
    expect(devListWidth, isNotNull);

    // Inspector 分割线：向右拖 400 → 宽度被钳到最小值 180
    await tester.drag(
      find.byKey(StudioHomePage.inspectorDividerKey),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    final inspectorSize = tester.getSize(
      find.ancestor(
        of: find.text('Inspector'),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(inspectorSize.width, closeTo(180, 1));

    // 文件树分割线：向左拖 1000 → 钳到最小值 120
    await tester.drag(
      find.byKey(StudioHomePage.fileTreeDividerKey),
      const Offset(-1000, 0),
    );
    await tester.pumpAndSettle();
    final treeSize = tester.getSize(
      find.ancestor(
        of: find.text('文件'),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(treeSize.width, closeTo(120, 1));
    expect(widthBefore, isNotNull);
  });

  testWidgets('启动设备：自动打开 index.html 标签，文件树点击切换标签', (tester) async {
    // 设备目录 fixture: ui/index.html + ui/style.css
    final devDir = Directory(p.join(root.path, 'ac_unit'));
    Directory(p.join(devDir.path, 'ui')).createSync(recursive: true);
    File(p.join(devDir.path, 'ui', 'index.html')).writeAsStringSync('<html>A</html>');
    File(p.join(devDir.path, 'ui', 'style.css')).writeAsStringSync('body{}');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(
            () => DeviceListController(devicesRoot: root),
          ),
          studioControllerProvider.overrideWith(
            () => StudioController(cache: UiCache(p.join(root.path, 'cache'))),
          ),
        ],
        child: const MaterialApp(home: StudioHomePage()),
      ),
    );
    await tester.pump();

    // 启动设备 (内存传输, 不构建 WebView —— 拆分视图默认关闭)
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioHomePage)),
    );
    // 设备连接/握手涉及真实异步 (FakeAsync 下会挂起) → runAsync
    final ok = await tester.runAsync(() => container
        .read(studioControllerProvider.notifier)
        .start(VirtualLight(uiPkgBytes: null), deviceDir: devDir.path));
    expect(ok, isTrue);
    // 设备有周期定时器 (温度采样/心跳)，不能用 pumpAndSettle —— 有界 pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 自动打开 index.html 标签 + 编辑器内容
    expect(find.text('index.html'), findsWidgets); // 标签 + 文件树
    expect(find.text('<html>A</html>'), findsWidgets); // 高亮层+输入层

    // 文件树点击 style.css → 新标签 + 内容切换
    await tester.tap(find.text('ui'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('style.css'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('body{}'), findsWidgets);
    expect(find.text('<html>A</html>'), findsNothing);

    // 右上角拆分按钮存在
    expect(find.byIcon(Icons.splitscreen), findsOneWidget);

    // 停止设备，取消周期定时器 (温度采样/心跳)
    await tester.runAsync(
      () => container.read(studioControllerProvider.notifier).stop(),
    );
    await tester.pump();
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
