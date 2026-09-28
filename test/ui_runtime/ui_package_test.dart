import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/ui_runtime/ui_package.dart';

/// ui.pkg 打包格式 (WORK_V2 §15.2) 测试。
void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('多文件打包/解包 round-trip (§15.2 目录结构)', () {
    final files = <String, Uint8List>{
      'manifest.json': bytes('{"protocol":1}'),
      'index.html': bytes('<html><body>hi</body></html>'),
      'style.css': bytes('body{color:red}'),
      'assets/icon.svg': bytes('<svg/>'),
    };
    final pkg = UiPackage.pack(files);
    final unpacked = UiPackage.unpack(pkg);

    expect(unpacked.keys.toSet(), files.keys.toSet());
    for (final entry in files.entries) {
      expect(unpacked[entry.key], entry.value, reason: '文件 ${entry.key} 内容一致');
    }
  });

  test('同内容字节确定性 (可复现构建, §15.5)', () {
    final files = <String, Uint8List>{'index.html': bytes('<html/>')};
    expect(UiPackage.pack(files), UiPackage.pack(files));
  });

  test('空 pkg 解包为空集合', () {
    expect(UiPackage.unpack(UiPackage.pack(<String, Uint8List>{})), isEmpty);
  });

  group('.uipkgignore 排除清单', () {
    test('parseIgnore：跳过注释/空行，反斜杠归一为 /', () {
      final patterns = UiPackageSource.parseIgnore(
        '# 注释\n\n  icons/icon-1024.png  \nserve.py\nicons\\maskable-512.png\n',
      );
      expect(patterns, ['icons/icon-1024.png', 'serve.py', 'icons/maskable-512.png']);
    });

    test('isIgnored：整条路径 / 任意层级文件名 / 目录 / 通配符', () {
      final patterns = UiPackageSource.parseIgnore('''
# PWA 素材
icons/icon-1024.png
sw.js
pwa/
*.txt
notes?.md
''');
      // 整条相对路径
      expect(UiPackageSource.isIgnored('icons/icon-1024.png', patterns), isTrue);
      // 不含 / 的模式匹配任意层级的同名文件
      expect(UiPackageSource.isIgnored('sw.js', patterns), isTrue);
      expect(UiPackageSource.isIgnored('js/sw.js', patterns), isTrue);
      // 目录模式
      expect(UiPackageSource.isIgnored('pwa/a.png', patterns), isTrue);
      expect(UiPackageSource.isIgnored('assets/pwa/a.png', patterns), isTrue);
      expect(UiPackageSource.isIgnored('pwa2/a.png', patterns), isFalse);
      // 通配符
      expect(UiPackageSource.isIgnored('docs/readme.txt', patterns), isTrue);
      expect(UiPackageSource.isIgnored('notes1.md', patterns), isTrue);
      expect(UiPackageSource.isIgnored('notes12.md', patterns), isFalse);
      // 未命中
      expect(UiPackageSource.isIgnored('icons/icon-192.png', patterns), isFalse);
      expect(UiPackageSource.isIgnored('icons/apple-touch-icon.png', patterns), isFalse);
      // 路径模式不跨目录段：icons/icon-1024.png 不匹配别的层级
      expect(UiPackageSource.isIgnored('a/icons/icon-1024.png', patterns), isFalse);
    });

    test('collect：被排除文件不进包，清单本身不进包', () {
      final dir = Directory.systemTemp.createTempSync('uipkg_ignore');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/manifest.json').writeAsStringSync('{"entry":"index.html"}');
      File('${dir.path}/index.html').writeAsStringSync('<html/>');
      File('${dir.path}/serve.py').writeAsStringSync('print(1)');
      File('${dir.path}/改bug.txt').writeAsStringSync('笔记');
      Directory('${dir.path}/icons').createSync();
      File('${dir.path}/icons/icon-192.png').writeAsBytesSync(<int>[1, 2]);
      File('${dir.path}/icons/icon-1024.png').writeAsBytesSync(<int>[3, 4]);
      File('${dir.path}/.uipkgignore').writeAsStringSync(
        '# 开发遗留\nserve.py\n*.txt\nicons/icon-1024.png\n',
      );

      final collected = UiPackageSource.collect(dir);
      expect(
        collected.files.keys.toSet(),
        {'manifest.json', 'index.html', 'icons/icon-192.png'},
      );
      expect(
        collected.skipped,
        ['.uipkgignore', 'icons/icon-1024.png', 'serve.py', '改bug.txt'],
      );
    });

    test('collect：无清单 → 全量打包', () {
      final dir = Directory.systemTemp.createTempSync('uipkg_noignore');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/index.html').writeAsStringSync('<html/>');

      final collected = UiPackageSource.collect(dir);
      expect(collected.files.keys, ['index.html']);
      expect(collected.skipped, isEmpty);
    });
  });
}
