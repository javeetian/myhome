# Device Studio / Device UI Platform

# FRAMEWORK_V3.md

> Version: 3.0
> Status: Architecture Design
> Target: Flutter Desktop + Flutter Mobile + MCU Device SDK
> Platforms: Windows / macOS / Android / iOS / Embedded Device

---

# 1. 项目定位

本项目不是单纯的 Flutter BLE App，而是一套完整的：

> **Device UI Platform**

核心目标：

```text
UI 开发
   ↓
ui.pkg
   ↓
Device Studio
   ↓
PC 模拟 App
   ↓
Virtual Device
   ↓
Protocol
   ↓
真实设备 SDK
   ↓
MCU Firmware
```

开发者可以在没有真实硬件的情况下，在 Windows / macOS 上完成：

* UI 开发
* UI 打包
* UI 运行
* 设备模拟
* Device API 调试
* Protocol 调试
* State / Event 调试
* 异常测试
* 通信压力测试
* UI Package 测试
* C 设备代码生成

最终再把生成的设备代码复制到真实设备 SDK 中编译。

---

# 2. V3 核心设计原则

## 2.1 PC 是主要开发环境

开发设备 UI 时：

```text
PC
├── UI Editor / IDE
├── Device Studio
├── UI Runtime
├── Virtual Device
├── Protocol Inspector
└── Code Generator
```

尽可能避免：

```text
修改 UI
↓
烧录 MCU
↓
连接 BLE
↓
测试
```

---

# 3. 核心架构

整体结构：

```text
                         Device Platform
                              │
             ┌────────────────┼────────────────┐
             │                │                │
             ▼                ▼                ▼
         UI SDK          Device SDK      Simulator SDK
             │                │                │
             ▼                ▼                ▼
          ui.pkg          firmware       Virtual Device
             │                │                │
             └────────────────┼────────────────┘
                              │
                              ▼
                       Device Studio
                              │
                       Flutter Desktop
                              │
             ┌────────────────┼────────────────┐
             │                │                │
             ▼                ▼                ▼
          WebView        DeviceClient      Inspector
             │                │                │
             └────────────────┼────────────────┘
                              │
                           Protocol
                              │
                       ┌──────┴──────┐
                       │             │
                       ▼             ▼
                 Simulator       BLE / WiFi
                       │             │
                       ▼             ▼
                 Virtual MCU     Real Device
```

---

# 4. 最重要的架构原则

真实设备和模拟设备必须共享：

```text
Protocol
Device API
State Model
Command Model
Event Model
Manifest
Codec
Fragmentation
Error Model
```

只允许替换：

```text
Transport
Hardware
```

因此：

```text
                  DeviceClient
                       │
                    Protocol
                       │
                   Transport
                 /            \
                /              \
               ▼                ▼
       SimulatorTransport   BleTransport
               │                │
               ▼                ▼
        VirtualDevice       Real Device
```

不能出现：

```text
Simulator 一套协议
Real Device 另一套协议
```

否则长期一定产生兼容问题。

---

# 5. 系统模块

V3 包含以下主要模块：

```text
1. Device Definition
2. UI SDK
3. UI Package
4. UI Runtime
5. Device API
6. DeviceClient
7. Protocol
8. Transport
9. Virtual Device
10. Virtual Hardware
11. Device Studio
12. Code Generator
13. Device SDK
14. Test Framework
15. Debug / Inspector
```

---

# 6. Device Definition

Device Definition 是整个系统的基础。

推荐使用：

```text
device.yaml
```

作为设备定义源文件。

示例：

```yaml
device:
  id: smart_light
  name: Smart Light
  model: L100

protocol:
  version: 1

api:
  version: 1

state:
  power:
    type: bool

  brightness:
    type: uint8
    min: 0
    max: 100

  color_temperature:
    type: uint16
    min: 2700
    max: 6500

commands:

  - name: light.set_power

    params:
      power:
        type: bool

  - name: light.set_brightness

    params:
      value:
        type: uint8
        min: 0
        max: 100

events:

  - name: light.state_changed
```

---

# 7. Device Definition 的作用

同一份：

```text
device.yaml
```

生成：

```text
Dart Device API
C Device API
Device Manifest
Simulator
Test Schema
Protocol Schema
UI Capability Definition
```

结构：

```text
                       device.yaml
                            │
             ┌──────────────┼──────────────┐
             │              │              │
             ▼              ▼              ▼
          Dart API       C API         Manifest
             │              │              │
             ▼              ▼              ▼
         Flutter        Device SDK       ui.pkg
             │              │
             └──────┬───────┘
                    ▼
               Simulator
```

---

# 8. UI Package

UI 最终打包成：

```text
ui.pkg
```

第一版可以使用 ZIP 格式。

结构：

```text
ui.pkg
├── manifest.json
├── index.html
├── app.js
├── style.css
├── assets/
│   ├── icon.svg
│   ├── background.png
│   └── ...
└── package.json
```

---

# 9. UI Manifest

示例：

```json
{
  "package": "smart_light_ui",
  "version": "1.0.0",

  "device": {
    "type": "smart_light",
    "model": "L100"
  },

  "protocol": {
    "version": 1
  },

  "entry": "index.html",

  "api_version": 1,

  "hash": {
    "algorithm": "sha256",
    "value": "..."
  }
}
```

未来增加：

```text
signature
publisher
minimum_app_version
minimum_firmware_version
permissions
locales
themes
```

---

# 10. UI Package 生命周期

```text
UI Source
   │
   ▼
ui build
   │
   ▼
ui.pkg
   │
   ├── hash
   ├── version
   └── manifest
   │
   ▼
Device Studio
   │
   ▼
验证
   │
   ▼
解包
   │
   ▼
UI Runtime
```

---

# 11. UI Cache

缓存 Key：

```text
device_type
device_model
ui_version
package_hash
```

例如：

```text
cache/
└── smart_light/
    └── L100/
        └── 1.0.0/
            └── sha256_xxxxx/
                ├── index.html
                ├── app.js
                └── assets/
```

如果：

```text
version + hash
```

没有变化：

```text
直接使用缓存
```

否则：

```text
重新安装 UI Package
```

---

# 12. UI Runtime

UI Runtime 负责：

```text
ui.pkg
   ↓
HTTP Server
   ↓
WebView
```

推荐：

```text
127.0.0.1:<random-port>
```

例如：

```text
http://127.0.0.1:39127/
```

不要直接让 WebView 访问文件系统。

---

# 13. UI 与设备通信

UI 不允许直接操作：

```text
BLE
TCP
USB
MCU
```

UI 只能使用：

```text
Device API
```

例如：

```javascript
device.command(
    "light.set_brightness",
    {
        value: 80
    }
);
```

获取状态：

```javascript
device.getState();
```

监听：

```javascript
device.on("state", function(state) {
    render(state);
});
```

---

# 14. UI Adapter

架构：

```text
WebView
   │
   │ HTTP / WebSocket
   ▼
UI Adapter
   │
   ▼
DeviceClient
```

UI Adapter 负责：

* HTTP API
* WebSocket
* JS API
* Session
* 权限
* 参数验证
* JSON ↔ Device API

---

# 15. HTTP API

建议：

```text
GET  /api/device
GET  /api/state
POST /api/command
GET  /api/manifest
```

Command：

```http
POST /api/command
```

Body：

```json
{
  "request_id": 78231,
  "cmd": "light.set_brightness",
  "params": {
    "value": 80
  }
}
```

Response：

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

# 16. WebSocket

用于：

```text
Device → App → UI
```

例如：

```json
{
  "event": "state",
  "version": 102,
  "data": {
    "power": true,
    "brightness": 80
  }
}
```

也可以发送 Patch：

```json
{
  "event": "patch",
  "version": 103,
  "patch": [
    {
      "op": "replace",
      "path": "/brightness",
      "value": 81
    }
  ]
}
```

---

# 17. DeviceClient

DeviceClient 是 Flutter 侧的核心设备抽象。

```dart
class DeviceClient {
  Future<DeviceInfo> getInfo();

  Future<DeviceState> getState();

  Future<CommandResponse> command(
    String name,
    Map<String, dynamic> params,
  );

  Stream<DeviceEvent> get events;
}
```

DeviceClient 不知道：

```text
WebView
DOM
HTML
Flutter Widget
```

也不知道具体使用：

```text
BLE
Simulator
WiFi
USB
Cloud
```

---

# 18. Transport

统一接口：

```dart
abstract class DeviceTransport {

  Future<void> connect();

  Future<void> disconnect();

  Future<void> send(List<int> data);

  Stream<List<int>> get received;

  bool get isConnected;
}
```

实现：

```text
BleTransport
SimulatorTransport
WifiTransport
UsbTransport
CloudTransport
```

---

# 19. Protocol

建议第一版：

```text
VER | TYPE | FLAGS | SEQ | LENGTH | PAYLOAD | CRC16
```

例如：

```text
+-----+------+-------+-----+--------+---------+------+
| VER | TYPE | FLAGS | SEQ | LENGTH | PAYLOAD | CRC  |
+-----+------+-------+-----+--------+---------+------+
   1     1      1      2      2        N        2
```

---

# 20. Frame Type

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

# 21. Application Request ID

Transport：

```text
SEQ
```

Application：

```text
request_id
```

必须分开。

例如：

```text
SEQ = 123
request_id = 78231
```

其中：

```text
SEQ
```

负责通信帧。

```text
request_id
```

负责：

```text
command
response
```

关联。

---

# 22. Codec

协议层不要绑定 JSON。

定义：

```dart
abstract class Codec {

  List<int> encode(Object message);

  Object decode(List<int> data);
}
```

第一版：

```text
JsonCodec
```

以后：

```text
CborCodec
MessagePackCodec
BinaryCodec
```

上层 API 不需要改变。

---

# 23. Fragmentation

BLE MTU 有限制。

大消息必须分片。

逻辑：

```text
Application Message
        │
        ▼
Fragment
        │
 ┌──────┼──────┐
 ▼      ▼      ▼
F0      F1     F2
```

Fragment Metadata：

```text
MSG_ID
INDEX
TOTAL
LENGTH
DATA
```

接收端必须处理：

* 丢包
* 重复
* 乱序
* 超时
* 错误长度
* 错误总片数
* 重复消息

---

# 24. ACK / Retry

第一版：

```text
Stop-and-Wait
Window = 1
```

流程：

```text
TX
 ↓
等待 ACK
 ↓
成功 → 下一帧
 ↓
Timeout
 ↓
Retry
 ↓
超过最大次数
 ↓
ERROR
```

后续可以：

```text
Sliding Window
Window = 4 / 8
```

---

# 25. Virtual Device

Virtual Device 是真实设备的 PC 模拟版本。

例如：

```text
VirtualLight
```

内部：

```text
VirtualLight
├── state
├── command handler
├── event
├── timer
└── virtual hardware
```

---

# 26. Virtual Hardware

模拟：

```text
Power
PWM
LED
Temperature
Sensor
Motor
Relay
```

例如：

```dart
class VirtualPwm {

  int value = 0;

  void set(int value) {
    this.value = value;
  }
}
```

真实设备：

```text
PWM Driver
```

模拟：

```text
VirtualPwm
```

业务逻辑保持一致。

---

# 27. Device Logic

建议把：

```text
Device Logic
```

和：

```text
Hardware Driver
```

分离。

结构：

```text
Device Logic
     │
     ▼
Hardware Adapter
     │
 ┌───┴────┐
 ▼        ▼
Virtual   Real
Hardware  Hardware
```

这样 Virtual Device 可以尽可能运行真实设备业务逻辑。

---

# 28. Device Studio

Device Studio 是 PC 开发中心。

目标平台：

```text
Windows
macOS
```

使用：

```text
Flutter Desktop
```

---

# 29. Device Studio 功能

第一版：

```text
1. Load UI Package
2. Select Device
3. Start Simulator
4. Run UI
5. View State
6. Send Command
7. View Protocol
8. View Logs
9. Reset Device
10. Disconnect / Reconnect
```

后续：

```text
11. Fault Injection
12. Packet Inspector
13. Performance Monitor
14. UI Hot Reload
15. Code Generator
16. Device Package Manager
```

---

# 30. Device Studio UI

建议：

```text
┌────────────────────────────────────────────────────┐
│ Device Studio                                      │
├──────────────┬───────────────────────┬─────────────┤
│ Devices      │                       │ Inspector   │
│              │                       │             │
│ ● Light L100 │       WebView         │ Power       │
│ ○ Fan F100   │                       │ ON          │
│ ○ Lock L1    │       UI              │             │
│              │                       │ Brightness  │
│              │                       │ 80          │
├──────────────┴───────────────────────┴─────────────┤
│ Protocol Console                                   │
│ TX  01 01 00 12 ...                                │
│ RX  01 02 00 18 ...                                │
└────────────────────────────────────────────────────┘
```

---

# 31. Inspector

Inspector 显示：

```text
Device ID
Model
Firmware Version
Protocol Version
UI Version
MTU
RSSI
Connection State
State Version
TX Bytes
RX Bytes
Retry Count
Last Error
```

模拟设备还可以显示：

```text
Virtual Hardware
Power
PWM
Temperature
Sensor
```

---

# 32. Fault Injection

Simulator 必须支持故障注入。

例如：

```text
Packet Loss       10%
Packet Delay      100ms
Duplicate        2%
CRC Error         ON
Timeout           OFF
Disconnect        OFF
Wrong Sequence    OFF
Device Reset      OFF
```

测试：

```text
Retry
Reconnect
Fragment
State Sync
Error Handling
```

---

# 33. Riverpod

Flutter App 和 Device Studio 使用：

```text
Riverpod
```

负责：

```text
DeviceManager
DeviceSession
DeviceState
ConnectionState
Manifest
UI Package
UI Cache
Runtime State
```

不负责：

```text
CRC
Frame
Fragment
Codec
Transport
Retry
```

---

# 34. DeviceManager

```text
DeviceManager
│
├── DeviceSession A
│
├── DeviceSession B
│
└── DeviceSession C
```

支持多设备。

---

# 35. DeviceSession

每一个设备：

```text
DeviceSession
├── Transport
├── DeviceClient
├── ConnectionState
├── DeviceInfo
├── Manifest
├── DeviceState
├── UI Runtime
└── Logs
```

不同设备互不影响。

---

# 36. Connection State

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

异常：

```text
error
 ↓
reconnecting
 ↓
connecting
```

---

# 37. State Model

设备状态必须有：

```text
version
```

例如：

```json
{
  "version": 100,
  "power": true,
  "brightness": 80
}
```

Patch：

```text
version = 101
```

如果：

```text
当前 version = 100
收到 version = 103
```

说明：

```text
100 → 101 → 102 → 103
```

中间缺失。

必须：

```text
REQUEST_FULL_STATE
```

---

# 38. Full State 使用场景

以下情况获取完整 State：

```text
第一次连接
重新连接
App Resume
State Version Gap
Device Reset
Protocol Error Recovery
```

---

# 39. Command Queue

命令不能全部简单排队。

分为：

```text
SERIAL
PARALLEL
REPLACEABLE
CANCELABLE
```

例如：

```text
brightness = 50
brightness = 51
brightness = 52
brightness = 53
```

如果用户快速拖动滑块：

```text
50
51
52
53
```

可以合并成：

```text
53
```

这样减少 BLE 流量。

---

# 40. Security

MVP：

```text
BLE
+
Session Token
```

正式产品：

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

特别是：

```text
Lock
Motor
Power
Garage
Industrial Control
```

不能只依赖 BLE Pairing。

---

# 41. Code Generator

核心目标：

```text
device.yaml
      ↓
Code Generator
      ↓
Dart
C
JSON
Simulator
```

输出：

```text
generated/
├── dart/
│   └── device_api.dart
│
├── c/
│   ├── device_api.h
│   ├── device_api.c
│   ├── device_state.h
│   ├── device_state.c
│   └── device_commands.c
│
├── simulator/
│   └── virtual_device.dart
│
└── manifest.json
```

---

# 42. 不生成整个 Firmware

Code Generator 只生成：

```text
Device Application Layer
```

不要生成：

```text
main.c
startup
BLE driver
RTOS
HAL
Flash Driver
```

这些由真实设备 SDK 提供。

---

# 43. Device SDK

真实设备 SDK：

```text
device_sdk/
├── core/
│   ├── protocol/
│   ├── codec/
│   ├── frame/
│   ├── fragment/
│   └── security/
│
├── transport/
│   └── ble/
│
├── platform/
│   ├── timer/
│   ├── storage/
│   └── system/
│
├── hardware/
│   ├── gpio/
│   ├── pwm/
│   └── sensor/
│
└── app/
    └── generated/
```

---

# 44. Generated Code 放置位置

```text
device_sdk/
└── app/
    ├── generated/
    │   ├── device_api.c
    │   ├── device_api.h
    │   ├── device_state.c
    │   └── device_state.h
    │
    ├── main.c
    ├── device_app.c
    └── hardware.c
```

这样 SDK 核心和生成代码解耦。

---

# 45. Device Developer 的代码

生成：

```text
generated/device_api.c
```

开发者自己实现：

```text
device_app.c
hardware.c
```

例如：

```c
void light_set_brightness(uint8_t value)
{
    pwm_set(value);
}
```

Device SDK 负责：

```text
BLE
Protocol
Frame
Fragment
ACK
State
Command Routing
```

Hardware App 负责：

```text
PWM
GPIO
Sensor
Motor
Relay
```

---

# 46. UI 与 Device 的最终关系

```text
                 UI
                 │
           Device API
                 │
            DeviceClient
                 │
              Protocol
                 │
             Transport
                 │
        ┌────────┴────────┐
        │                 │
    Simulator            BLE
        │                 │
 Virtual Device       Real Device
        │                 │
Virtual Hardware     Real Hardware
```

---

# 47. PC 完整开发流程

```text
device.yaml
     │
     ├──────────────┐
     ▼              ▼
Code Generator     UI Development
     │              │
     ▼              ▼
Simulator         ui.pkg
     │              │
     └──────┬───────┘
            ▼
       Device Studio
            │
       WebView UI
            │
       Device API
            │
       Virtual Device
            │
       Virtual Hardware
```

---

# 48. 从 PC 到真实设备

开发完成：

```text
device.yaml
     │
     ▼
Code Generator
     │
     ▼
generated/
     │
     ▼
Copy
     │
     ▼
Real Device SDK
     │
     ▼
MCU Compiler
     │
     ▼
Firmware
```

---

# 49. BLE 只是 Transport

未来支持：

```text
BLE
WiFi
USB
TCP
Cloud
```

不修改：

```text
UI
Device API
DeviceClient
Protocol
State
Command
```

只增加：

```text
Transport
```

---

# 50. 推荐项目目录

```text
device-platform/
│
├── tools/
│   ├── device_cli/
│   ├── ui_builder/
│   └── code_generator/
│
├── studio/
│   └── flutter/
│
├── sdk/
│   ├── ui/
│   ├── device/
│   └── simulator/
│
├── protocol/
│   ├── schema/
│   ├── codec/
│   ├── frame/
│   └── fragment/
│
├── devices/
│   ├── smart_light/
│   │   ├── device.yaml
│   │   ├── ui/
│   │   ├── simulator/
│   │   └── generated/
│   │
│   └── smart_fan/
│
└── examples/
    └── smart_light/
```

---

# 51. 最终产品形态

最终可以形成：

```text
Device Studio
│
├── UI Builder
├── Device Simulator
├── Protocol Inspector
├── State Inspector
├── Log Viewer
├── Package Builder
└── Code Generator
```

开发者：

```text
写 Device Definition
        ↓
写 UI
        ↓
PC 模拟
        ↓
测试
        ↓
生成代码
        ↓
复制到 Device SDK
        ↓
编译真实设备
```

---

# 52. V3 最终目标

一个新设备应该尽量做到：

```text
新增 Device
      ↓
device.yaml
      ↓
UI
      ↓
Simulator
      ↓
Device Studio 测试
      ↓
Code Generator
      ↓
真实 Device SDK
```

而不是修改：

```text
Flutter App UI
Flutter BLE Code
Device Protocol
多个设备判断
```

最终 Flutter App 只需要知道：

```text
Manifest
Device API
UI Package
Device State
```

新增设备主要由设备自身定义驱动。

---

# 53. V3 最核心的一句话

> **Device Definition 是 Source of Truth，Device Studio 是开发入口，ui.pkg 是 UI 分发格式，Virtual Device 是真实设备的 PC 替身，Device SDK 是 MCU 运行时，Protocol 是双方共同语言。**

---
