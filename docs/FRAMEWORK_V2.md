# 蓝牙设备控制平台架构设计 V2

**项目名称：** Device UI Platform
**技术栈：** Flutter + Riverpod + WebView + BLE + HTML/CSS/JS
**项目状态：** 架构设计阶段
**目标：** 构建“一套 Flutter App + 多种蓝牙设备 + 设备自带 UI”的通用设备控制平台

---

# 1. 项目目标

本项目的核心理念：

> **设备负责提供 UI、设备能力和硬件状态；Flutter App 负责提供通用运行环境、BLE 通信、UI Runtime 和设备管理。**

Flutter App 不针对某一种设备编写具体 UI。

设备可以携带：

* HTML
* CSS
* JavaScript
* UI Manifest
* 图片
* 图标
* Device API 定义

手机连接设备后，动态加载设备提供的 UI。

因此可以实现：

```text
一套 Flutter App
        │
        ├── 灯
        ├── 风扇
        ├── 传感器
        ├── 电机
        ├── 仪器
        └── 其他 BLE 设备
```

不同设备可以拥有完全不同的 UI，而无需重新发布 App。

---

# 2. 核心设计原则

## 2.1 UI 与通信协议完全解耦

设备 UI 使用：

```text
HTML
CSS
JavaScript
```

设备通信使用：

```text
Device API
Command
Response
Event
State
Patch
```

BLE 只负责：

```text
Transport
```

三者互相独立。

---

## 2.2 Flutter 不负责设备 UI

Flutter 主要负责：

```text
设备扫描
设备连接
BLE 通信
协议解析
设备状态
UI Package 缓存
WebView Runtime
设备管理
```

具体设备 UI 由设备提供。

---

## 2.3 WebView 不直接操作 BLE

WebView 不知道 BLE 的存在。

架构：

```text
HTML/JS
   │
   │ HTTP / WebSocket
   ▼
UI Adapter
   │
   ▼
DeviceClient
   │
   ▼
BLE Transport
   │
   ▼
BLE
   │
   ▼
Device
```

这样可以避免 HTML/JS 与 BLE 实现耦合。

---

## 2.4 BLE 不直接传输 JSON

JSON 主要用于：

```text
HTML / JavaScript
```

BLE 底层使用：

```text
Binary Protocol
```

推荐：

```text
JSON
   ↓
Device Protocol
   ↓
Binary Encoding
   ↓
BLE Transport
```

这样可以减少 BLE 数据量，提高效率。

---

# 3. 总体架构

```text
┌───────────────────────────────────────────────────────────┐
│                       Flutter App                         │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                    WebView                          │  │
│  │              Device HTML/CSS/JS UI                  │  │
│  └───────────────────────┬─────────────────────────────┘  │
│                          │ HTTP / WebSocket                │
│  ┌───────────────────────▼─────────────────────────────┐  │
│  │                    UI Adapter                       │  │
│  │             HTTP/WS → Device API                    │  │
│  └───────────────────────┬─────────────────────────────┘  │
│                          │                                 │
│  ┌───────────────────────▼─────────────────────────────┐  │
│  │                   DeviceClient                      │  │
│  │                                                     │  │
│  │ Command / Response / Event / State / Patch         │  │
│  └───────────────────────┬─────────────────────────────┘  │
│                          │                                 │
│  ┌───────────────────────▼─────────────────────────────┐  │
│  │                  BLE Transport                      │  │
│  │                                                     │  │
│  │ MTU / Fragment / ACK / Retry / Queue / Timeout     │  │
│  └───────────────────────┬─────────────────────────────┘  │
└──────────────────────────┼────────────────────────────────┘
                           │ BLE GATT
                           ▼
┌───────────────────────────────────────────────────────────┐
│                         Device                            │
│                                                           │
│  ┌──────────────────┐       ┌─────────────────────────┐  │
│  │   UI Package     │       │      Device API         │  │
│  │                  │       │                         │  │
│  │ HTML              │       │ Command                 │  │
│  │ CSS               │       │ Response                │  │
│  │ JavaScript        │       │ Event                   │  │
│  │ Assets            │       │ State                   │  │
│  └──────────────────┘       │ Patch                   │  │
│                             └───────────┬─────────────┘  │
│                                         │                │
│                              ┌──────────▼──────────┐     │
│                              │   Hardware State     │     │
│                              └──────────────────────┘     │
└───────────────────────────────────────────────────────────┘
```

---

# 4. Flutter 分层架构

Flutter 项目分成以下几个核心层：

```text
UI
│
├── Flutter Native UI
└── WebView Device UI
        │
        ▼
UI Runtime
        │
        ▼
Device API
        │
        ▼
DeviceClient
        │
        ▼
Protocol
        │
        ▼
BLE Transport
        │
        ▼
BLE Plugin
```

---

# 5. Riverpod 状态管理

Flutter 端使用：

```text
Riverpod
```

Riverpod 负责：

* DeviceManager
* DeviceSession
* BLE 状态
* Device State
* Command Queue
* UI Package Cache
* Device Manifest
* UI Runtime
* Connection 状态

但是：

> **DeviceClient、Protocol、BLE Transport 不应该强绑定 Riverpod。**

这样底层代码仍然是普通 Dart，可以独立测试。

---

# 6. 推荐 Flutter 项目目录

```text
lib/
│
├── app/
│   ├── app.dart
│   └── router.dart
│
├── ble/
│   ├── ble_scanner.dart
│   ├── ble_connection.dart
│   ├── ble_transport.dart
│   ├── ble_packet.dart
│   ├── ble_fragment.dart
│   └── ble_queue.dart
│
├── protocol/
│   ├── message.dart
│   ├── command.dart
│   ├── response.dart
│   ├── event.dart
│   ├── state.dart
│   ├── patch.dart
│   └── codec.dart
│
├── device/
│   ├── device_client.dart
│   ├── device_manager.dart
│   ├── device_session.dart
│   └── device_manifest.dart
│
├── ui_runtime/
│   ├── webview_host.dart
│   ├── ui_server.dart
│   ├── ui_cache.dart
│   └── js_bridge.dart
│
├── providers/
│   ├── ble_provider.dart
│   ├── device_provider.dart
│   ├── device_session_provider.dart
│   ├── device_state_provider.dart
│   ├── command_provider.dart
│   ├── ui_runtime_provider.dart
│   └── ui_cache_provider.dart
│
└── storage/
    └── ...
```

---

# 7. Riverpod Provider 关系

整体关系：

```text
DeviceManager
      │
      ├── DeviceSession A
      │       │
      │       ├── DeviceClient
      │       │       │
      │       │       └── BleTransport
      │       │
      │       ├── DeviceState
      │       ├── DeviceManifest
      │       └── UI Runtime
      │
      ├── DeviceSession B
      │
      └── DeviceSession C
```

建议使用：

```text
Provider
NotifierProvider
AsyncNotifierProvider
StreamProvider
family
```

例如：

```dart
final deviceClientProvider =
    Provider.family<DeviceClient, String>((ref, deviceId) {
  final transport =
      ref.watch(bleTransportProvider(deviceId));

  return DeviceClient(transport);
});
```

---

# 8. DeviceSession

每个连接设备拥有一个独立的 Session。

```dart
class DeviceSession {
  final String deviceId;

  final DeviceManifest manifest;

  final DeviceState state;

  final ConnectionState connectionState;
}
```

多个设备：

```text
DeviceManager
│
├── DeviceSession A
│
├── DeviceSession B
│
└── DeviceSession C
```

这样 App 可以同时管理多个设备。

---

# 9. DeviceClient

DeviceClient 是 Flutter 与设备协议之间的核心接口。

```dart
class DeviceClient {
  final BleTransport transport;

  Future<void> connect();

  Future<void> disconnect();

  Future<DeviceResponse> command(
    String command,
    Map<String, dynamic> params,
  );

  Stream<DeviceEvent> get events;

  Stream<DevicePatch> get patches;

  Future<DeviceState> getState();
}
```

业务层只依赖：

```text
DeviceClient
```

而不是：

```text
flutter_reactive_ble
flutter_blue_plus
```

这样以后更换 BLE 库时，上层无需修改。

---

# 10. BLE 技术选型

推荐：

```text
flutter_reactive_ble
```

或者：

```text
universal_ble
```

BLE Plugin 只负责：

```text
Scan
Connect
Disconnect
MTU
Read
Write
Notify
```

业务逻辑不直接调用 BLE Plugin。

架构：

```text
DeviceClient
      ↓
BleTransport
      ↓
flutter_reactive_ble
```

---

# 11. Device Protocol

协议分成：

```text
Application Protocol
        ↓
Transport Protocol
        ↓
BLE GATT
```

Application Protocol：

```text
Command
Response
Event
State
Patch
```

Transport Protocol：

```text
Frame
Sequence
Fragment
ACK
NACK
Retry
Timeout
```

---

# 12. BLE Frame

建议基础 Frame：

```text
┌──────┬──────┬───────┬──────┬────────┬──────────┐
│ VER  │ TYPE │ FLAGS │ SEQ  │ LENGTH │ PAYLOAD  │
└──────┴──────┴───────┴──────┴────────┴──────────┘
                                         │
                                         ▼
                                        CRC
```

建议：

```text
VER       1 byte
TYPE      1 byte
FLAGS     1 byte
SEQ       2 bytes
LENGTH    2 bytes
PAYLOAD   N bytes
CRC16     2 bytes
```

具体字段大小可以在 MVP 实测后调整。

---

# 13. Message TYPE

第一版可以定义：

```text
0x01 COMMAND
0x02 RESPONSE
0x03 EVENT
0x04 STATE
0x05 PATCH

0x10 ACK
0x11 NACK

0x20 HELLO
0x21 HELLO_ACK
0x22 PING
0x23 PONG

0x30 RESOURCE_REQUEST
0x31 RESOURCE_RESPONSE
```

后续可以继续扩展。

---

# 14. SEQ 与 Request ID

两者必须分开。

## SEQ

负责：

```text
BLE Message Sequence
```

用于：

```text
重传
ACK
顺序
重复包检测
```

例如：

```text
SEQ = 1001
```

---

## Request ID

负责：

```text
业务请求与响应对应关系
```

例如：

```text
request_id = 78231
```

因此：

```text
SEQ
    ↓
Transport Layer

request_id
    ↓
Application Layer
```

不要混用。

---

# 15. BLE Fragment

一个 Application Message 可能大于 MTU。

例如：

```text
Application Message
3000 bytes
```

需要：

```text
Fragment 0
Fragment 1
Fragment 2
...
Fragment N
```

建议 Fragment Header：

```text
┌──────────┬──────────┬───────────┬────────┬─────────┐
│ MSG_ID   │ INDEX    │ TOTAL     │ LENGTH │ DATA    │
└──────────┴──────────┴───────────┴────────┴─────────┘
```

设备收到：

```text
Fragment
    ↓
Assembler
    ↓
完整 Message
    ↓
Protocol Decoder
```

---

# 16. ACK / NACK / Retry

Transport 层需要支持：

```text
ACK
NACK
Timeout
Retry
```

例如：

```text
Flutter
   │
   │ Frame
   ▼
Device
   │
   │ ACK
   ▼
Flutter
```

超时：

```text
Frame
  │
  ├── Timeout
  │
  ▼
Retry
```

达到最大重试次数：

```text
ERROR
```

建议后续增加：

```text
Sliding Window
```

提高 BLE 吞吐量。

---

# 17. Device Application API

WebView 使用简单的 HTTP API。

例如：

```text
GET  /api/device
GET  /api/state
POST /api/command
GET  /api/resource/xxx
WS   /ws
```

---

# 18. Command

HTML：

```http
POST /api/command
```

JSON：

```json
{
  "cmd": "light.set",
  "params": {
    "brightness": 80
  }
}
```

UI Adapter：

```text
JSON
 ↓
Command
 ↓
DeviceClient
 ↓
Binary Protocol
 ↓
BLE
```

---

# 19. Response

设备：

```json
{
  "type": "response",
  "request_id": 78231,
  "status": "ok",
  "data": {
    "brightness": 80
  }
}
```

Flutter：

```text
BLE
 ↓
Binary Decode
 ↓
Response
 ↓
DeviceClient
 ↓
HTTP Response
 ↓
WebView
```

---

# 20. Event

设备可以主动发送：

```json
{
  "type": "event",
  "event": "temperature.changed",
  "data": {
    "value": 25.5
  }
}
```

适合：

```text
温度变化
电源变化
传感器变化
设备报警
硬件事件
```

---

# 21. Device State

设备维护完整 State：

```json
{
  "power": true,
  "brightness": 80,
  "color": "#FF0000",
  "mode": "normal",
  "temperature": 25.5
}
```

设备是：

> **硬件实时状态的 Source of Truth**

云端不直接取代设备状态。

---

# 22. State Version

每个 State 都有：

```text
state_version
```

例如：

```text
100
101
102
103
```

如果 Flutter 收到：

```text
100
103
```

发现：

```text
101、102
```

缺失，则重新请求完整 State：

```text
GET /api/state
```

或者：

```text
STATE_REQUEST
```

重新同步。

---

# 23. State Patch

日常状态更新不要发送完整 State。

使用 Patch：

```json
{
  "type": "patch",
  "version": 103,
  "ops": [
    {
      "op": "replace",
      "path": "/brightness",
      "value": 60
    }
  ]
}
```

流程：

```text
Device State
     ↓
Patch
     ↓
Flutter DeviceState
     ↓
WebView JS
     ↓
DOM
```

---

# 24. Patch 类型

第一版可以支持：

```text
replace
add
remove
```

例如：

```json
{
  "op": "replace",
  "path": "/brightness",
  "value": 80
}
```

以后可以根据需要扩展。

---

# 25. UI Package

设备携带完整 UI：

```text
ui.pkg
```

内部：

```text
ui.pkg
│
├── manifest.json
├── index.html
├── app.js
├── style.css
│
└── assets/
    ├── icon.png
    ├── background.webp
    └── ...
```

建议压缩：

```text
gzip
```

或者：

```text
brotli
```

---

# 26. Manifest

设备必须提供：

```text
manifest.json
```

示例：

```json
{
  "protocol": 1,
  "ui_version": "1.2.3",

  "device": {
    "type": "light",
    "model": "AC7014"
  },

  "entry": "index.html",

  "capabilities": [
    "light",
    "rgb",
    "scene"
  ]
}
```

Manifest 用于描述：

```text
协议版本
UI 版本
设备类型
设备型号
入口页面
Capabilities
```

---

# 27. UI Cache

App 不应该每次连接都通过 BLE 下载 HTML。

流程：

```text
连接设备
    ↓
读取 Manifest
    ↓
读取 UI Version
    ↓
检查本地 Cache
    │
    ├── 相同
    │      ↓
    │   直接加载
    │
    └── 不同
           ↓
       下载 UI Package
           ↓
       校验
           ↓
       Cache
           ↓
       加载
```

本地缓存：

```text
Device ID
    ↓
UI Version
    ↓
ui.pkg
```

---

# 28. UI Package 校验

正式产品建议增加：

```text
size
hash
version
```

例如：

```json
{
  "ui_version": "1.2.3",
  "size": 183421,
  "sha256": "..."
}
```

下载完成后：

```text
Download
   ↓
SHA256
   ↓
验证成功
   ↓
Cache
```

避免 UI Package 损坏。

---

# 29. UI Runtime

Flutter 负责：

```text
WebView
Local HTTP Server
WebSocket
UI Cache
Device API Adapter
```

结构：

```text
WebView
   │
   │ HTTP
   ▼
127.0.0.1
   │
   ▼
Shelf
   │
   ▼
UI Adapter
   │
   ▼
DeviceClient
```

---

# 30. Localhost Server

建议不要使用固定：

```text
localhost:8080
```

正式版本使用：

```text
127.0.0.1
+
随机端口
+
Session Token
```

例如：

```text
127.0.0.1:<random-port>
```

同时加入：

```text
Session Token
Origin 校验
Device Session 绑定
```

避免本地接口被其他来源随意访问。

---

# 31. WebSocket

WebSocket 用于设备主动推送。

流程：

```text
Device
   │
   │ BLE Notify
   ▼
Flutter
   │
   │ WebSocket
   ▼
WebView
```

例如：

```json
{
  "type": "patch",
  "version": 103,
  "ops": [
    {
      "op": "replace",
      "path": "/brightness",
      "value": 60
    }
  ]
}
```

---

# 32. WebView API

WebView 只需要理解：

```text
HTTP
WebSocket
JavaScript
```

例如：

```javascript
fetch("/api/command", {
  method: "POST",
  headers: {
    "Content-Type": "application/json"
  },
  body: JSON.stringify({
    cmd: "light.set",
    params: {
      brightness: 80
    }
  })
});
```

---

# 33. JS State Store

设备状态进入 WebView 后：

```text
Device State
     ↓
JS Store
     ↓
UI Rendering
```

例如：

```javascript
window.deviceState = {
    power: true,
    brightness: 80,
    color: "#FF0000"
};
```

Patch：

```javascript
applyPatch(patch);
```

然后重新渲染需要变化的 UI。

---

# 34. HTMX

HTMX 可以继续使用，但不应该成为整个协议的核心。

推荐：

```text
Device UI Runtime
│
├── HTML
├── CSS
├── JavaScript
└── Device API
```

HTMX 是可选的：

```text
HTML
+
HTMX
+
Device API
```

以后也可以使用：

```text
原生 JavaScript
Preact
Vue
Svelte
其他轻量 UI 框架
```

Device Protocol 不应该依赖 HTMX。

---

# 35. Device API 与 HTMX 解耦

错误：

```text
Device Protocol
    ↓
HTMX
```

正确：

```text
Device Protocol
    ↓
Device API
    ↓
┌──────────────┬───────────────┐
│              │               │
HTMX        JavaScript       其他 UI
```

这样 UI 技术可以自由变化。

---

# 36. UI 动态更新

原则：

> **设备负责状态，UI 负责显示状态。**

不要让 UI 自己认为：

```text
点击按钮
 ↓
brightness = 80
```

而应该：

```text
用户点击
 ↓
Command
 ↓
Device
 ↓
Hardware
 ↓
State Changed
 ↓
Patch
 ↓
UI
```

这样 UI 永远以设备状态为准。

---

# 37. 完整操作流程

用户点击：

```text
Brightness 80
```

完整流程：

```text
┌──────────────┐
│    WebView   │
└──────┬───────┘
       │ HTTP
       ▼
┌──────────────┐
│ UI Adapter   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ DeviceClient │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Protocol     │
└──────┬───────┘
       │ Binary
       ▼
┌──────────────┐
│ BLE Transport│
└──────┬───────┘
       │
       ▼
     Device
       │
       ▼
   Hardware
       │
       ▼
   State Change
       │
       ▼
      Patch
       │
       ▼
     Flutter
       │
       ▼
   WebSocket
       │
       ▼
    WebView
       │
       ▼
      UI
```

---

# 38. 连接流程

```text
Scan
 ↓
Connect
 ↓
Discover Services
 ↓
MTU
 ↓
HELLO
 ↓
HELLO_ACK
 ↓
Read Manifest
 ↓
Check UI Version
 ↓
Load UI Cache
 ↓
Sync State
 ↓
WebView
```

---

# 39. HELLO

Flutter：

```text
HELLO
```

包含：

```text
protocol_version
app_version
supported_features
```

设备：

```text
HELLO_ACK
```

返回：

```text
protocol_version
device_type
device_model
firmware_version
ui_version
capabilities
```

---

# 40. Capability

设备不要仅仅告诉 App：

```text
device_type = light
```

还应该告诉：

```text
capabilities
```

例如：

```json
[
  "power",
  "brightness",
  "rgb",
  "temperature",
  "scene"
]
```

这样未来可以支持不同能力组合。

例如：

```text
灯 A
power
brightness

灯 B
power
brightness
rgb

灯 C
power
brightness
rgb
scene
temperature
```

---

# 41. Resource API

UI 需要图片、字体等资源。

可以定义：

```text
GET /api/resource/<path>
```

例如：

```text
/api/resource/icon.png
```

如果资源已经存在本地 Cache：

```text
直接读取
```

否则：

```text
Resource Request
 ↓
BLE
 ↓
Device
 ↓
Resource Response
```

---

# 42. UI 资源不应该每次都通过 BLE 加载

优先：

```text
首次连接
 ↓
下载 UI Package
 ↓
本地缓存
 ↓
WebView 本地加载
```

而不是：

```text
WebView
 ↓
每张图片
 ↓
BLE
```

否则 UI 会非常慢。

---

# 43. UI Package 加载位置

推荐：

```text
BLE Device
      ↓
Flutter UI Cache
      ↓
Local HTTP Server
      ↓
WebView
```

即：

```text
WebView
   ↓
127.0.0.1
   ↓
本地 UI Package
```

而不是 WebView 直接访问 BLE。

---

# 44. JSON 与 Binary Protocol

推荐最终架构：

```text
                  WebView
                     │
                  JSON/HTTP
                     │
                     ▼
                Device API
                     │
                     ▼
                DeviceClient
                     │
                JSON Object
                     │
                     ▼
               Binary Codec
                     │
               CBOR / TLV
                     │
                     ▼
                BLE Frame
                     │
                     ▼
                  BLE GATT
```

第一阶段可以：

```text
JSON
```

用于快速验证。

正式版本再考虑：

```text
CBOR
MessagePack
TLV
自定义 Binary
```

---

# 45. Binary Codec

协议层应该定义：

```dart
abstract class Codec {
  List<int> encode(Object message);

  Object decode(List<int> data);
}
```

以后可以替换：

```text
JsonCodec
CborCodec
MessagePackCodec
BinaryCodec
```

而不影响 DeviceClient。

---

# 46. Transport Interface

建议：

```dart
abstract class BleTransport {
  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<void> write(List<int> data);

  Stream<List<int>> get notifications;

  Future<int> requestMtu(int mtu);
}
```

上层不关心具体 BLE 插件。

---

# 47. Command Queue

BLE 通信建议增加：

```text
Command Queue
```

例如：

```text
Command 1
Command 2
Command 3
Command 4
```

队列：

```text
┌─────────┐
│ Queue   │
├─────────┤
│ Cmd 1   │
│ Cmd 2   │
│ Cmd 3   │
│ Cmd 4   │
└─────────┘
```

根据命令类型决定：

```text
串行
并行
可取消
可覆盖
```

例如连续调节亮度：

```text
80
81
82
83
84
```

可以只保留：

```text
84
```

减少 BLE 流量。

---

# 48. Sync / Async

不建议简单使用：

```text
mode: sync
mode: async
```

而是根据 API 类型自然区分。

Command：

```text
Request
 ↓
Response
```

Event：

```text
Device
 ↓
Event
```

State：

```text
Device
 ↓
State / Patch
```

因此协议不需要大量依赖：

```text
mode
```

字段。

---

# 49. Error Protocol

统一错误：

```json
{
  "status": "error",
  "error": {
    "code": 1003,
    "message": "Invalid brightness"
  }
}
```

错误码建议分组：

```text
1xxx Protocol Error
2xxx Device Error
3xxx Command Error
4xxx Hardware Error
5xxx Resource Error
```

例如：

```text
1001 Invalid Protocol
1002 Unsupported Version

2001 Device Busy
2002 Device Not Ready

3001 Invalid Command
3002 Invalid Parameter

4001 Motor Error
4002 Sensor Error

5001 Resource Not Found
5002 Resource Corrupted
```

---

# 50. 安全设计

正式版本建议增加：

```text
Device Identity
Session
Authentication
Permission
Encryption
```

尤其是涉及：

```text
门锁
电机
电源
高功率设备
工业设备
```

不能只依赖 BLE 链路本身。

可以逐步增加：

```text
HELLO
 ↓
Challenge
 ↓
Authentication
 ↓
Session Key
 ↓
Encrypted Message
```

---

# 51. 云端扩展

未来如果加入云端：

```text
Flutter
│
├── Local Device
│      ↓
│     BLE
│
└── Cloud
       ↓
      MQTT/HTTP/WebSocket
```

不要让云端直接改变本地 UI。

建议：

```text
Device
 = Hardware State Source of Truth

Cloud
 = Account / Configuration / History / Remote Command
```

---

# 52. Local + Cloud 统一接口

未来可以定义：

```dart
abstract class DeviceTransport {
  Future<void> connect();

  Future<void> disconnect();

  Future<DeviceResponse> send(DeviceMessage message);

  Stream<DeviceMessage> get messages;
}
```

实现：

```text
BleTransport
CloudTransport
UsbTransport
WifiTransport
```

这样：

```text
DeviceClient
```

不需要知道底层是：

```text
BLE
WiFi
USB
Cloud
```

---

# 53. 推荐的最终软件结构

```text
                     Device UI Platform
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
        UI Spec           Device API          Transport
          │                   │                   │
    HTML/CSS/JS       Command/State/Event       BLE
    Manifest          Patch/Capability           USB
    Resource                                    WiFi
                                                TCP
```

---

# 54. MVP 第一阶段

不要一次实现全部功能。

第一阶段只实现：

```text
Flutter
 ↓
WebView
 ↓
Local HTTP
 ↓
DeviceClient
 ↓
BLE
 ↓
ESP32 / AC7014
```

功能：

```text
Scan
Connect
Write
Notify
Command
Response
```

设备提供：

```text
index.html
```

先验证整个闭环。

---

# 55. MVP 第二阶段

增加：

```text
Frame
SEQ
Length
CRC
Fragment
Assembler
```

验证：

```text
100 bytes
500 bytes
1 KB
5 KB
10 KB
```

数据传输。

---

# 56. MVP 第三阶段

增加：

```text
ACK
NACK
Retry
Timeout
Command Queue
```

测试：

```text
丢包
断线
重连
重复包
乱序
设备忙
```

---

# 57. MVP 第四阶段

增加：

```text
State
State Version
Patch
Event
```

实现：

```text
设备状态 → Flutter → WebView
```

---

# 58. MVP 第五阶段

增加：

```text
Manifest
UI Package
UI Version
UI Cache
Resource
SHA256
```

实现：

```text
设备升级 UI
 ↓
Flutter 自动检测
 ↓
下载
 ↓
验证
 ↓
缓存
```

---

# 59. MVP 第六阶段

优化：

```text
CBOR / MessagePack / Binary
GZIP / Brotli
Sliding Window
多设备
并发
安全认证
```

---

# 60. 性能优化原则

## UI

```text
HTML Minify
CSS Minify
JS Minify
GZIP/Brotli
图片压缩
WebP
懒加载
```

## BLE

```text
MTU
Fragment
ACK Window
Batch
Command Queue
Binary Encoding
```

## State

```text
Full State
    ↓
Patch
    ↓
Only changed fields
```

---

# 61. 不推荐的方案

## 不推荐 1

```text
WebView → BLE Plugin
```

WebView 不应该直接操作 BLE。

---

## 不推荐 2

```text
BLE → JSON
```

JSON 可以作为逻辑协议，但不应该成为高频 BLE 数据的最终格式。

---

## 不推荐 3

```text
固定 localhost:8080
```

正式版本使用：

```text
127.0.0.1
随机端口
Session Token
```

---

## 不推荐 4

```text
每次连接都下载 UI
```

必须有：

```text
UI Cache
Version
Hash
```

---

## 不推荐 5

```text
HTMX = Device Protocol
```

HTMX 只是 UI 技术。

---

## 不推荐 6

```text
Riverpod → 直接控制 BLE Plugin
```

应该：

```text
Riverpod
 ↓
DeviceClient
 ↓
BleTransport
 ↓
BLE Plugin
```

---

# 62. 最终数据流

## 用户操作

```text
User
 ↓
HTML
 ↓
HTTP
 ↓
UI Adapter
 ↓
DeviceClient
 ↓
Command
 ↓
Codec
 ↓
Frame
 ↓
Fragment
 ↓
BLE
 ↓
Device
 ↓
Hardware
```

## 设备状态

```text
Hardware
 ↓
Device State
 ↓
Patch
 ↓
Binary Frame
 ↓
BLE Notify
 ↓
Flutter
 ↓
DeviceClient
 ↓
Riverpod
 ↓
WebSocket
 ↓
WebView
 ↓
JavaScript
 ↓
UI
```

---

# 63. 最终架构总结

整个系统最终形成：

```text
┌──────────────────────────────────────────────┐
│                  Flutter App                 │
│                                              │
│ Riverpod                                     │
│    │                                         │
│ DeviceManager                                │
│    │                                         │
│ DeviceSession                                │
│    │                                         │
│ DeviceClient                                 │
│    │                                         │
│ Protocol                                     │
│    │                                         │
│ BLE Transport                                │
│    │                                         │
│ flutter_reactive_ble / universal_ble         │
│                                              │
│ WebView + UI Runtime                         │
└───────────────────────┬──────────────────────┘
                        │
                       BLE
                        │
┌───────────────────────▼──────────────────────┐
│                    Device                    │
│                                              │
│ UI Package                                   │
│ HTML/CSS/JS                                  │
│ Manifest                                     │
│ Device API                                   │
│ State/Patch                                  │
│ Hardware                                     │
└──────────────────────────────────────────────┘
```

核心原则：

```text
UI 与协议解耦
协议与 BLE 解耦
BLE 与 Flutter 状态管理解耦
HTMX 与 Device API 解耦
设备 UI 与 Flutter App 解耦
```

最终目标：

> **一套 Flutter App，通过统一 Device API 和 Transport，可以运行来自不同设备的动态 UI，并同时支持 BLE、本地控制以及未来的 Wi-Fi / USB / Cloud Transport。**

---

# 64. 推荐技术栈

```text
Flutter
Riverpod
webview_flutter

BLE:
flutter_reactive_ble
或
universal_ble

Local UI Server:
shelf
web_socket_channel

Protocol:
自定义 Binary Protocol

Encoding:
第一阶段 JSON
正式版本 CBOR / MessagePack / TLV

Compression:
GZIP / Brotli

UI:
HTML
CSS
JavaScript
HTMX（可选）

Storage:
UI Package Cache
Device Metadata
```

---

# 65. 第一版必须实现的最小接口

Flutter：

```text
BleTransport
DeviceClient
ProtocolCodec
DeviceSession
UIRuntime
```

Device：

```text
HELLO
HELLO_ACK
COMMAND
RESPONSE
EVENT
STATE
PATCH
ACK
NACK
```

UI：

```text
GET  /api/device
GET  /api/state
POST /api/command
WS   /ws
```

这套接口先稳定下来，再扩展其他功能。

---

# 66. 开发顺序

最终建议严格按照：

```text
1. BLE Transport
        ↓
2. Frame
        ↓
3. Fragment
        ↓
4. ACK / Retry
        ↓
5. Device Protocol
        ↓
6. DeviceClient
        ↓
7. Riverpod
        ↓
8. Local HTTP Server
        ↓
9. WebView
        ↓
10. State / Patch
        ↓
11. Manifest
        ↓
12. UI Package
        ↓
13. UI Cache
        ↓
14. Capability
        ↓
15. Security
        ↓
16. Cloud Transport
```

不要一开始就做完整 UI 系统。

先把：

```text
Flutter
    ↕
BLE
    ↕
Device
```

这一条链路跑通，再接 WebView。

---

# 67. 最终产品定位

这个项目不应该只被设计成：

> 一个 Flutter 蓝牙灯控 App。

更适合定位为：

> **通用 BLE Device UI Runtime / Device UI Platform**

它的核心能力是：

```text
设备
  ↓
提供 UI
  ↓
提供 Device API
  ↓
提供 Capability
  ↓
提供 State
  ↓
Flutter Runtime
  ↓
统一运行
```

因此未来新增设备时：

```text
新增设备
 ↓
开发固件
 ↓
开发 HTML UI
 ↓
定义 Device API
 ↓
打包 UI
 ↓
设备上线
```

而不是：

```text
新增设备
 ↓
修改 Flutter
 ↓
增加页面
 ↓
增加 Provider
 ↓
发布 App
 ↓
用户升级 App
```

这就是整个架构最大的价值。
