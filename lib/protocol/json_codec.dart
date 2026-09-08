import 'dart:convert';

import 'ble_frame.dart';
import 'codec.dart';
import 'protocol_messages.dart';

/// JSON 编解码 (WORK_V2 §10.6 第一版)。
///
/// 字段名与 §10.2-10.5 示例逐字对齐：
///   request_id / cmd / params / status / data / error{code,message}
///   event / state{version,state} / patch{type,version,ops}
class JsonCodec implements MessageCodec {
  const JsonCodec();

  @override
  List<int> encode(ProtocolMessage message) {
    final Object json = switch (message) {
      DeviceCommand m => <String, dynamic>{
          'request_id': m.requestId,
          'cmd': m.cmd,
          'params': m.params,
        },
      DeviceResponse m => <String, dynamic>{
          'request_id': m.requestId,
          'status': m.status,
          if (m.data != null) 'data': m.data,
          if (m.error != null) 'error': m.error!.toJson(),
        },
      DeviceEvent m => <String, dynamic>{'event': m.event, 'data': m.data},
      DeviceState m => <String, dynamic>{'version': m.version, 'state': m.state},
      DevicePatch m => <String, dynamic>{
          'type': 'patch',
          'version': m.version,
          'ops': m.ops,
        },
      DeviceHello m => <String, dynamic>{
          'request_id': m.requestId,
          'protocol_version': m.protocolVersion,
        },
      DeviceHelloAck m => <String, dynamic>{
          'request_id': m.requestId,
          'protocol_version': m.protocolVersion,
          'device_type': m.deviceType,
          'device_model': m.deviceModel,
          'firmware_version': m.firmwareVersion,
          'ui_version': m.uiVersion,
          'capabilities': m.capabilities,
        },
      DeviceResourceRequest m => <String, dynamic>{
          'request_id': m.requestId,
          'path': m.path,
        },
      DeviceResourceResponse m => <String, dynamic>{
          'request_id': m.requestId,
          'status': m.status,
          if (m.data != null) 'data': base64Encode(m.data!),
          if (m.error != null) 'error': m.error!.toJson(),
        },
    };
    return utf8.encode(jsonEncode(json));
  }

  @override
  ProtocolMessage decode(int frameType, List<int> data) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException catch (e) {
      throw ProtocolException('JSON 解析失败: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw ProtocolException('JSON 顶层必须是对象');
    }
    return switch (frameType) {
      FrameType.command => _decodeCommand(json),
      FrameType.response => _decodeResponse(json),
      FrameType.event => DeviceEvent(
          event: _requireString(json, 'event'),
          data: _optionalMap(json, 'data'),
        ),
      FrameType.state => DeviceState(
          version: _requireInt(json, 'version'),
          state: _requireMap(json, 'state'),
        ),
      FrameType.patch => DevicePatch(
          version: _requireInt(json, 'version'),
          ops: _requireList(json, 'ops'),
        ),
      FrameType.hello => DeviceHello(
          requestId: _requireInt(json, 'request_id'),
          protocolVersion: _optionalInt(json, 'protocol_version') ?? 1,
        ),
      FrameType.helloAck => DeviceHelloAck(
          requestId: _requireInt(json, 'request_id'),
          protocolVersion: _optionalInt(json, 'protocol_version') ?? 1,
          deviceType: _optionalString(json, 'device_type') ?? '',
          deviceModel: _optionalString(json, 'device_model') ?? '',
          firmwareVersion: _optionalString(json, 'firmware_version') ?? '',
          uiVersion: _optionalString(json, 'ui_version') ?? '',
          capabilities: _optionalStringList(json, 'capabilities'),
        ),
      FrameType.resourceRequest => DeviceResourceRequest(
          requestId: _requireInt(json, 'request_id'),
          path: _requireString(json, 'path'),
        ),
      FrameType.resourceResponse => DeviceResourceResponse(
          requestId: _requireInt(json, 'request_id'),
          status: _requireString(json, 'status'),
          data: json['data'] is String ? base64Decode(json['data'] as String) : null,
          error: _optionalError(json),
        ),
      _ => throw ProtocolException(
          '非业务帧类型: 0x${frameType.toRadixString(16).padLeft(2, '0')}',
        ),
    };
  }

  DeviceCommand _decodeCommand(Map<String, dynamic> json) => DeviceCommand(
        requestId: _requireInt(json, 'request_id'),
        cmd: _requireString(json, 'cmd'),
        params: _optionalMap(json, 'params'),
      );

  DeviceResponse _decodeResponse(Map<String, dynamic> json) {
    final errorJson = json['error'];
    return DeviceResponse(
      requestId: _requireInt(json, 'request_id'),
      status: _requireString(json, 'status'),
      data: _optionalMap(json, 'data'),
      error: errorJson is Map<String, dynamic>
          ? DeviceError(
              code: _requireInt(errorJson, 'code'),
              message: _requireString(errorJson, 'message'),
            )
          : null,
    );
  }

  int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw ProtocolException('字段 $key 缺失或非整数: $value');
    }
    return value;
  }

  int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is int ? value : null;
  }

  String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  List<String> _optionalStringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) {
      return const <String>[];
    }
    return value.map((e) {
      if (e is! String) {
        throw ProtocolException('字段 $key 的元素必须是字符串: $e');
      }
      return e;
    }).toList();
  }

  DeviceError? _optionalError(Map<String, dynamic> json) {
    final errorJson = json['error'];
    if (errorJson is! Map<String, dynamic>) {
      return null;
    }
    return DeviceError(
      code: _requireInt(errorJson, 'code'),
      message: _requireString(errorJson, 'message'),
    );
  }

  String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw ProtocolException('字段 $key 缺失或非字符串: $value');
    }
    return value;
  }

  Map<String, dynamic> _requireMap(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! Map<String, dynamic>) {
      throw ProtocolException('字段 $key 缺失或非对象: $value');
    }
    return value;
  }

  List<Map<String, dynamic>> _requireList(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List) {
      throw ProtocolException('字段 $key 缺失或非数组: $value');
    }
    return value.map((e) {
      if (e is! Map<String, dynamic>) {
        throw ProtocolException('字段 $key 的元素必须是对象: $e');
      }
      return e;
    }).toList();
  }

  Map<String, dynamic> _optionalMap(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return const <String, dynamic>{};
    }
    if (value is! Map<String, dynamic>) {
      throw ProtocolException('字段 $key 非对象: $value');
    }
    return value;
  }
}
