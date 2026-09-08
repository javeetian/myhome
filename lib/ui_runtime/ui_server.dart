import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../device/device_client.dart';
import '../device/device_manifest.dart';
import 'js_bridge.dart';
import 'ui_adapter.dart';

/// 本地 UI Server (WORK_V2 §13.1)：Shelf HTTP + WebSocket 服务器。
///
/// 安全 (§13.5)：
///   仅绑定 127.0.0.1；随机端口；随机 session token。
///   所有路由 (静态 / API / WS) 均挂在 `/s/<token>/` 前缀下 ——
///   设备页面全部使用相对路径即可自动携带 token，无需感知。
///   带 Origin 头的请求必须来自本机，否则 403。
///
/// 路由 (§13.2)：
///   `GET  /s/<token>/`                → index.html (Phase 9/10 接 UI Package)
///   `GET  /s/<token>/<文件>`          → 静态资源
///   `GET  /s/<token>/api/device`      → 设备信息
///   `GET  /s/<token>/api/state`       → 当前设备状态
///   `POST /s/<token>/api/command`     → 指令
///   `GET  /s/<token>/api/resource/*`  → Phase 10
///   `GET  /s/<token>/ws`              → WebSocket 推送
class UiServer {
  UiServer({
    required DeviceClient client,
    String? staticRoot,
    DeviceManifest? manifest,
  })  : _client = client,
        _adapter = UiAdapter(client, manifest: manifest),
        _staticRoot = staticRoot;

  final DeviceClient _client;
  final UiAdapter _adapter;

  /// 静态文件根目录 (Phase 9 起为 UI Package 缓存目录)。
  final String? _staticRoot;

  final Set<WebSocketChannel> _wsClients = <WebSocketChannel>{};

  HttpServer? _httpServer;
  String? _token;
  StreamSubscription<String>? _pushSub;

  /// 实际监听端口 (随机端口，启动后可用)。
  int? get port => _httpServer?.port;

  /// 页面入口 URL (含 token 路径前缀)，供 WebView 加载。
  String? get entryUrl {
    final server = _httpServer;
    final token = _token;
    if (server == null || token == null) {
      return null;
    }
    return 'http://127.0.0.1:${server.port}/s/$token/';
  }

  /// 启动：绑定 127.0.0.1 随机端口，生成 session token (§13.5)。
  Future<void> start() async {
    _token = _generateToken();
    // 设备推送 → 广播给所有 WebSocket 客户端
    _pushSub = _adapter.pushStream().listen(_broadcast);
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_router);
    _httpServer =
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
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
    _token = null;
  }

  /// 设备推送 → 广播给所有 WebSocket 客户端。
  /// 已关闭的通道在发送失败时惰性移除。
  void _broadcast(String message) {
    for (final channel in _wsClients.toList()) {
      try {
        channel.sink.add(message);
      } catch (_) {
        _wsClients.remove(channel);
      }
    }
  }

  static String _generateToken() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Response> _router(Request request) async {
    final prefix = '/s/$_token';
    // shelf 的 Request.url.path 是相对路径 (无前导 /)，这里统一归一化
    final rawPath = request.url.path;
    final path = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    if (path != prefix && !path.startsWith('$prefix/')) {
      return Response.notFound('not found'); // 无 token：404，不泄露细节
    }
    // Origin 校验 (§13.5)
    final origin = request.headers['origin'];
    if (origin != null && !_isLocalOrigin(origin)) {
      return Response.forbidden('origin not allowed');
    }
    final sub = path == prefix ? '' : path.substring(prefix.length + 1);
    switch (sub) {
      case 'ws':
        return _handleWs(request);
      case 'api/command':
        return _adapter.handleCommand(request);
      case 'api/state':
        return _adapter.handleState(request);
      case 'api/device':
        return _adapter.handleDeviceInfo(request);
      case 'api/manifest':
        return _adapter.handleManifest(request);
      default:
        if (sub == '__device_api.js') {
          return _serveDeviceApi();
        }
        if (sub == 'api/resource' || sub.startsWith('api/resource/')) {
          final resourcePath = sub.length > 'api/resource'.length
              ? sub.substring('api/resource'.length + 1)
              : '';
          return _handleResource(resourcePath);
        }
        return _handleStatic(sub);
    }
  }

  /// 资源 (WORK_V2 §27)：先查本地缓存，未命中向设备请求并落盘缓存。
  Future<Response> _handleResource(String resourcePath) async {
    if (resourcePath.isEmpty) {
      return _jsonError(404, 5001, '缺少资源路径');
    }
    // 1. 本地命中 (UI Package 缓存)
    final local = _localFile(resourcePath);
    if (local != null) {
      return Response.ok(
        local.readAsBytesSync(),
        headers: <String, String>{'content-type': _contentType(resourcePath)},
      );
    }
    // 2. 设备回退：RESOURCE_REQUEST → 落盘 → 返回
    final root = _staticRoot;
    if (root == null) {
      return _jsonError(404, 5001, '资源不存在: $resourcePath');
    }
    try {
      final response = await _client.requestResource(resourcePath);
      if (!response.isOk || response.data == null) {
        return _jsonError(404, 5001, '资源不存在: $resourcePath');
      }
      final target = File(p.normalize(p.join(root, resourcePath)));
      if (!target.path.startsWith(root + p.separator)) {
        return Response.forbidden('forbidden');
      }
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(response.data!);
      return Response.ok(
        response.data!,
        headers: <String, String>{'content-type': _contentType(resourcePath)},
      );
    } catch (e) {
      return _jsonError(500, 5002, '资源下载失败: $e');
    }
  }

  /// 静态根目录下的安全文件查找。
  File? _localFile(String rel) {
    final root = _staticRoot;
    if (root == null) {
      return null;
    }
    final target = File(p.normalize(p.join(root, rel)));
    if (!target.path.startsWith(root + p.separator)) {
      return null; // 防目录穿越
    }
    return target.existsSync() ? target : null;
  }

  Response _jsonError(int statusCode, int code, String message) => Response(
        statusCode,
        body: jsonEncode(<String, dynamic>{
          'status': 'error',
          'error': <String, dynamic>{'code': code, 'message': message},
        }),
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );

  /// Device API Runtime 脚本 (Phase 9 §14.3/§14.5)，随页面相对路径引用。
  Response _serveDeviceApi() => Response.ok(
        deviceApiRuntimeJs,
        headers: <String, String>{
          'content-type': 'application/javascript; charset=utf-8',
          'cache-control': 'no-store',
        },
      );

  static bool _isLocalOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host ?? '';
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  /// 设备无 UI 包时的提示页 (纯协议调试模式)。
  static const String _noUiHtml = '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>无 UI</title></head>
<body style="font-family: sans-serif; padding: 24px; color: #555;">
  <h2>该设备未提供 UI 包</h2>
  <p>当前为纯协议调试模式：Protocol Console 与 Inspector 仍可正常使用。</p>
</body></html>
''';

  Handler get _handleWs => webSocketHandler(
        (WebSocketChannel channel, String? protocol) {
          // 注意：shelf_web_socket 已消费 channel.stream，
          // 推送由 _broadcast 统一分发 (见 start)。
          _wsClients.add(channel);
        },
      );

  /// 静态文件服务 (UI 包目录；Phase 9 正式接入)。
  Response _handleStatic(String rel) {
    final root = _staticRoot;
    if (root == null) {
      // 设备无 UI 包 (纯协议调试模式)：根路径给友好提示页而非空白 404
      if (rel.isEmpty) {
        return Response.ok(
          _noUiHtml,
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
        );
      }
      return Response.notFound('no static root');
    }
    final name = rel.isEmpty ? 'index.html' : rel;
    final target = p.normalize(p.join(root, name));
    // 防目录穿越
    if (target != root && !target.startsWith(root + p.separator)) {
      return Response.forbidden('forbidden');
    }
    final file = File(target);
    if (!file.existsSync()) {
      return Response.notFound('not found: $name');
    }
    var bytes = file.readAsBytesSync();
    final headers = <String, String>{'content-type': _contentType(name)};
    if (name.endsWith('.html')) {
      // 注入 Device API Runtime (Phase 9 §14.3/§14.5)：设备页面零样板代码
      bytes = utf8.encode(injectDeviceApi(utf8.decode(bytes)));
      headers['cache-control'] = 'no-store';
    }
    return Response.ok(bytes, headers: headers);
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
}
