import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhome/tools/release_samples.dart';
import 'package:path/path.dart' as p;

/// 发布包随附源码 (使用文档 §7)：sdk/device + 示例工程 → Release/samples/。
void main() {
  late Directory temp;
  late Directory release;
  late Directory sdkDevice;
  late Directory light1;

  void write(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('release_samples_test_');
    release = Directory(p.join(temp.path, 'Release'))..createSync();
    write(p.join(release.path, 'myhome.exe'), 'exe');

    sdkDevice = Directory(p.join(temp.path, 'sdk', 'device'));
    write(p.join(sdkDevice.path, 'core', 'protocol', 'crc16.c'), 'c');
    write(p.join(sdkDevice.path, 'hardware', 'hardware_adapter.h'), 'h');
    write(p.join(sdkDevice.path, 'build_test.bat'), 'bat');
    write(p.join(sdkDevice.path, 'README.md'), 'readme');
    // 开发机编译产物与仓库占位文件不该发给用户
    write(p.join(sdkDevice.path, 'crc16.obj'), 'obj');
    write(p.join(sdkDevice.path, 'test_sdk.exe'), 'exe');
    write(p.join(sdkDevice.path, '.gitkeep'), '');

    light1 = Directory(p.join(temp.path, 'light1'));
    write(p.join(light1.path, 'device.yaml'), 'yaml');
    write(p.join(light1.path, 'generated', 'c', 'device_api.c'), 'c');
    write(p.join(light1.path, 'build', 'ui.pkg'), 'pkg');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('shouldShip：编译产物与仓库占位文件不发，源码/文档都发', () {
    expect(ReleaseSamples.shouldShip('crc16.obj'), isFalse);
    expect(ReleaseSamples.shouldShip(r'core\crc16.obj'), isFalse);
    expect(ReleaseSamples.shouldShip('test_sdk.exe'), isFalse);
    expect(ReleaseSamples.shouldShip(r'test\test_sdk.pdb'), isFalse);
    expect(ReleaseSamples.shouldShip('.gitkeep'), isFalse);
    expect(ReleaseSamples.shouldShip(r'core\protocol\crc16.c'), isTrue);
    expect(ReleaseSamples.shouldShip('hardware_adapter.h'), isTrue);
    expect(ReleaseSamples.shouldShip(r'platform\jieli\myhome_glue.c'), isTrue);
    expect(ReleaseSamples.shouldShip('deploy_to_sdk.ps1'), isTrue);
    // 大小写不敏感 (Windows)
    expect(ReleaseSamples.shouldShip('CRC16.OBJ'), isFalse);
    // 名字里带 obj 但不是产物
    expect(ReleaseSamples.shouldShip('obj_notes.md'), isTrue);
  });

  test('stage：拷进 Release/samples/，目录结构保持，产物被过滤', () {
    final counts = ReleaseSamples.stage(
      releaseDir: release,
      sources: {'device_sdk': sdkDevice, 'light1': light1},
    );

    expect(counts['device_sdk'], 4); // crc16.c / hardware_adapter.h / build_test.bat / README.md
    expect(counts['light1'], 3); // device.yaml / generated/c/device_api.c / build/ui.pkg

    final samples = Directory(p.join(release.path, 'samples'));
    expect(File(p.join(samples.path, 'device_sdk', 'core', 'protocol', 'crc16.c'))
        .existsSync(), isTrue);
    expect(File(p.join(samples.path, 'device_sdk', 'crc16.obj')).existsSync(), isFalse);
    expect(File(p.join(samples.path, 'device_sdk', 'test_sdk.exe')).existsSync(), isFalse);
    expect(File(p.join(samples.path, 'device_sdk', '.gitkeep')).existsSync(), isFalse);
    expect(
        File(p.join(samples.path, 'light1', 'build', 'ui.pkg')).readAsStringSync(),
        'pkg');

    // 说明文件：CRLF，指向使用文档 §7
    final readme = File(p.join(samples.path, 'README.txt')).readAsStringSync();
    expect(readme, contains('device_sdk'));
    expect(readme, contains('light1'));
    expect(readme, contains('使用文档'));
    expect(readme, contains('\r\n'));

    // 原目录不动（是拷贝，不是搬运）
    expect(File(p.join(sdkDevice.path, 'crc16.obj')).existsSync(), isTrue);
  });

  test('stage：重复打包先删后拷，不留上一次的旧文件', () {
    ReleaseSamples.stage(releaseDir: release, sources: {'device_sdk': sdkDevice});
    final stale = File(p.join(release.path, 'samples', 'device_sdk', 'README.md'));
    expect(stale.existsSync(), isTrue);
    stale.deleteSync();

    ReleaseSamples.stage(releaseDir: release, sources: {'device_sdk': sdkDevice});
    expect(stale.existsSync(), isTrue, reason: '重跑要恢复，而不是留半套');
    expect(
      Directory(p.join(release.path, 'samples')).listSync().length,
      2, // device_sdk/ + README.txt
    );
  });
}
