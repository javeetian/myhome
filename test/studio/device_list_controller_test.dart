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

  test('allDeviceDirs：包含被移除的目录 (供"打开"选择)', () {
    makeDevice('a');
    makeDevice('b');
    File(p.join(root.path, 'b', '.removed')).writeAsStringSync('');

    final dirs = controller().allDeviceDirs();

    expect(dirs.map(p.basename), containsAll(<String>['a', 'b']));
  });

  test('openDir：调用注入的 opener', () async {
    final opened = <String>[];
    final testContainer = ProviderContainer(
      overrides: [
        deviceListProvider.overrideWith(
          () => DeviceListController(
            devicesRoot: root,
            opener: (path) async => opened.add(path),
          ),
        ),
      ],
    );
    addTearDown(testContainer.dispose);

    await testContainer
        .read(deviceListProvider.notifier)
        .openDir('/some/device/dir');

    expect(opened, <String>['/some/device/dir']);
  });
}
