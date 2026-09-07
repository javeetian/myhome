# WORK.md

# Device UI Platform

## 项目工作流程与开发执行规范

**版本：** V2.0
**文档类型：** WORK / Development Workflow
**项目状态：** 架构设计 → MVP 开发
**核心技术：** Flutter + Riverpod + WebView + BLE + HTML/CSS/JS

---

# 0. 文档目的

本文件用于指导整个项目的实际开发。

`FRAMEWORK_V2.md` 负责定义：

* 系统架构
* 模块职责
* 协议设计
* 技术选型
* 数据流

本文件负责定义：

* 开发顺序
* 每个阶段做什么
* 每个阶段产出什么
* 如何验证
* 什么条件下进入下一阶段
* 出现问题时如何定位
* MVP 如何逐步演进为正式产品

---

# 1. 项目最终目标

最终实现：

```text
                         Device UI Platform

┌──────────────────────────────────────────────────────────┐
│                       Flutter App                        │
│                                                          │
│  Riverpod                                                 │
│      │                                                   │
│      ▼                                                   │
│  DeviceManager                                           │
│      │                                                   │
│      ▼                                                   │
│  DeviceSession                                           │
│      │                                                   │
│      ▼                                                   │
│  DeviceClient                                            │
│      │                                                   │
│      ▼                                                   │
│  Protocol                                                │
│      │                                                   │
│      ▼                                                   │
│  BLE Transport                                           │
│      │                                                   │
│      ▼                                                   │
│  BLE Plugin                                              │
│                                                          │
│  WebView                                                 │
│      │                                                   │
│      ▼                                                   │
│  UI Runtime                                              │
│                                                          │
└───────────────────────┬──────────────────────────────────┘
                        │
                       BLE
                        │
                        ▼
┌──────────────────────────────────────────────────────────┐
│                        Device                            │
│                                                          │
│  UI Package                                              │
│  Manifest                                                │
│  Device API                                              │
│  State                                                   │
│  Patch                                                   │
│  Hardware                                                │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

核心目标：

> 一套 Flutter App，可以连接不同 BLE 设备，并运行设备自己提供的 UI。

新增设备时尽量做到：

```text
新增设备
    ↓
开发设备固件
    ↓
开发设备 HTML/CSS/JS
    ↓
定义 Device API
    ↓
生成 UI Package
    ↓
设备部署
    ↓
Flutter 自动识别并运行
```

而不是：

```text
新增设备
    ↓
修改 Flutter
    ↓
增加页面
    ↓
发布新 App
```

---

# 2. 开发总原则

整个项目严格遵循以下原则。

## 2.1 先 Transport，后 UI

开发顺序：

```text
BLE
 ↓
Frame
 ↓
Fragment
 ↓
ACK
 ↓
Protocol
 ↓
DeviceClient
 ↓
Riverpod
 ↓
HTTP Adapter
 ↓
WebView
 ↓
UI Package
```

不要反过来。

---

# 3. 五层架构

项目划分为五个主要层。

```text
Layer 5
UI Runtime
    │
Layer 4
Device API
    │
Layer 3
Device Protocol
    │
Layer 2
Transport
    │
Layer 1
BLE
```

具体：

```text
HTML/JS
   ↓
HTTP / WebSocket
   ↓
UI Adapter
   ↓
DeviceClient
   ↓
Protocol Codec
   ↓
Transport
   ↓
BLE GATT
```

---

# 4. 开发阶段总览

整个项目分成 12 个阶段。

```text
Phase 0   环境与工程初始化
   ↓
Phase 1   BLE Transport
   ↓
Phase 2   Frame
   ↓
Phase 3   Fragment
   ↓
Phase 4   ACK / Retry / Queue
   ↓
Phase 5   Device Protocol
   ↓
Phase 6   DeviceClient
   ↓
Phase 7   Riverpod
   ↓
Phase 8   UI Adapter
   ↓
Phase 9   WebView Runtime
   ↓
Phase 10  Manifest / UI Package / Cache
   ↓
Phase 11  State / Patch / Event
   ↓
Phase 12  Security / Performance / Production
```

---

# 5. Phase 0：工程初始化

## 目标

建立 Flutter 项目和基础目录。

---

## 5.1 Flutter 项目

创建：

```text
Flutter App
```

添加：

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter_riverpod:
  webview_flutter:
  flutter_reactive_ble:
  shelf:
  web_socket_channel:
```

BLE 库可以替换成：

```text
universal_ble
```

但上层必须使用：

```text
BleTransport
```

屏蔽具体 BLE Plugin。

---

## 5.2 创建目录

```text
lib/
│
├── app/
│
├── ble/
│
├── protocol/
│
├── device/
│
├── ui_runtime/
│
├── providers/
│
└── storage/
```

---

## 5.3 第一阶段不做

不要做：

```text
复杂 UI
云端
用户系统
登录
设备商城
设备升级
```

只建立基础工程。

---

## 5.4 完成条件

Flutter：

```text
flutter run
```

成功。

Android / iOS：

```text
Build
Install
Launch
```

成功。

---

# 6. Phase 1：BLE Transport

这是整个项目第一条真正的技术链路。

---

## 6.1 定义接口

```dart
abstract class BleTransport {

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<void> write(List<int> data);

  Stream<List<int>> get notifications;

  Future<int> requestMtu(int mtu);
}
```

---

## 6.2 BLE 功能

第一阶段只实现：

```text
Scan
Connect
Disconnect
Discover Services
Write
Notify
MTU
```

---

## 6.3 BLE GATT 服务

建议定义：

```text
Service UUID
```

以及：

```text
TX Characteristic
RX Characteristic
```

例如：

```text
Flutter
   │
   │ Write
   ▼
TX Characteristic
   │
   ▼
Device

Device
   │
   │ Notify
   ▼
RX Characteristic
   │
   ▼
Flutter
```

UUID 不要散落在业务代码中。

统一：

```dart
class BleConstants {
  static const serviceUuid = "...";
  static const txUuid = "...";
  static const rxUuid = "...";
}
```

---

## 6.4 MTU

连接以后：

```text
Connect
 ↓
Request MTU
 ↓
Read negotiated MTU
 ↓
Transport 保存 MTU
```

不要假设：

```text
MTU = 247
```

必须以实际协商结果为准。

---

## 6.5 验证

测试：

```text
1 byte
10 bytes
100 bytes
200 bytes
500 bytes
1000 bytes
```

确认：

```text
Write
 ↓
Device
 ↓
Notify
 ↓
Flutter
```

能够完整收发。

---

## 6.6 完成条件

必须证明：

```text
Flutter ↔ Device
```

可以稳定双向通信。

---

# 7. Phase 2：Transport Frame

BLE 通了以后，不直接传 JSON。

先建立 Frame。

---

# 7.1 Frame

基础结构：

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

---

# 7.2 Frame 类

```dart
class BleFrame {

  final int version;

  final int type;

  final int flags;

  final int sequence;

  final List<int> payload;

}
```

实现：

```text
encode()
decode()
validate()
```

---

# 7.3 CRC

流程：

```text
Header
 +
Payload
 ↓
CRC16
```

接收：

```text
Frame
 ↓
CRC Check
 ↓
失败 → 丢弃 / NACK
成功 → Decode
```

---

# 7.4 SEQ

SEQ 用于 Transport。

例如：

```text
100
101
102
103
```

用途：

```text
ACK
重复检测
重传
排序
```

不能作为业务 Request ID。

---

# 7.5 测试

必须做：

```text
正常 Frame
空 Payload
最大 Payload
CRC 错误
Length 错误
Version 错误
非法 Type
SEQ 溢出
```

---

# 8. Phase 3：Fragment

解决：

```text
Application Message > BLE MTU
```

---

# 8.1 原则

一个完整 Message：

```text
3000 bytes
```

拆成：

```text
Fragment 0
Fragment 1
Fragment 2
...
Fragment N
```

---

# 8.2 Fragment

定义：

```text
MSG_ID
INDEX
TOTAL
LENGTH
DATA
```

例如：

```text
MSG_ID = 100
INDEX = 0
TOTAL = 13
```

---

# 8.3 发送流程

```text
Application Message
        ↓
Fragmenter
        ↓
Fragment[]
        ↓
Frame Encoder
        ↓
BLE
```

---

# 8.4 接收流程

```text
BLE
 ↓
Frame Decoder
 ↓
Fragment
 ↓
Assembler
 ↓
完整 Message
```

---

# 8.5 异常

必须处理：

```text
缺 Fragment
重复 Fragment
乱序 Fragment
错误 TOTAL
错误 LENGTH
超时
```

---

# 8.6 超时

例如：

```text
收到 Fragment 0
 ↓
等待 Fragment 1
 ↓
等待 Fragment 2
 ↓
超过 timeout
 ↓
丢弃整个 Message
```

后续可以通过 NACK 请求重传。

---

# 8.7 测试

必须测试：

```text
100 bytes
500 bytes
1 KB
5 KB
10 KB
50 KB
```

以及：

```text
随机乱序
随机丢包
随机重复
```

---

# 9. Phase 4：ACK / Retry / Queue

---

# 9.1 ACK

定义：

```text
0x10 ACK
0x11 NACK
```

流程：

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

---

# 9.2 Retry

例如：

```text
发送
 ↓
等待 ACK
 ↓
Timeout
 ↓
Retry 1
 ↓
Timeout
 ↓
Retry 2
 ↓
Timeout
 ↓
Error
```

配置：

```text
maxRetry
ackTimeout
```

---

# 9.3 Command Queue

建立：

```text
CommandQueue
```

例如：

```text
Queue
│
├── Command A
├── Command B
├── Command C
└── Command D
```

---

# 9.4 Command 分类

以后可以定义：

```text
Serial
Parallel
Replaceable
Cancelable
```

例如亮度：

```text
80
81
82
83
84
```

可以：

```text
80
81
82
83
84
 ↓
只发送 84
```

---

# 9.5 Sliding Window

第一版：

```text
Window = 1
```

即：

```text
发送
 ↓
等待 ACK
 ↓
下一包
```

稳定以后：

```text
Window = 4
```

甚至：

```text
Window = 8
```

提高 BLE 吞吐量。

---

# 10. Phase 5：Device Protocol

Transport 稳定后才定义业务协议。

---

# 10.1 TYPE

定义：

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

---

# 10.2 Command

逻辑结构：

```text
Command
├── request_id
├── command
└── params
```

例如：

```json
{
  "request_id": 78231,
  "cmd": "light.set",
  "params": {
    "brightness": 80
  }
}
```

---

# 10.3 Response

```json
{
  "request_id": 78231,
  "status": "ok",
  "data": {
    "brightness": 80
  }
}
```

---

# 10.4 Event

```json
{
  "event": "temperature.changed",
  "data": {
    "value": 25.5
  }
}
```

---

# 10.5 Error

统一：

```json
{
  "status": "error",
  "error": {
    "code": 3001,
    "message": "Invalid parameter"
  }
}
```

---

# 10.6 Codec

定义：

```dart
abstract class Codec {

  List<int> encode(Object message);

  Object decode(List<int> data);
}
```

第一版：

```text
JSON Codec
```

正式版本：

```text
CBOR
MessagePack
TLV
Custom Binary
```

可以择一。

---

# 11. Phase 6：DeviceClient

DeviceClient 是 Flutter 业务层与设备之间的统一入口。

---

# 11.1 API

```dart
class DeviceClient {

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

---

# 11.2 DeviceClient 不知道 UI

它只负责：

```text
Command
Response
Event
State
Patch
```

不知道：

```text
HTML
WebView
HTMX
DOM
```

---

# 11.3 DeviceClient 不直接使用 BLE Plugin

错误：

```text
DeviceClient
 ↓
flutter_reactive_ble
```

正确：

```text
DeviceClient
 ↓
BleTransport
 ↓
flutter_reactive_ble
```

---

# 11.4 单元测试

DeviceClient 必须可以脱离真实 BLE 测试。

使用：

```text
MockBleTransport
```

测试：

```text
Command
Response
Timeout
Retry
Error
Event
State
Patch
```

---

# 12. Phase 7：Riverpod

现在加入 Riverpod。

---

# 12.1 Riverpod 职责

Riverpod 管：

```text
DeviceManager
DeviceSession
DeviceState
Connection State
Device Manifest
UI Cache
UI Runtime
```

---

# 12.2 不管：

```text
BLE Frame Encoding
CRC
Fragment
Codec
Transport
```

这些仍然是普通 Dart。

---

# 12.3 Provider

推荐：

```text
bleTransportProvider
deviceClientProvider
deviceSessionProvider
deviceManagerProvider
deviceStateProvider
deviceManifestProvider
uiRuntimeProvider
uiCacheProvider
```

---

# 12.4 Device Manager

```text
DeviceManager
│
├── DeviceSession A
│
├── DeviceSession B
│
└── DeviceSession C
```

---

# 12.5 Device Session

```text
DeviceSession
│
├── Connection State
├── Manifest
├── Device State
├── DeviceClient
└── UI Runtime
```

---

# 12.6 状态生命周期

```text
disconnected
      ↓
scanning
      ↓
connecting
      ↓
discovering
      ↓
negotiating
      ↓
handshaking
      ↓
loading_ui
      ↓
syncing_state
      ↓
connected
```

断线：

```text
connected
   ↓
disconnecting
   ↓
disconnected
```

异常：

```text
任何状态
   ↓
error
```

---

# 13. Phase 8：UI Adapter

现在开始接 WebView。

---

# 13.1 Local HTTP Server

使用：

```text
Shelf
```

WebView：

```text
http://127.0.0.1:<random-port>
```

---

# 13.2 HTTP API

第一版：

```text
GET  /api/device
GET  /api/state
POST /api/command
GET  /api/resource/<path>
WS   /ws
```

---

# 13.3 API Adapter

结构：

```text
HTTP
 ↓
Router
 ↓
UI Adapter
 ↓
DeviceClient
```

例如：

```text
POST /api/command
```

转换：

```text
HTTP JSON
 ↓
DeviceClient.command()
```

---

# 13.4 HTTP Response

Device Response：

```text
DeviceClient
 ↓
UI Adapter
 ↓
HTTP JSON
```

WebView 不需要知道 BLE。

---

# 13.5 Session Security

Local Server 使用：

```text
127.0.0.1
+
random port
+
session token
```

请求必须验证：

```text
Token
Origin
Session
Device
```

---

# 14. Phase 9：WebView Runtime

---

# 14.1 WebView

WebView 只负责：

```text
HTML
CSS
JavaScript
```

---

# 14.2 UI Runtime

```text
UI Package
 ↓
Local HTTP Server
 ↓
WebView
```

---

# 14.3 JS API

HTML/JS：

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

# 14.4 WebSocket

WebSocket：

```text
Device
 ↓
BLE Notify
 ↓
Flutter
 ↓
UI Adapter
 ↓
WebSocket
 ↓
WebView
```

---

# 14.5 JavaScript State

WebView：

```javascript
window.deviceState = {};
```

接收到：

```text
State
Patch
Event
```

之后更新：

```text
JS Store
 ↓
DOM
```

---

# 15. Phase 10：Manifest / UI Package / Cache

---

# 15.1 Manifest

定义：

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
    "power",
    "brightness",
    "rgb"
  ]
}
```

---

# 15.2 UI Package

```text
ui.pkg
│
├── manifest.json
├── index.html
├── app.js
├── style.css
└── assets/
```

---

# 15.3 UI 下载

流程：

```text
Connect
 ↓
HELLO
 ↓
HELLO_ACK
 ↓
Manifest
 ↓
Compare UI Version
```

如果：

```text
Device UI Version
==
Local UI Version
```

则：

```text
直接加载
```

否则：

```text
Request UI Package
 ↓
Download
 ↓
Hash Verify
 ↓
Cache
 ↓
Load
```

---

# 15.4 Cache

缓存：

```text
Device ID
UI Version
Package Hash
Package Path
```

---

# 15.5 UI Package 完整性

至少：

```text
Size
SHA256
Version
```

正式版本可以加入：

```text
Digital Signature
```

---

# 16. Phase 11：State / Patch / Event

---

# 16.1 Device State

设备维护完整状态：

```json
{
  "power": true,
  "brightness": 80,
  "color": "#FF0000",
  "mode": "normal",
  "temperature": 25.5
}
```

---

# 16.2 State Version

例如：

```text
100
101
102
103
```

---

# 16.3 Patch

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

# 16.4 Flutter 状态

流程：

```text
BLE
 ↓
DeviceClient
 ↓
Patch
 ↓
Riverpod DeviceState
 ↓
UI Runtime
 ↓
WebSocket
 ↓
WebView
```

---

# 16.5 Version Gap

如果：

```text
Current = 100
Received = 103
```

说明：

```text
101 / 102
```

可能丢失。

执行：

```text
STATE_REQUEST
```

获取完整 State。

---

# 16.6 Full State

完整 State 用于：

```text
首次连接
重连
Version Gap
App 恢复
设备主动要求同步
```

---

# 17. 完整连接流程

正式实现后：

```text
User
 ↓
Scan
 ↓
Select Device
 ↓
Connect
 ↓
Discover GATT
 ↓
Request MTU
 ↓
HELLO
 ↓
HELLO_ACK
 ↓
Read Manifest
 ↓
Check UI Cache
 ↓
Download UI if needed
 ↓
Verify UI
 ↓
Load UI
 ↓
Request State
 ↓
State
 ↓
WebView Connected
```

---

# 18. 完整命令流程

用户：

```text
Brightness = 80
```

流程：

```text
WebView
 ↓
POST /api/command
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
BLE Write
 ↓
Device
 ↓
Hardware
 ↓
Response
 ↓
BLE Notify
 ↓
Flutter
 ↓
DeviceClient
 ↓
HTTP Response
 ↓
WebView
```

---

# 19. 完整状态流程

设备硬件发生变化：

```text
Hardware
 ↓
Device State
 ↓
State Version +1
 ↓
Patch
 ↓
Binary Codec
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
JS Store
 ↓
UI
```

---

# 20. 断线流程

```text
BLE Disconnect
       ↓
DeviceSession
       ↓
connectionState = disconnected
       ↓
UI Runtime
       ↓
显示连接状态
```

如果允许自动重连：

```text
Disconnect
 ↓
Backoff
 ↓
Reconnect
 ↓
HELLO
 ↓
Manifest
 ↓
State Sync
 ↓
Connected
```

---

# 21. 重连不能直接恢复旧状态

重连以后必须：

```text
重新建立 Session
 ↓
重新 Handshake
 ↓
重新同步 State
```

不能简单认为：

```text
旧 Session = 新 Session
```

---

# 22. 多设备流程

多个设备：

```text
DeviceManager
│
├── Session A
│    ├── BLE
│    ├── State
│    └── WebView
│
├── Session B
│    ├── BLE
│    ├── State
│    └── WebView
│
└── Session C
```

每个设备必须有独立：

```text
Transport
Session
State
Manifest
UI Runtime
```

---

# 23. UI 生命周期

```text
UI Package Found
       ↓
Create Runtime
       ↓
Start Local Server
       ↓
Load WebView
       ↓
Open WebSocket
       ↓
Send Device Info
       ↓
Send Current State
       ↓
UI Ready
```

关闭：

```text
Dispose WebView
 ↓
Close WebSocket
 ↓
Stop UI Session
```

---

# 24. Device API 版本控制

协议必须支持版本。

例如：

```text
protocol = 1
```

以后：

```text
protocol = 2
```

Flutter 必须判断：

```text
Supported?
```

如果不支持：

```text
显示协议版本错误
```

不要尝试盲目通信。

---

# 25. Capability

设备通过 Manifest / HELLO 提供：

```text
power
brightness
rgb
scene
temperature
```

UI 根据 Capability 决定功能。

例如：

```text
没有 rgb
 ↓
隐藏 RGB UI
```

---

# 26. 不允许 UI 假设设备能力

不要：

```javascript
setRGB()
```

直接认为所有设备支持。

应该：

```text
manifest.capabilities
        ↓
判断
        ↓
显示 UI
```

---

# 27. Resource 工作流程

UI 请求：

```text
/api/resource/icon.png
```

检查：

```text
Local Cache
```

如果不存在：

```text
Resource Request
 ↓
Device
 ↓
Fragment
 ↓
BLE
 ↓
Flutter
 ↓
Cache
 ↓
HTTP Response
```

---

# 28. 性能测试

正式开发前必须建立性能指标。

---

## 28.1 BLE 吞吐量

测试：

```text
100 KB
500 KB
1 MB
```

记录：

```text
平均速度
最大速度
最小速度
丢包率
重传率
CPU
RAM
```

---

# 28.2 UI 加载时间

记录：

```text
Connect
 ↓
Manifest
 ↓
UI Download
 ↓
WebView Start
 ↓
UI Ready
```

重点指标：

```text
Cold Start
Warm Start
Cached Start
```

---

# 28.3 操作延迟

例如：

```text
点击按钮
 ↓
BLE
 ↓
Device
 ↓
Response
 ↓
UI
```

记录：

```text
P50
P95
P99
```

---

# 29. 异常测试

必须测试：

```text
BLE 断开
BLE 重连
设备重启
App 后台
App 被杀
WebView 崩溃
HTTP Server 重启
Notify 丢失
BLE Write 失败
CRC 错误
Fragment 丢失
Fragment 重复
Fragment 乱序
ACK 丢失
Command Timeout
Device Busy
UI Package 损坏
协议版本不兼容
```

---

# 30. 测试设备

建议准备：

```text
Device A
正常设备

Device B
低 RAM

Device C
低 BLE 吞吐

Device D
高延迟

Device E
模拟异常
```

MVP 阶段至少：

```text
ESP32
AC7014
```

其中一个先完整跑通。

---

# 31. 日志系统

所有层都需要统一日志。

格式：

```text
[TIME]
[LEVEL]
[MODULE]
[DEVICE]
[SEQ]
[REQUEST_ID]
MESSAGE
```

例如：

```text
22:01:10 DEBUG BLE
device=ABC
seq=100
write 32 bytes
```

---

# 32. 日志等级

```text
TRACE
DEBUG
INFO
WARN
ERROR
```

正式版本默认：

```text
INFO
WARN
ERROR
```

开发版本：

```text
DEBUG
```

---

# 33. 调试模式

建议增加：

```text
Developer Mode
```

显示：

```text
Device ID
Firmware
UI Version
Protocol Version
MTU
RSSI
Connection State
Last Error
TX bytes
RX bytes
Retry Count
```

方便现场定位问题。

---

# 34. 安全开发阶段

MVP：

```text
BLE
+
Session
```

正式：

```text
Device Identity
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

# 35. 安全重点

不能依赖：

```text
BLE Pairing
```

作为唯一安全机制。

尤其涉及：

```text
门锁
电机
电源
工业控制
```

必须有应用层认证。

---

# 36. 云端阶段

本地 BLE 稳定以后再加入 Cloud。

架构：

```text
                 DeviceClient
                  /        \
                 /          \
        BleTransport      CloudTransport
             │                  │
            BLE                Cloud
```

统一：

```dart
abstract class DeviceTransport
```

因此：

```text
BLE
WiFi
USB
Cloud
```

可以作为不同 Transport。

---

# 37. 云端职责

Cloud 负责：

```text
用户
设备绑定
配置
历史数据
远程命令
OTA 信息
```

设备负责：

```text
实时硬件状态
硬件执行
安全状态
```

---

# 38. OTA

UI Package 与 Firmware OTA 必须分开。

```text
Firmware OTA
    ↓
Firmware

UI Update
    ↓
ui.pkg
```

不要因为更新 UI 而必须更新 Firmware。

---

# 39. UI OTA

未来：

```text
Cloud
 ↓
UI Package
 ↓
App
 ↓
Device
```

或者：

```text
Cloud
 ↓
App Cache
 ↓
WebView
```

具体策略根据设备资源和安全需求确定。

---

# 40. 第一版设备固件

MVP 固件只需要：

```text
BLE GATT
 ↓
Transport
 ↓
Protocol
 ↓
Device API
 ↓
Hardware
```

暂时不需要：

```text
复杂 UI
OTA
云端
用户认证
```

但是协议接口需要提前预留扩展。

---

# 41. 第一版设备 UI

只做一个页面：

```text
index.html
```

内容：

```text
Power
Brightness
Temperature
```

例如：

```text
┌───────────────────────┐
│       Light           │
│                       │
│ Power     ON          │
│                       │
│ Brightness            │
│ ─────────────── 80%   │
│                       │
│ Temperature   25.5°C  │
└───────────────────────┘
```

---

# 42. MVP 验证标准

MVP 必须实现：

```text
1. Flutter 扫描设备
2. Flutter 连接设备
3. MTU 协商
4. HELLO
5. Device Manifest
6. UI Package
7. UI Cache
8. WebView 加载
9. POST Command
10. BLE Binary Frame
11. Fragment
12. Response
13. State
14. Patch
15. WebSocket
16. 断线重连
```

全部成功以后才进入正式开发。

---

# 43. MVP 最小 Demo

最终 Demo：

```text
Flutter App
     │
     │ BLE
     ▼
ESP32
     │
     ├── Manifest
     ├── UI Package
     ├── Device API
     └── Hardware
```

App：

```text
扫描
 ↓
连接
 ↓
加载 UI
 ↓
显示页面
 ↓
点击 Power
 ↓
设备开灯
 ↓
设备返回 State
 ↓
UI 更新
```

整个闭环跑通。

---

# 44. 开发优先级

优先级必须：

```text
P0
BLE
Transport
Protocol
DeviceClient
```

```text
P1
Riverpod
UI Adapter
WebView
```

```text
P2
UI Package
Cache
State/Patch
```

```text
P3
Performance
Security
Cloud
OTA
```

---

# 45. 禁止过早优化

MVP 阶段不要过早加入：

```text
复杂 Binary Compression
Sliding Window
多线程
复杂 DSL
大型 UI Framework
Cloud
微服务
```

先证明：

```text
BLE
 +
Device Protocol
 +
WebView
```

可行。

---

# 46. JSON → Binary 的迁移策略

第一阶段：

```text
WebView
 ↓
JSON
 ↓
DeviceClient
 ↓
JSON Codec
 ↓
BLE
```

稳定后：

```text
WebView
 ↓
JSON
 ↓
DeviceClient
 ↓
CBOR / MessagePack
 ↓
BLE
```

最终：

```text
WebView API
    ↓
Logical Object
    ↓
Binary Codec
    ↓
Transport
```

这样 UI 不需要修改。

---

# 47. 协议稳定原则

一旦设备量开始增加：

```text
Protocol Version
```

必须严格管理。

不要随意修改：

```text
TYPE
Frame Header
Field meaning
Error code
Command semantics
```

需要：

```text
Version
Capability
Backward Compatibility
```

---

# 48. Git 分支建议

推荐：

```text
main
develop
feature/ble
feature/protocol
feature/device-client
feature/riverpod
feature/webview
feature/ui-runtime
feature/ui-package
```

每完成一个 Phase：

```text
Tag
```

例如：

```text
v0.1-ble
v0.2-frame
v0.3-protocol
v0.4-device-client
v0.5-webview
v0.6-ui-runtime
v1.0-mvp
```

---

# 49. 每个 Phase 的完成规则

每个 Phase 必须满足：

```text
代码完成
   +
单元测试
   +
真实设备测试
   +
异常测试
   +
日志完善
   +
文档更新
```

才算完成。

---

# 50. 当前实际执行任务

项目现在不要同时做所有事情。

当前执行顺序：

```text
[ ] 1. 创建 Flutter 工程
[ ] 2. 加入 Riverpod
[ ] 3. 加入 BLE Plugin
[ ] 4. 实现 BleTransport
[ ] 5. 建立 ESP32/AC7014 BLE GATT
[ ] 6. Flutter ↔ Device 双向通信
[ ] 7. 实现 BLE Frame
[ ] 8. 实现 CRC
[ ] 9. 实现 Fragment
[ ] 10. 实现 ACK
[ ] 11. 实现 Retry
[ ] 12. 实现 Device Protocol
[ ] 13. 实现 DeviceClient
[ ] 14. 接入 Riverpod
[ ] 15. 实现 Shelf
[ ] 16. WebView 加载本地 HTML
[ ] 17. HTTP → DeviceClient
[ ] 18. WebSocket → WebView
[ ] 19. State / Patch
[ ] 20. Manifest
[ ] 21. UI Package
[ ] 22. UI Cache
[ ] 23. 完整 MVP
```

---

# 51. 当前第一目标

不要把目标定成：

```text
完成整个 App
```

而应该定成：

> **让一个真实 BLE 设备在 Flutter App 中运行自己的 HTML UI，并完成一次完整的 Command → Hardware → State → UI 闭环。**

也就是：

```text
                ┌──────────────┐
                │   WebView    │
                └──────┬───────┘
                       │
                    Command
                       │
                       ▼
                ┌──────────────┐
                │    Flutter   │
                └──────┬───────┘
                       │
                      BLE
                       │
                       ▼
                ┌──────────────┐
                │    Device    │
                └──────┬───────┘
                       │
                    Hardware
                       │
                       ▼
                    State
                       │
                       ▼
                    Flutter
                       │
                       ▼
                    WebView
```

这条链路跑通以后，整个架构就已经被验证了。

---

# 52. 最终开发路线

```text
                  ┌──────────────┐
                  │   Phase 0    │
                  │ Project Init │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 1    │
                  │ BLE Transport│
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 2    │
                  │ Frame + CRC  │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 3    │
                  │  Fragment    │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 4    │
                  │ ACK / Retry  │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 5    │
                  │Device Protocol│
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 6    │
                  │ DeviceClient │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 7    │
                  │   Riverpod   │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 8    │
                  │ UI Adapter   │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Phase 9    │
                  │ WebView      │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Phase 10    │
                  │ UI Package   │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Phase 11    │
                  │ State/Patch  │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Phase 12    │
                  │ Production   │
                  └──────────────┘
```

---

# 53. 项目最终判断标准

当以下流程可以稳定运行：

```text
设备上电
    ↓
Flutter 扫描
    ↓
连接
    ↓
HELLO
    ↓
Manifest
    ↓
UI Cache
    ↓
WebView
    ↓
用户操作
    ↓
Command
    ↓
Binary Protocol
    ↓
BLE
    ↓
Device
    ↓
Hardware
    ↓
State
    ↓
Patch
    ↓
Flutter Riverpod
    ↓
WebSocket
    ↓
WebView
    ↓
UI 更新
```

并且：

```text
断线可以恢复
大数据可以分包
丢包可以重传
UI 可以缓存
不同设备可以使用不同 UI
Flutter 不需要针对设备修改 UI
```

则 V1 架构验证成功。

---

# 54. 后续扩展

V1 成功后再考虑：

```text
Cloud
OTA
UI OTA
Device Authentication
Encryption
Multi-user
Device Groups
Scene
Automation
WiFi Transport
USB Transport
```

核心架构不改变。

---

# 55. 最终原则

整个项目始终遵守：

```text
                    UI
                     │
                     │
                 Device API
                     │
                     │
                DeviceClient
                     │
                     │
                  Protocol
                     │
                     │
                 Transport
                     │
                     │
                    BLE
```

任何一层都不能越层调用。

特别是：

```text
HTML
  ✕
BLE Plugin
```

```text
DeviceClient
  ✕
HTML DOM
```

```text
Riverpod
  ✕
BLE Frame implementation
```

正确方式：

```text
HTML
 ↓
Device API
 ↓
DeviceClient
 ↓
Protocol
 ↓
Transport
 ↓
BLE
```

---

# 56. 当前项目第一开发任务

**只做 Phase 1。**

目标：

```text
Flutter
   ↕
BLE
   ↕
ESP32 / AC7014
```

实现：

```text
Scan
Connect
MTU
Write
Notify
Disconnect
```

验证完成以后，再开始：

```text
Frame + CRC
```

不要提前开发 WebView、HTMX、UI Package。

---

# 57. 与 FRAMEWORK_V2.md 的关系

```text
FRAMEWORK_V2.md
    │
    └── 定义“系统应该是什么”

WORK.md
    │
    └── 定义“系统应该怎么一步一步做出来”
```

以后所有开发任务都应该首先对应到：

```text
Phase
Task
Acceptance Criteria
Test
```

完成一个阶段后再进入下一个阶段。
