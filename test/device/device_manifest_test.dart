import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_manifest.dart';

/// DeviceManifest (WORK_V2 §15.1/§24) 测试。
void main() {
  group('DeviceManifest 解析', () {
    test('全字段 fromJson (§15.1 示例)', () {
      final manifest = DeviceManifest.fromJson(<String, dynamic>{
        'protocol': 1,
        'ui_version': '1.2.3',
        'device': <String, dynamic>{'type': 'light', 'model': 'AC7014'},
        'entry': 'index.html',
        'capabilities': <String>['power', 'brightness', 'rgb'],
        'package': <String, dynamic>{'size': 183421, 'sha256': 'ab12cd'},
      });
      expect(manifest.protocol, 1);
      expect(manifest.uiVersion, '1.2.3');
      expect(manifest.deviceType, 'light');
      expect(manifest.deviceModel, 'AC7014');
      expect(manifest.entry, 'index.html');
      expect(manifest.capabilities, <String>['power', 'brightness', 'rgb']);
      expect(manifest.packageSize, 183421);
      expect(manifest.packageSha256, 'ab12cd');
    });

    test('最小 manifest (仅 protocol + ui_version)', () {
      final manifest = DeviceManifest.fromJson(<String, dynamic>{
        'protocol': 1,
        'ui_version': '2.0.0',
      });
      expect(manifest.deviceType, '');
      expect(manifest.entry, 'index.html');
      expect(manifest.capabilities, isEmpty);
      expect(manifest.packageSize, isNull);
    });

    test('缺 protocol → FormatException', () {
      expect(
        () => DeviceManifest.fromJson(<String, dynamic>{'ui_version': '1.0.0'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺 ui_version → FormatException', () {
      expect(
        () => DeviceManifest.fromJson(<String, dynamic>{'protocol': 1}),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson round-trip', () {
      const manifest = DeviceManifest(
        protocol: 1,
        uiVersion: '1.0.0',
        deviceType: 'light',
        deviceModel: 'demo-1',
        capabilities: <String>['power'],
      );
      final parsed = DeviceManifest.fromJson(manifest.toJson());
      expect(parsed.uiVersion, manifest.uiVersion);
      expect(parsed.deviceModel, manifest.deviceModel);
      expect(parsed.capabilities, manifest.capabilities);
    });
  });

  group('协议版本检查 (§24)', () {
    test('版本一致 → 通过', () {
      const manifest = DeviceManifest(protocol: 1, uiVersion: '1.0.0');
      expect(manifest.checkProtocolSupported, returnsNormally);
    });

    test('版本不一致 → UnsupportedProtocolError', () {
      const manifest = DeviceManifest(protocol: 99, uiVersion: '1.0.0');
      expect(
        manifest.checkProtocolSupported,
        throwsA(isA<UnsupportedProtocolError>()),
      );
    });
  });
}
