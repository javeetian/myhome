import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../device/device_manifest.dart';
import 'ui_package.dart';

/// UI Package 校验器 (WORK_V3 Phase 14)。
///
/// 检查 (WORK_V3 §18)：
///   manifest 合法性 / entry 存在 / protocol 版本匹配 / required files / 路径安全。
/// 错误一次性收集，每条消息明确可读。
class UiPackageValidator {
  UiPackageValidator._();

  /// 校验 [pkgBytes]；[definition] 提供时做协议版本一致性检查。
  /// 返回错误列表 (空 = 合法)。
  static List<String> validate(
    Uint8List pkgBytes, {
    int expectedProtocol = DeviceManifest.supportedProtocol,
  }) {
    final errors = <String>[];

    // 1. 解包 (tar.gz)
    final Map<String, Uint8List> files;
    try {
      files = UiPackage.unpack(pkgBytes);
    } catch (e) {
      return <String>['UI package is corrupted: $e'];
    }

    // 2. manifest.json
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null) {
      errors.add('Missing manifest.json');
    } else {
      try {
        final manifest = DeviceManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>,
        );
        // 3. entry 存在
        if (!files.containsKey(manifest.entry)) {
          errors.add('UI package entry not found: ${manifest.entry}');
        }
        // 4. 协议版本
        if (manifest.protocol != expectedProtocol) {
          errors.add(
            'Protocol version mismatch: package=${manifest.protocol}, '
            'expected=$expectedProtocol',
          );
        }
        // 5. hash 校验 (声明了必须匹配)
        if (manifest.packageSha256 != null) {
          final actual = sha256.convert(pkgBytes).toString();
          if (actual != manifest.packageSha256) {
            errors.add('Hash mismatch: manifest=${manifest.packageSha256}, '
                'actual=$actual');
          }
        }
      } catch (e) {
        errors.add('Invalid manifest: $e');
      }
    }

    // 6. 路径安全
    for (final name in files.keys) {
      if (name.contains('..') || name.startsWith('/') || name.contains('\\')) {
        errors.add('Illegal path in package: $name');
      }
    }

    return errors;
  }
}
