import 'dart:typed_data';

import 'ble_frame.dart';

/// 协议层异常 (编解码/字段校验失败)。
class ProtocolException implements Exception {
  const ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

/// 统一错误码 (WORK_V2 §10.5)。固件侧需对齐。
class ProtocolErrorCodes {
  ProtocolErrorCodes._();

  /// 无效参数 (doc 示例值)。
  static const int invalidParameter = 3001;

  /// 未知命令。
  static const int unknownCommand = 3002;

  /// 设备忙。
  static const int busy = 3003;

  /// 不支持的能力。
  static const int notSupported = 3004;
}

/// 设备协议消息模型 (WORK_V2 §10)。
///
/// 消息类型由 Frame TYPE 字节区分 (§10.1)，JSON 体内不重复类型字段
/// (PATCH 的 "type":"patch" 按 §16.3 示例保留，供固件对齐)。
sealed class ProtocolMessage {
  const ProtocolMessage();

  /// 对应 [FrameType] 值。
  int get frameType;
}

/// 指令 (WORK_V2 §10.2)。
class DeviceCommand extends ProtocolMessage {
  const DeviceCommand({
    required this.requestId,
    required this.cmd,
    this.params = const <String, dynamic>{},
  });

  final int requestId;
  final String cmd;
  final Map<String, dynamic> params;

  @override
  int get frameType => FrameType.command;
}

/// 指令响应 (WORK_V2 §10.3/§10.5)。status = 'ok' | 'error'。
class DeviceResponse extends ProtocolMessage {
  const DeviceResponse({
    required this.requestId,
    this.status = 'ok',
    this.data,
    this.error,
  });

  final int requestId;
  final String status;
  final Map<String, dynamic>? data;
  final DeviceError? error;

  bool get isOk => status == 'ok' && error == null;

  @override
  int get frameType => FrameType.response;
}

/// 设备主动事件 (WORK_V2 §10.4)。
class DeviceEvent extends ProtocolMessage {
  const DeviceEvent({required this.event, this.data = const <String, dynamic>{}});

  final String event;
  final Map<String, dynamic> data;

  @override
  int get frameType => FrameType.event;
}

/// 全量状态 (WORK_V2 §10.1；版本语义 Phase 11 §16.2 完善)。
class DeviceState extends ProtocolMessage {
  const DeviceState({required this.version, required this.state});

  final int version;
  final Map<String, dynamic> state;

  @override
  int get frameType => FrameType.state;
}

/// 状态补丁 (WORK_V2 §16.3；Gap 检测等语义 Phase 11 完善)。
class DevicePatch extends ProtocolMessage {
  const DevicePatch({required this.version, required this.ops});

  final int version;

  /// JSON Patch 风格操作列表：[{'op': 'replace', 'path': '/brightness', 'value': 60}]
  final List<Map<String, dynamic>> ops;

  @override
  int get frameType => FrameType.patch;
}

/// 错误信息 (§10.5)，内嵌于 [DeviceResponse] / [DeviceResourceResponse]。
class DeviceError {
  const DeviceError({required this.code, required this.message});

  final int code;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'message': message,
      };
}

/// HELLO 握手 (App → 设备, WORK_V2 §39/§15.3)。
/// request_id 用于应用层配对 (与 Transport SEQ 分离, §14)。
class DeviceHello extends ProtocolMessage {
  const DeviceHello({required this.requestId, this.protocolVersion = 1});

  final int requestId;
  final int protocolVersion;

  @override
  int get frameType => FrameType.hello;
}

/// HELLO_ACK (设备 → App, §39)：设备能力与 UI 版本声明。
class DeviceHelloAck extends ProtocolMessage {
  const DeviceHelloAck({
    required this.requestId,
    this.protocolVersion = 1,
    this.deviceType = '',
    this.deviceModel = '',
    this.firmwareVersion = '',
    this.uiVersion = '',
    this.capabilities = const <String>[],
  });

  final int requestId;
  final int protocolVersion;
  final String deviceType;
  final String deviceModel;
  final String firmwareVersion;
  final String uiVersion;
  final List<String> capabilities;

  @override
  int get frameType => FrameType.helloAck;
}

/// 资源请求 (App → 设备, §27)：按路径请求 manifest.json / ui.pkg 等。
class DeviceResourceRequest extends ProtocolMessage {
  const DeviceResourceRequest({required this.requestId, required this.path});

  final int requestId;
  final String path;

  @override
  int get frameType => FrameType.resourceRequest;
}

/// 资源响应 (设备 → App, §27)。
/// MVP 数据以 base64 内嵌 JSON (§46 第一阶段)；正式版换二进制编码。
class DeviceResourceResponse extends ProtocolMessage {
  const DeviceResourceResponse({
    required this.requestId,
    this.status = 'ok',
    this.data,
    this.error,
  });

  final int requestId;
  final String status;
  final Uint8List? data;
  final DeviceError? error;

  bool get isOk => status == 'ok' && error == null;

  @override
  int get frameType => FrameType.resourceResponse;
}
