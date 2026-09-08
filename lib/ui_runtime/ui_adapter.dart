import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../device/device_client.dart';
import '../device/device_manifest.dart';
import '../protocol/protocol_messages.dart';

/// UI Adapter (WORK_V2 §13.3/§13.4)：HTTP/WS 语义 → [DeviceClient]。
///
/// ```text
/// HTTP → Router → UiAdapter → DeviceClient → Protocol → BLE
/// ```
/// WebView 只理解 HTTP / WebSocket / JavaScript (§14.3)，
/// 不知道 BLE 的存在 —— 本类就是这道边界。
class UiAdapter {
  UiAdapter(this._client, {DeviceManifest? manifest}) : _manifest = manifest;

  final DeviceClient _client;

  /// 设备 manifest (§15.1，经 UiRuntime 加载后传入)。
  final DeviceManifest? _manifest;

  /// POST /api/command：JSON {cmd, params} → DeviceClient.command()。
  ///
  /// 设备业务错误 (status='error') 正常返回 200 (设备确实响应了)；
  /// 传输失败 / 响应超时 → 500 (2xxx 设备错误, §10.5)。
  Future<Response> handleCommand(Request request) async {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _errorResponse(400, ProtocolErrorCodes.invalidParameter, '请求体必须是 JSON 对象');
    }
    final cmd = json['cmd'];
    if (cmd is! String || cmd.isEmpty) {
      return _errorResponse(400, ProtocolErrorCodes.invalidParameter, '缺少 cmd 字段');
    }
    final rawParams = json['params'];
    if (rawParams != null && rawParams is! Map<String, dynamic>) {
      return _errorResponse(400, ProtocolErrorCodes.invalidParameter, 'params 必须是对象');
    }
    final params = rawParams == null
        ? const <String, dynamic>{}
        : rawParams as Map<String, dynamic>;
    try {
      final response = await _client.command(cmd, params);
      return _json(<String, dynamic>{
        'status': response.status,
        'request_id': response.requestId,
        'data': response.data,
        'error': response.error?.toJson(),
      });
    } catch (e) {
      return _errorResponse(500, 2002, '设备通信失败: $e');
    }
  }

  /// GET /api/state：当前设备状态 (§16.6 未同步时主动拉取)。
  Future<Response> handleState(Request request) async {
    try {
      final state = await _client.getState();
      return _json(<String, dynamic>{
        'version': state.version,
        'state': state.state,
      });
    } catch (e) {
      return _errorResponse(404, 2002, '状态不可用: $e');
    }
  }

  /// GET /api/device：设备基本信息 + manifest (§15.1/§25)。
  /// HELLO_ACK 字段来自握手结果 (§39)；manifest 经 UiRuntime 加载后提供。
  Response handleDeviceInfo(Request request) => _json(<String, dynamic>{
        'device_id': _client.deviceId,
        'protocol': _client.helloAck?.protocolVersion ?? 1,
        'connected': _client.isConnected,
        if (_client.helloAck != null) ...<String, dynamic>{
          'device': <String, dynamic>{
            'type': _client.helloAck!.deviceType,
            'model': _client.helloAck!.deviceModel,
          },
          'firmware_version': _client.helloAck!.firmwareVersion,
          'ui_version': _client.helloAck!.uiVersion,
          'capabilities': _client.helloAck!.capabilities,
        },
        if (_manifest != null) ...<String, dynamic>{
          'entry': _manifest.entry,
        },
      });

  /// WS /ws：设备主动推送 (state/event/patch) → WebView (§14.4)。
  ///
  /// Phase 8 为单向推送；WebView → 设备请走 POST /api/command。
  /// 由 UiServer 在启动时订阅 (onListen)、停止时释放 (onCancel)，
  /// 广播给所有 WS 客户端。
  /// 注意：shelf_web_socket 已消费 channel.stream，服务端不能再 listen。
  Stream<String> pushStream() {
    final subs = <StreamSubscription<dynamic>>[];
    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        subs.add(_client.events.listen((event) => controller.add(jsonEncode(<String, dynamic>{
              'type': 'event',
              'event': event.event,
              'data': event.data,
            }))));
        subs.add(_client.patches.listen((patch) => controller.add(jsonEncode(<String, dynamic>{
              'type': 'patch',
              'version': patch.version,
              'ops': patch.ops,
            }))));
        subs.add(_client.states.listen((state) => controller.add(jsonEncode(<String, dynamic>{
              'type': 'state',
              'version': state.version,
              'state': state.state,
            }))));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  Response _errorResponse(int statusCode, int code, String message) =>
      _json(<String, dynamic>{
        'status': 'error',
        'error': <String, dynamic>{'code': code, 'message': message},
      }, statusCode: statusCode);

  Response _json(Object data, {int statusCode = 200}) => Response(
        statusCode,
        body: jsonEncode(data),
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        },
      );
}
