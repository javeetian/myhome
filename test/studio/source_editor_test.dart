import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/source_editor.dart';

/// 源码编辑器测试：加载 / 防抖自动保存 / 二进制占位 / 关闭前落盘。
void main() {
  late Directory root;
  late String filePath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('source_editor_test_');
    filePath = p.join(root.path, 'index.html');
    File(filePath).writeAsStringSync('<html>old</html>');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Future<void> pumpEditor(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SourceEditor(path: filePath))),
      );

  testWidgets('加载并显示文件内容', (tester) async {
    await pumpEditor(tester);

    // 高亮层 + 输入层会渲染同一文本 → findsWidgets
    expect(find.text('<html>old</html>'), findsWidgets);
    expect(find.text(filePath), findsOneWidget); // 路径栏
  });

  testWidgets('编辑后防抖自动保存到磁盘', (tester) async {
    await pumpEditor(tester);

    await tester.enterText(find.byType(EditableText), '<html>new</html>');
    expect(File(filePath).readAsStringSync(), '<html>old</html>',
        reason: '防抖未到期不应写入');

    await tester.pump(const Duration(milliseconds: 700));

    expect(File(filePath).readAsStringSync(), '<html>new</html>');
  });

  testWidgets('二进制文件显示占位提示', (tester) async {
    final binPath = p.join(root.path, 'ui.pkg');
    File(binPath).writeAsBytesSync(<int>[0x00, 0xFF, 0xFE, 0x00, 0x80]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SourceEditor(path: binPath))),
    );

    expect(find.textContaining('二进制文件不可编辑'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('切换标签 (dispose) 前未保存内容落盘', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(EditableText), '<html>pending</html>');

    // 未等防抖到期直接移除编辑器 (模拟切标签)
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    expect(File(filePath).readAsStringSync(), '<html>pending</html>');
  });
}
