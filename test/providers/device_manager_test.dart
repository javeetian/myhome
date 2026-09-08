import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/connection_phase.dart';
import 'package:myhome/device/device_session.dart';
import 'package:myhome/providers/device_manager_provider.dart';

/// 多设备会话记录 (WORK_V2 §22 数据层) 测试。
void main() {
  test('upsert / remove / 多设备记录', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final manager = container.read(deviceManagerProvider.notifier);

    expect(container.read(deviceManagerProvider), isEmpty);

    manager.upsert(const DeviceSession(
      phase: ConnectionPhase.connected,
      deviceId: 'dev-a',
    ));
    manager.upsert(const DeviceSession(
      phase: ConnectionPhase.connected,
      deviceId: 'dev-b',
    ));

    final state = container.read(deviceManagerProvider);
    expect(state.length, 2);
    expect(state['dev-a']?.deviceId, 'dev-a');
    expect(manager.of('dev-b')?.phase, ConnectionPhase.connected);

    // 同设备 upsert 覆盖旧快照
    manager.upsert(const DeviceSession(
      phase: ConnectionPhase.disconnected,
      deviceId: 'dev-a',
    ));
    expect(manager.of('dev-a')?.phase, ConnectionPhase.disconnected);
    expect(state.length, 2);

    manager.remove('dev-b');
    expect(container.read(deviceManagerProvider).length, 1);
    expect(manager.of('dev-b'), isNull);
    expect(manager.of('dev-a'), isNotNull);
  });

  test('无 deviceId 的快照被忽略', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(deviceManagerProvider.notifier)
        .upsert(const DeviceSession.none());
    expect(container.read(deviceManagerProvider), isEmpty);
  });
}
