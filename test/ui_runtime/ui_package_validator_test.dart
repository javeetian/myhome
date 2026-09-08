import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/ui_runtime/ui_package.dart';
import 'package:myhome/ui_runtime/ui_package_validator.dart';

/// UI Package 校验器 (WORK_V3 Phase 14) 测试。
void main() {
  Uint8List pkgWith(Map<String, dynamic> manifest, Map<String, String> files) {
    return UiPackage.pack(<String, Uint8List>{
      'manifest.json': Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      for (final entry in files.entries)
        entry.key: Uint8List.fromList(utf8.encode(entry.value)),
    });
  }

  const validV3Manifest = <String, dynamic>{
    'package': 'light_ui',
    'version': '1.0.0',
    'device': <String, dynamic>{'type': 'light', 'model': 'L100'},
    'protocol': <String, dynamic>{'version': 1},
    'entry': 'index.html',
    'api_version': 1,
  };

  test('合法 ui.pkg → 无错误', () {
    final pkg = pkgWith(validV3Manifest, <String, String>{
      'index.html': '<html/>',
      'style.css': 'body{}',
    });
    expect(UiPackageValidator.validate(pkg), isEmpty);
  });

  test('损坏的包 → corrupted', () {
    final errors = UiPackageValidator.validate(Uint8List.fromList(<int>[1, 2, 3]));
    expect(errors.single, contains('corrupted'));
  });

  test('缺 manifest.json → Missing manifest', () {
    final pkg = UiPackage.pack(<String, Uint8List>{
      'index.html': Uint8List.fromList(utf8.encode('<html/>')),
    });
    expect(UiPackageValidator.validate(pkg), contains('Missing manifest.json'));
  });

  test('entry 不存在 → entry not found', () {
    final pkg = pkgWith(validV3Manifest, <String, String>{'other.html': 'x'});
    expect(
      UiPackageValidator.validate(pkg),
      contains('UI package entry not found: index.html'),
    );
  });

  test('协议版本不匹配 → Protocol version mismatch', () {
    final pkg = pkgWith(
      <String, dynamic>{...validV3Manifest, 'protocol': <String, dynamic>{'version': 9}},
      <String, String>{'index.html': 'x'},
    );
    expect(
      UiPackageValidator.validate(pkg),
      contains('Protocol version mismatch: package=9, expected=1'),
    );
  });

  test('非法 manifest → Invalid manifest', () {
    final pkg = pkgWith(
      <String, dynamic>{'foo': 'bar'},
      <String, String>{'index.html': 'x'},
    );
    final errors = UiPackageValidator.validate(pkg);
    expect(errors.any((e) => e.startsWith('Invalid manifest')), isTrue);
  });

  test('非法路径 → Illegal path', () {
    final pkg = UiPackage.pack(<String, Uint8List>{
      'manifest.json': Uint8List.fromList(utf8.encode(jsonEncode(validV3Manifest))),
      'index.html': Uint8List.fromList(utf8.encode('x')),
      '../evil.txt': Uint8List.fromList(utf8.encode('bad')),
    });
    expect(
      UiPackageValidator.validate(pkg),
      contains('Illegal path in package: ../evil.txt'),
    );
  });
}
