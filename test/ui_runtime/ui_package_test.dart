import 'dart:convert';
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
}
