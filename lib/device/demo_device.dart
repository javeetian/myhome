import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../ble/ble_peripheral.dart';
import '../ble/ble_transport.dart';
import '../protocol/ble_frame.dart';
import '../protocol/fragment.dart';
import '../protocol/frame_sequencer.dart';
import '../protocol/frame_stream_decoder.dart';
import '../protocol/json_codec.dart';
import '../protocol/protocol_messages.dart';
import '../ui_runtime/ui_package.dart';

/// 演示设备 (WORK_V2 §30 硬件到位前的替代)：
/// 复用本项目自己的协议栈 (解码 / 组装 / 编解码) 模拟一台真实设备 ——
/// App 的 [DeviceClient] 走完整 BLE 协议链路，只是传输介质是本进程内回环。
///
/// Phase 10 起演示设备完整走官方协议流程：
///   HELLO → HELLO_ACK (设备能力 / UI 版本声明)
///   RESOURCE_REQUEST manifest.json / ui.pkg → RESOURCE_RESPONSE
/// 行为：led_on / led_off / set_brightness / ping 命令；
///   连接后立即推送初始 STATE；每 5 秒推送一次温度 STATE；
///   LED 变化额外发一次 EVENT (led.changed)。
class DemoDevice implements BleTransport {
  DemoDevice({this.deviceId = 'demo-light', this.name = 'Demo Light'}) {
    _decoder.onFrame = (frame) => _assembler.add(frame);
    _assembler.onComplete = _onMessageAssembled;
  }

  /// 设备标识 (会话用)。
  final String deviceId;

  /// 展示名称。
  final String name;

  /// UI 版本 (缓存键, §15.4)。
  static const String uiVersion = '1.0.0';

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();
  final StreamController<BleConnectionState> _connectionStates =
      StreamController<BleConnectionState>.broadcast();

  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final FragmentAssembler _assembler = FragmentAssembler();
  final FrameSequencer _sequencer = FrameSequencer();
  final JsonCodec _codec = const JsonCodec();
  final Random _random = Random();

  int _nextMsgId = 1000;
  int _stateVersion = 0;
  bool _connected = false;
  bool _led = false;
  int _brightness = 80;
  double _temperature = 25.0;
  Timer? _timer;

  Uint8List? _pkgCache;

  /// ui.pkg 字节 (§15.2)：manifest.json + index.html + assets/。
  Uint8List get _uiPkg => _pkgCache ??= UiPackage.pack(<String, Uint8List>{
        'manifest.json': Uint8List.fromList(utf8.encode(_manifestJson)),
        'index.html': Uint8List.fromList(utf8.encode(demoUiHtml)),
        'assets/icon.svg': Uint8List.fromList(utf8.encode(_iconSvg)),
      });

  String get _manifestJson => jsonEncode(<String, dynamic>{
        'protocol': 1,
        'ui_version': uiVersion,
        'device': <String, dynamic>{'type': 'light', 'model': 'demo-1'},
        'entry': 'index.html',
        'capabilities': <String>['power', 'brightness', 'led', 'temperature'],
      });

  // ---- 设备侧协议行为 ----

  void _onMessageAssembled(int msgId, int frameType, List<int> message) {
    switch (frameType) {
      case FrameType.command:
        try {
          final command = _codec.decode(frameType, message) as DeviceCommand;
          _handleCommand(command);
        } on ProtocolException {
          // 非协议字节：忽略
        }
      case FrameType.hello:
        try {
          final hello = _codec.decode(frameType, message) as DeviceHello;
          _handleHello(hello);
        } on ProtocolException {
          // 坏握手请求：忽略
        }
      case FrameType.resourceRequest:
        try {
          final request =
              _codec.decode(frameType, message) as DeviceResourceRequest;
          _handleResourceRequest(request);
        } on ProtocolException {
          // 坏资源请求：忽略
        }
      case FrameType.stateRequest:
        try {
          // 全量状态请求 (§16.5/§16.6)：回复当前状态快照 (不递增版本)
          _sendMessage(
            FrameType.state,
            _codec.encode(DeviceState(version: _stateVersion, state: _state)),
          );
        } on ProtocolException {
          // 坏状态请求：忽略
        }
      case FrameType.ping:
        try {
          final ping = _codec.decode(frameType, message) as DevicePing;
          _sendMessage(
            FrameType.pong,
            _codec.encode(DevicePong(requestId: ping.requestId)),
          );
        } on ProtocolException {
          // 坏 PING：忽略
        }
      default:
        break;
    }
    // 传输层 ACK (所有消息)
    _notifications.add(
      BleFrame(
        version: BleFrame.currentVersion,
        type: FrameType.ack,
        flags: 0,
        sequence: _sequencer.next(),
        payload: <int>[msgId >> 8, msgId & 0xFF],
      ).encode(),
    );
  }

  /// HELLO → HELLO_ACK (§39)：设备能力与 UI 版本声明。
  void _handleHello(DeviceHello hello) {
    _sendMessage(
      FrameType.helloAck,
      _codec.encode(DeviceHelloAck(
        requestId: hello.requestId,
        protocolVersion: 1,
        deviceType: 'light',
        deviceModel: 'demo-1',
        firmwareVersion: '1.0.0',
        uiVersion: uiVersion,
        capabilities: const <String>['power', 'brightness', 'led', 'temperature'],
      )),
    );
  }

  /// RESOURCE_REQUEST → RESOURCE_RESPONSE (§27)。
  void _handleResourceRequest(DeviceResourceRequest request) {
    final Uint8List? bytes;
    switch (request.path) {
      case 'manifest.json':
        bytes = Uint8List.fromList(utf8.encode(_manifestJson));
      case 'ui.pkg':
        bytes = _uiPkg;
      default:
        bytes = null;
    }
    final response = bytes == null
        ? DeviceResourceResponse(
            requestId: request.requestId,
            status: 'error',
            error: const DeviceError(code: 5001, message: 'resource not found'),
          )
        : DeviceResourceResponse(requestId: request.requestId, data: bytes);
    _sendMessage(FrameType.resourceResponse, _codec.encode(response));
  }

  void _handleCommand(DeviceCommand command) {
    final data = <String, dynamic>{};
    switch (command.cmd) {
      case 'led_on':
        _led = true;
        data['led'] = true;
      case 'led_off':
        _led = false;
        data['led'] = false;
      case 'set_brightness':
        final value = command.params['value'];
        if (value is num) {
          _brightness = value.toInt().clamp(0, 100);
        }
        data['brightness'] = _brightness;
      case 'ping':
        data['pong'] = true;
      default:
        data['echo'] = command.params;
    }
    _sendMessage(
      FrameType.response,
      _codec.encode(DeviceResponse(requestId: command.requestId, data: data)),
    );
    if (command.cmd == 'led_on' || command.cmd == 'led_off') {
      _sendMessage(
        FrameType.event,
        _codec.encode(DeviceEvent(event: 'led.changed', data: <String, dynamic>{'led': _led})),
      );
    }
    _pushState();
  }

  Map<String, dynamic> get _state => <String, dynamic>{
        'led': _led,
        'brightness': _brightness,
        'temperature': double.parse(_temperature.toStringAsFixed(1)),
      };

  void _pushState() {
    _sendMessage(
      FrameType.state,
      _codec.encode(DeviceState(version: ++_stateVersion, state: _state)),
    );
  }

  void _sendMessage(int frameType, List<int> data) {
    final fragmenter = Fragmenter(mtu: 247, frameType: frameType, sequencer: _sequencer);
    for (final frame in fragmenter.fragment(_nextMsgId++, data)) {
      _notifications.add(frame.encode());
    }
  }

  // ---- BleTransport (回环侧) ----

  @override
  Future<void> connect(String deviceId) async {
    _connected = true;
    _pushState(); // 初始状态
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _temperature += _random.nextDouble() * 0.6 - 0.3;
      _pushState();
    });
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_connected) {
      throw StateError('设备已断开');
    }
    _decoder.add(data);
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Stream<BleConnectionState> get connectionStates => _connectionStates.stream;

  @override
  Future<int> requestMtu(int mtu) async => mtu.clamp(23, 247);

  /// 释放资源。
  Future<void> dispose() async {
    await disconnect();
    _assembler.dispose();
    await _notifications.close();
  }
}

/// 演示设备图标 (ui.pkg assets 示例文件)。
const String _iconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
  <circle cx="16" cy="16" r="14" fill="#3949ab"/>
  <circle cx="16" cy="16" r="7" fill="#fdd835"/>
</svg>
''';

/// 演示设备 UI 页面。
///
/// 约定 (与 Phase 10 UI 规范一致)：
///   全部使用相对路径 —— 由服务端 `/s/<token>/` 前缀自动携带 session token (§13.5)；
///   WebSocket 地址从 location 推导，无需感知 token 值。
const String demoUiHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Demo Light</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f6fa; overscroll-behavior: none; -webkit-touch-callout: none; }
  header { background: #3949ab; color: #fff; padding: 16px; text-align: center; font-size: 18px; }
  main { padding: 16px; max-width: 480px; margin: 0 auto; }
  button { display: block; width: 100%; padding: 14px; margin: 10px 0; border: none; border-radius: 8px; background: #3949ab; color: #fff; font-size: 16px; }
  button:active { opacity: 0.7; }
  .card { background: #fff; border-radius: 8px; padding: 12px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  .temp { font-size: 32px; font-weight: bold; color: #3949ab; }
  input[type=range] { width: 100%; }
  #log { font-size: 12px; color: #666; font-family: monospace; white-space: pre-wrap; max-height: 160px; overflow: auto; }
  .led { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #ccc; margin-right: 6px; }
  .led.on { background: #fdd835; }
</style>
</head>
<body>
<header>Demo Light</header>
<main>
  <div class="card">温度 <span class="temp" id="temp">--</span> ℃</div>
  <div class="card"><span class="led" id="led"></span>LED：<span id="led-state">--</span></div>
  <button onclick="send('led_on')">开灯</button>
  <button onclick="send('led_off')">关灯</button>
  <div class="card">亮度 <span id="br-value">80</span>%
    <input type="range" id="br" min="0" max="100" value="80" onchange="send('set_brightness', { value: +this.value })">
  </div>
  <button onclick="send('ping')">Ping</button>
  <div class="card"><div id="log">事件日志：</div></div>
</main>
<script>
  var $ = function(id) { return document.getElementById(id); };
  function log(s) { $('log').textContent += '\n' + s; }

  // Device API Runtime (Phase 9)：由 App 自动注入，页面零样板代码
  deviceApi.onState(function(state) {
    applyState(state);
    log('state v' + (window.__stateVersion || '?') + ': ' + JSON.stringify(state));
  });
  deviceApi.onEvent('led.changed', function(data) {
    log('event led.changed: ' + JSON.stringify(data));
  });

  async function send(cmd, params) {
    log('→ ' + cmd + (params ? ' ' + JSON.stringify(params) : ''));
    try {
      var resp = await deviceApi.command(cmd, params);
      log('← ' + resp.status + (resp.error ? ' ' + JSON.stringify(resp.error) : ''));
    } catch (e) { log('✗ ' + e); }
  }

  function applyState(state) {
    if (state.temperature !== undefined) { $('temp').textContent = state.temperature; }
    if (state.led !== undefined) {
      $('led').className = 'led' + (state.led ? ' on' : '');
      $('led-state').textContent = state.led ? '开' : '关';
    }
    if (state.brightness !== undefined) {
      $('br').value = state.brightness;
      $('br-value').textContent = state.brightness;
    }
  }
</script>
</body>
</html>
''';
