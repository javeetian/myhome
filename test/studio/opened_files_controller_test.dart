import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/opened_files_controller.dart';

void main() {
  late Directory root;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('opened_files_test_');
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  OpenedFilesController controller() =>
      container.read(openedFilesProvider.notifier);

  test('初始为空', () {
    final state = container.read(openedFilesProvider);
    expect(state.paths, isEmpty);
    expect(state.active, isNull);
  });

  test('open：添加标签并激活；重复打开仅切换激活', () {
    controller().open('/a/index.html');
    controller().open('/a/style.css');
    controller().open('/a/index.html'); // 重复

    final state = container.read(openedFilesProvider);
    expect(state.paths, <String>['/a/index.html', '/a/style.css']);
    expect(state.active, '/a/index.html');
  });

  test('close：关闭激活标签时激活最后一个剩余标签', () {
    controller().open('/a/a.html');
    controller().open('/a/b.html');
    controller().open('/a/c.html');
    controller().close('/a/c.html'); // 激活的

    var state = container.read(openedFilesProvider);
    expect(state.paths, <String>['/a/a.html', '/a/b.html']);
    expect(state.active, '/a/b.html');

    controller().close('/a/a.html'); // 非激活

    state = container.read(openedFilesProvider);
    expect(state.paths, <String>['/a/b.html']);
    expect(state.active, '/a/b.html');

    controller().close('/a/b.html');
    state = container.read(openedFilesProvider);
    expect(state.paths, isEmpty);
    expect(state.active, isNull);
  });

  test('resetAndOpen：ui/index.html 存在则自动打开', () {
    final dir = Directory(p.join(root.path, 'dev'))..createSync(recursive: true);
    Directory(p.join(dir.path, 'ui')).createSync();
    File(p.join(dir.path, 'ui', 'index.html')).writeAsStringSync('<html>');

    controller().resetAndOpen(root: dir.path);

    final state = container.read(openedFilesProvider);
    expect(state.paths, <String>[p.join(dir.path, 'ui', 'index.html')]);
    expect(state.active, p.join(dir.path, 'ui', 'index.html'));
  });

  test('resetAndOpen：无入口文件则重置为空', () {
    controller().open('/x/device.yaml');
    final dir = Directory(p.join(root.path, 'empty'))..createSync();

    controller().resetAndOpen(root: dir.path);

    expect(container.read(openedFilesProvider).paths, isEmpty);
  });
}
