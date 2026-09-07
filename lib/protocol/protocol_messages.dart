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

/// 错误信息 (§10.5)，内嵌于 [DeviceResponse]。
class DeviceError {
  const DeviceError({required this.code, required this.message});

  final int code;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'message': message,
      };
}
