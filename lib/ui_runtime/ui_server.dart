import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../device/device_session.dart';
import 'ui_cache.dart';

/// 本地 UI Server：HTTP/WebSocket → [DeviceSession] (BLE/Mock)。
/// 即 FRAMEWORK_V2 中的 UI Adapter + Local HTTP Server (§17/§29)。
///
/// 路由：
///   GET  /            → UI 包 index.html
///   GET  /<文件>      → UI 包静态资源
///   POST /api/<路径>  → JSON 指令 → 设备
///   GET  /ws          → WebSocket (指令下行 + 状态上行)
class UiServer {
  UiServer(this._session);

  final DeviceSession _session;
  final Set<WebSocketChannel> _wsClients = <WebSocketChannel>{};

  HttpServer? _httpServer;
  StreamSubscription<Map<String, dynamic>>? _pushSub;
  String? _bundleRoot;

  /// 启动：初始化设备通道 → 解压 UI 包 → 监听端口。
  Future<void> start({required int port}) async {
    await _session.init();
    final gz = await _session.readUiBundle();
    final cache = await UiCache.extract(_session.name, gz);
    _bundleRoot = cache.rootDir;

    // 设备推送 → 转发给所有 WebSocket 客户端
    _pushSub = _session.pushes.listen(_broadcast);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_router);
    _httpServer =
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
  }

  Future<void> stop() async {
    await _pushSub?.cancel();
    _pushSub = null;
    for (final channel in _wsClients.toList()) {
      await channel.sink.close();
    }
    _wsClients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    _bundleRoot = null;
  }

  Future<Response> _router(Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' && (path == 'ws' || path == '/ws')) {
      return _wsHandler(request);
    }
    if (path == 'api' || path.startsWith('api/')) {
      return _handleApi(request);
    }
    return _handleStatic(request);
  }

  Handler get _wsHandler => webSocketHandler(
        (WebSocketChannel channel, String? protocol) {
          _wsClients.add(channel);
          channel.stream.listen(
            _onWsMessage,
            onDone: () => _wsClients.remove(channel),
            onError: (Object _) => _wsClients.remove(channel),
            cancelOnError: true,
          );
        },
      );

  /// 客户端 (WebView JS) 发来的 WS 消息 → 异步指令下发给设备。
  Future<void> _onWsMessage(dynamic data) async {
    try {
      final command = jsonDecode(data as String) as Map<String, dynamic>;
      await _session.sendCommand(command, sync: false);
    } catch (_) {
      // 单条消息失败不影响连接
    }
  }

  /// 设备主动推送 → 广播给所有 WebSocket 客户端。
  void _broadcast(Map<String, dynamic> push) {
    final message = jsonEncode(push);
    for (final channel in _wsClients.toList()) {
      try {
        channel.sink.add(message);
      } catch (_) {
        _wsClients.remove(channel);
      }
    }
  }

  /// Device API 指令入口：JSON body → 设备 → JSON 响应。
  Future<Response> _handleApi(Request request) async {
    final body = await request.readAsString();
    Map<String, dynamic> command;
    try {
      command = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      // HTMX 默认以表单编码提交，也兼容一下
      command = Uri.splitQueryString(body).map(
        (key, value) => MapEntry(key, value),
      );
    }
    command.putIfAbsent('id', () => DateTime.now().millisecondsSinceEpoch);
    final sync = command['mode'] != 'async';
    try {
      final result = await _session
          .sendCommand(command, sync: sync)
          .timeout(const Duration(seconds: 10));
      return _json(result);
    } catch (e) {
      return _json(<String, dynamic>{
        'type': 'response',
        'status': 'error',
        'error': e.toString(),
        'id': command['id'],
      });
    }
  }

  /// 静态文件服务 (UI 包解压目录)。
  Response _handleStatic(Request request) {
    final root = _bundleRoot;
    if (root == null) {
      return Response.notFound('UI bundle not loaded');
    }
    final rel = (request.url.path.isEmpty || request.url.path == '/')
        ? 'index.html'
        : request.url.path.substring(1);
    final target = p.normalize(p.join(root, rel));
    // 防目录穿越
    if (target != root && !target.startsWith(root + p.separator)) {
      return Response.forbidden('forbidden');
    }
    final file = File(target);
    if (!file.existsSync()) {
      return Response.notFound('not found: $rel');
    }
    return Response.ok(
      file.readAsBytesSync(),
      headers: <String, String>{'content-type': _contentType(rel)},
    );
  }

  String _contentType(String rel) {
    if (rel.endsWith('.html')) return 'text/html; charset=utf-8';
    if (rel.endsWith('.css')) return 'text/css; charset=utf-8';
    if (rel.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (rel.endsWith('.json')) return 'application/json; charset=utf-8';
    if (rel.endsWith('.png')) return 'image/png';
    if (rel.endsWith('.jpg') || rel.endsWith('.jpeg')) return 'image/jpeg';
    if (rel.endsWith('.svg')) return 'image/svg+xml';
    if (rel.endsWith('.woff2')) return 'font/woff2';
    return 'application/octet-stream';
  }

  Response _json(Object data) => Response.ok(
        jsonEncode(data),
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'access-control-allow-origin': '*',
        },
      );
}
