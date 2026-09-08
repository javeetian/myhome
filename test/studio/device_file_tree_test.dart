import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/device_file_tree.dart';

/// 设备目录文件树 (VS Code Explorer 风格) 测试。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_tree_test_');
    Directory(p.join(root.path, 'ui')).createSync();
    File(p.join(root.path, 'ui', 'index.html')).writeAsStringSync('<html>');
    File(p.join(root.path, 'ui', 'style.css')).writeAsStringSync('body{}');
    Directory(p.join(root.path, 'build')).createSync();
    File(p.join(root.path, 'build', 'ui.pkg')).writeAsBytesSync(<int>[1, 2, 3]);
    File(p.join(root.path, 'device.yaml')).writeAsStringSync('device:');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Widget buildTree({String? deviceDir}) => MaterialApp(
        home: Scaffold(body: DeviceFileTree(deviceDir: deviceDir)),
      );

  testWidgets('无设备目录时显示占位提示', (tester) async {
    await tester.pumpWidget(buildTree());

    expect(find.text('启动设备后显示其目录'), findsOneWidget);
  });

  testWidgets('目录在前排序，文件按名显示', (tester) async {
    await tester.pumpWidget(buildTree(deviceDir: root.path));

    expect(find.text('ui'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    expect(find.text('device.yaml'), findsOneWidget);
  });

  testWidgets('展开文件夹显示子文件，层级递归', (tester) async {
    await tester.pumpWidget(buildTree(deviceDir: root.path));

    expect(find.text('index.html'), findsNothing);
    await tester.tap(find.text('ui'));
    await tester.pumpAndSettle();

    expect(find.text('index.html'), findsOneWidget);
    expect(find.text('style.css'), findsOneWidget);
  });

  testWidgets('点击文件回调 onFileTap', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceFileTree(
            deviceDir: root.path,
            onFileTap: tapped.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('ui'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('index.html'));
    await tester.pumpAndSettle();

    expect(tapped, <String>[p.join(root.path, 'ui', 'index.html')]);
  });

  testWidgets('文件图标按扩展名区分', (tester) async {
    await tester.pumpWidget(buildTree(deviceDir: root.path));

    expect(find.byIcon(Icons.settings), findsOneWidget); // device.yaml

    await tester.tap(find.text('ui'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.language), findsOneWidget); // .html
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget); // .css

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget); // .pkg
  });

  testWidgets('刷新按钮重建文件树 (新文件出现)', (tester) async {
    await tester.pumpWidget(buildTree(deviceDir: root.path));

    expect(find.text('new_file.js'), findsNothing);
    File(p.join(root.path, 'new_file.js')).writeAsStringSync('//');
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('new_file.js'), findsOneWidget);
  });
}
