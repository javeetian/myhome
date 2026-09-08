import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/studio/device_list_controller.dart';

String deviceYaml(String id, String name, String model) => '''
device:
  id: $id
  name: $name
  model: $model

protocol:
  version: 1

api:
  version: 1

state: {}

commands: []

events: []
''';

void main() {
  late Directory root;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('device_list_test_');
    container = ProviderContainer(
      overrides: [
        deviceListProvider
            .overrideWith(() => DeviceListController(devicesRoot: root)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  Directory makeDevice(String id, {String name = 'N', String model = 'M'}) {
    final dir = Directory(p.join(root.path, id))..createSync();
    File(p.join(dir.path, 'device.yaml'))
        .writeAsStringSync(deviceYaml(id, name, model));
    return dir;
  }

  DeviceListController controller() =>
      container.read(deviceListProvider.notifier);

  test('扫描：列出含 device.yaml 的目录 (按名排序)', () {
    makeDevice('b_dev');
    makeDevice('a_dev');

    final list = container.read(deviceListProvider);

    expect(list.map((d) => d.dirName).toList(), <String>['a_dev', 'b_dev']);
    expect(list.first.definition?.id, 'a_dev');
    expect(list.first.isValid, isTrue);
  });

  test('扫描：.removed 标记的目录不显示', () {
    makeDevice('visible');
    makeDevice('hidden');
    File(p.join(root.path, 'hidden', '.removed')).writeAsStringSync('');

    final list = container.read(deviceListProvider);

    expect(list.map((d) => d.dirName), <String>['visible']);
  });

  test('扫描：无 device.yaml 的目录不算设备', () {
    Directory(p.join(root.path, 'not_a_device')).createSync();

    expect(container.read(deviceListProvider), isEmpty);
  });

  test('扫描：坏 device.yaml 的目录显示并带错误信息', () {
    final dir = Directory(p.join(root.path, 'broken'))..createSync();
    File(p.join(dir.path, 'device.yaml')).writeAsStringSync('device: [bad');

    final list = container.read(deviceListProvider);

    expect(list, hasLength(1));
    expect(list.single.isValid, isFalse);
    expect(list.single.error, isNotNull);
  });

  test('remove：写入 .removed 标记，目录保留，列表移除', () {
    final dir = makeDevice('gone');
    final info = container.read(deviceListProvider).single;

    controller().remove(info);

    expect(container.read(deviceListProvider), isEmpty);
    expect(dir.existsSync(), isTrue, reason: '目录保留');
    expect(File(p.join(dir.path, '.removed')).existsSync(), isTrue);
  });

  test('delete：目录被递归删除且列表移除', () {
    final dir = makeDevice('doomed');
    final info = container.read(deviceListProvider).single;

    controller().delete(info);

    expect(container.read(deviceListProvider), isEmpty);
    expect(dir.existsSync(), isFalse);
  });

  test('create：生成 devices/<id>/device.yaml 并出现在列表', () {
    final error = controller().createDevice(
      id: 'new_light',
      name: 'New Light',
      model: 'N100',
    );

    expect(error, isNull);
    final yaml = File(p.join(root.path, 'new_light', 'device.yaml'));
    expect(yaml.existsSync(), isTrue);
    expect(yaml.readAsStringSync(), contains('id: new_light'));
    expect(yaml.readAsStringSync(), contains('name: New Light'));

    final list = container.read(deviceListProvider);
    expect(list.single.definition?.name, 'New Light');
    expect(list.single.definition?.model, 'N100');
  });

  test('create：非法 ID 返回错误', () {
    expect(
      controller().createDevice(id: 'Bad-Id', name: 'X', model: 'Y'),
      contains('ID'),
    );
    expect(
      controller().createDevice(id: '1bad', name: 'X', model: 'Y'),
      contains('ID'),
    );
  });

  test('create：目录已存在返回错误', () {
    makeDevice('dup');
    expect(
      controller().createDevice(id: 'dup', name: 'X', model: 'Y'),
      contains('已存在'),
    );
  });

  test('importDevice：devices/ 内已移除的目录恢复显示', () {
    makeDevice('a');
    File(p.join(root.path, 'a', '.removed')).writeAsStringSync('');
    expect(container.read(deviceListProvider), isEmpty);

    expect(controller().importDevice(p.join(root.path, 'a')), isNull);

    expect(container.read(deviceListProvider), hasLength(1));
    expect(
      File(p.join(root.path, 'a', '.removed')).existsSync(),
      isFalse,
      reason: '.removed 标记被删除 (恢复显示)',
    );
  });

  test('importDevice：外部目录加入导入列表并持久化', () {
    final ext = Directory.systemTemp.createTempSync('ext_dev_');
    File(p.join(ext.path, 'device.yaml'))
        .writeAsStringSync(deviceYaml('ext_dev', 'Ext Dev', 'X1'));
    addTearDown(() => ext.deleteSync(recursive: true));

    expect(controller().importDevice(ext.path), isNull);

    final list = container.read(deviceListProvider);
    expect(list.single.definition?.name, 'Ext Dev');

    // 持久化：新容器重新扫描仍包含导入目录
    final container2 = ProviderContainer(
      overrides: [
        deviceListProvider
            .overrideWith(() => DeviceListController(devicesRoot: root)),
      ],
    );
    addTearDown(container2.dispose);
    expect(
      container2.read(deviceListProvider).single.dirPath,
      ext.path,
    );
  });

  test('importDevice：所选目录不含 device.yaml → 错误', () {
    final plain = Directory.systemTemp.createTempSync('plain_dir_');
    addTearDown(() => plain.deleteSync(recursive: true));

    expect(controller().importDevice(plain.path), contains('device.yaml'));
  });

  test('importDevice：外部导入的目录被移除标记后不显示', () {
    final ext = Directory.systemTemp.createTempSync('ext_dev2_');
    File(p.join(ext.path, 'device.yaml'))
        .writeAsStringSync(deviceYaml('ext_dev2', 'Ext Dev 2', 'X2'));
    addTearDown(() => ext.deleteSync(recursive: true));
    expect(controller().importDevice(ext.path), isNull);

    final info = container.read(deviceListProvider).single;
    controller().remove(info);

    expect(container.read(deviceListProvider), isEmpty);
    expect(
      File(p.join(ext.path, '.removed')).existsSync(),
      isTrue,
    );
  });

  test('pickAndImport：picker 返回 null → 用户取消', () async {
    final testContainer = ProviderContainer(
      overrides: [
        deviceListProvider.overrideWith(
          () => DeviceListController(
            devicesRoot: root,
            picker: () async => null,
          ),
        ),
      ],
    );
    addTearDown(testContainer.dispose);

    final result = await testContainer
        .read(deviceListProvider.notifier)
        .pickAndImport();

    expect(result, isNull);
    expect(testContainer.read(deviceListProvider), isEmpty);
  });
}
