import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../core/constants.dart';
import '../device/device_session.dart';

/// 基于 BLE GATT 的 [DeviceSession] 实现 (flutter_reactive_ble)：
/// 指令 → 写入特征值；响应/推送 ← Notify 特征值。
///
/// 对应 FRAMEWORK_V2 §46 BleTransport。Phase 1 直接实现 [DeviceSession]；
/// 后续按 §9 拆出 DeviceClient 层 (Command/Response/Event 封装)。
class BleTransport implements DeviceSession {
  BleTransport(this._device);

  final DiscoveredDevice _device;

  final StreamController<Map<String, dynamic>> _pushController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// 等待响应的同步指令，按 id 索引。
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};

  /// FRB 断开连接的方式是取消连接流订阅，必须持有句柄。
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  FlutterReactiveBle? _bleInstance;

  FlutterReactiveBle get _ble {
    if (_bleInstance != null) {
      return _bleInstance!;
    }
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      throw StateError('当前平台不支持 BLE');
    }
    return _bleInstance = FlutterReactiveBle();
  }

  static final Uuid _serviceUuid = Uuid.parse(AppConstants.serviceUuid);
  static final Uuid _writeCharUuid = Uuid.parse(AppConstants.writeCharUuid);
  static final Uuid _notifyCharUuid = Uuid.parse(AppConstants.notifyCharUuid);
  static final Uuid _uiCharUuid = Uuid.parse(AppConstants.uiBundleCharUuid);

  int _seq = 0;
  bool _inited = false;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  String get name => _device.name.isNotEmpty ? _device.name : _device.id;

  QualifiedCharacteristic _char(Uuid uuid) => QualifiedCharacteristic(
        characteristicId: uuid,
        serviceId: _serviceUuid,
        deviceId: _device.id,
      );

  @override
  Future<void> init() async {
    if (_inited) {
      return;
    }
    _inited = true;

    // 1. 连接 (保持订阅，取消订阅 = 断开)
    final connected = Completer<void>();
    _connSub = _ble
        .connectToDevice(
          id: _device.id,
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _connected = true;
                if (!connected.isCompleted) {
                  connected.complete();
                }
              case DeviceConnectionState.disconnected:
                _connected = false;
                _pushController.add(<String, dynamic>{
                  'type': 'push',
                  'data': <String, dynamic>{'disconnected': true},
                });
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object e) {
            if (!connected.isCompleted) {
              connected.completeError(e);
            }
          },
        );
    await connected.future.timeout(const Duration(seconds: 20), onTimeout: () {
      throw TimeoutException('设备连接超时');
    });

    // 2. MTU 协商 (失败不阻塞)
    try {
      await _ble.requestMtu(deviceId: _device.id, mtu: 247);
    } catch (_) {
      // 部分平台不支持，忽略
    }

    // 3. 校验目标 GATT 特征存在
    await _ble.discoverAllServices(_device.id);
    final services = await _ble.getDiscoveredServices(_device.id);
    final hasTarget = services.any(
      (s) =>
          s.id == _serviceUuid &&
          s.characteristics.any((c) => c.id == _writeCharUuid),
    );
    if (!hasTarget) {
      throw StateError('设备缺少目标 GATT 特征 (service: ${AppConstants.serviceUuid})');
    }

    // 4. 订阅 Notify
    _notifySub = _ble
        .subscribeToCharacteristic(_char(_notifyCharUuid))
        .listen(_onNotify);
  }

  void _onNotify(List<int> data) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (_) {
      return; // TODO: 粘包/分片重组 (\x02...\x03 起止标记)
    }
    final id = msg['id'];
    if (msg['type'] == 'response' && id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    } else {
      _pushController.add(msg);
    }
  }

  @override
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> command, {
    bool sync = true,
  }) async {
    final rawId = command['id'];
    final id = rawId is int ? rawId : _seq++;
    final envelope = <String, dynamic>{...command, 'id': id};

    // TODO: 超过 MTU (~247B) 时按 \x02/\x03 标记分片
    List<int> payload = utf8.encode(jsonEncode(envelope));
    if (payload.length > 200) {
      payload = <int>[0x02, ...payload, 0x03];
    }

    Completer<Map<String, dynamic>>? completer;
    if (sync) {
      completer = Completer<Map<String, dynamic>>();
      _pending[id] = completer;
    }
    await _ble.writeCharacteristicWithResponse(_char(_writeCharUuid), value: payload);
    if (!sync) {
      return <String, dynamic>{
        'type': 'response',
        'status': 'ok',
        'id': id,
        'data': <String, dynamic>{},
      };
    }
    return completer!.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('设备响应超时 (id=$id)');
    });
  }

  @override
  Future<Uint8List> readUiBundle() async {
    // TODO: 大文件需分片读取并拼接
    final bytes = await _ble.readCharacteristic(_char(_uiCharUuid));
    return Uint8List.fromList(bytes);
  }

  @override
  Stream<Map<String, dynamic>> get pushes => _pushController.stream;

  @override
  Future<void> dispose() async {
    _connected = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel(); // 取消连接流订阅 = 断开 BLE
    _connSub = null;
    await _pushController.close();
  }
}
