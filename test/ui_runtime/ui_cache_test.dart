import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/ui_runtime/ui_cache.dart';
import 'package:myhome/ui_runtime/ui_package.dart';

/// UiCache (WORK_V2 §15.4/§15.5) 测试。
void main() {
  late Directory tempDir;
  late UiCache cache;

  Uint8List pkgWith(Map<String, String> files) => UiPackage.pack(
        files.map((k, v) => MapEntry(k, Uint8List.fromList(utf8.encode(v)))),
      );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ui_cache_test');
    cache = UiCache(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('lookup：未缓存 → null；store 后命中', () async {
    expect(cache.lookup('dev-1', '1.0.0'), isNull);

    final root = await cache.store(
      'dev-1',
      '1.0.0',
      pkgWith(<String, String>{
        'index.html': '<html>v1</html>',
        'style.css': 'body{}',
      }),
    );

    expect(root, cache.versionDir('dev-1', '1.0.0'));
    expect(cache.lookup('dev-1', '1.0.0'), root);
    expect(cache.lookup('dev-1', '9.9.9'), isNull);
    expect(File('$root/index.html').readAsStringSync(), '<html>v1</html>');
    expect(File('$root/style.css').readAsStringSync(), 'body{}');
  });

  test('store：大小校验失败不写缓存 (§15.5)', () async {
    final pkg = pkgWith(<String, String>{'index.html': 'x'});
    await expectLater(
      cache.store('dev-1', '1.0.0', pkg, expectedSize: pkg.length + 1),
      throwsA(isA<StateError>()),
    );
    expect(cache.lookup('dev-1', '1.0.0'), isNull);
    expect(Directory(cache.versionDir('dev-1', '1.0.0')).existsSync(), isFalse);
  });

  test('store：SHA256 校验失败不写缓存 (§15.5)', () async {
    final pkg = pkgWith(<String, String>{'index.html': 'x'});
    await expectLater(
      cache.store(
        'dev-1',
        '1.0.0',
        pkg,
        expectedSha256: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      ),
      throwsA(isA<StateError>()),
    );
    expect(cache.lookup('dev-1', '1.0.0'), isNull);
  });

  test('store：SHA256 正确 → 通过', () async {
    final pkg = pkgWith(<String, String>{'index.html': 'x'});
    final root = await cache.store(
      'dev-1',
      '1.0.0',
      pkg,
      expectedSize: pkg.length,
      expectedSha256: sha256.convert(pkg).toString(),
    );
    expect(cache.lookup('dev-1', '1.0.0'), root);
  });

  test('store：缺少 index.html → 失败', () async {
    await expectLater(
      cache.store('dev-1', '1.0.0', pkgWith(<String, String>{'a.txt': 'x'})),
      throwsA(isA<StateError>()),
    );
  });

  test('store：目录穿越路径 → 失败', () async {
    await expectLater(
      cache.store(
        'dev-1',
        '1.0.0',
        pkgWith(<String, String>{'index.html': 'x', '../evil.txt': 'bad'}),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      File(p.join(tempDir.path, 'evil.txt')).existsSync(),
      isFalse,
      reason: '越界文件不得写入',
    );
  });
}
