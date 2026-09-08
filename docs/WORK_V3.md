# Device Studio / Device UI Platform

# WORK_V3.md

> Version: 3.0
> Purpose: Development Workflow / Implementation Plan

---

# 1. 总体开发目标

最终实现：

```text
PC
│
├── Device Definition
├── UI Development
├── UI Package Builder
├── Device Studio
├── Virtual Device
├── Protocol Debugger
└── Code Generator
        │
        ▼
   Real Device SDK
        │
        ▼
       MCU
```

第一阶段不追求：

```text
Cloud
OTA
账号系统
大规模设备管理
```

首先完成：

> **PC 上完整模拟一个真实设备 + UI + Protocol 的闭环。**

---

# 2. V3 第一目标

选择：

```text
Smart Light
```

作为第一个参考设备。

功能：

```text
Power
Brightness
Color Temperature
```

必须实现：

```text
Flutter Desktop
      ↓
ui.pkg
      ↓
WebView
      ↓
Device API
      ↓
DeviceClient
      ↓
Protocol
      ↓
SimulatorTransport
      ↓
VirtualLight
      ↓
VirtualHardware
```

---

# 3. MVP 验收标准

必须完成：

```text
1. 创建 device.yaml
2. 生成 Device Definition
3. 创建 UI
4. 打包 ui.pkg
5. Device Studio 加载 ui.pkg
6. 启动 Virtual Device
7. WebView 显示 UI
8. UI 获取 State
9. UI 发送 Command
10. Simulator 接收 Command
11. 修改 Virtual State
12. 返回 Response
13. 产生 Event
14. WebView 更新
15. Protocol Console 显示 TX/RX
16. Reset Device
17. Disconnect / Reconnect
```

完成以上内容后，V3 才算真正跑通。

---

# 4. Phase 0 — 工程初始化

建立：

```text
device-platform/
├── tools/
├── studio/
├── sdk/
├── protocol/
└── devices/
```

Flutter Studio：

```text
studio/flutter/
```

创建：

```text
Windows
macOS
```

目标：

```text
flutter run -d windows
flutter run -d macos
```

验收：

```text
Windows 可以启动
macOS 可以启动
```

---

# 5. Phase 1 — Device Definition

实现：

```text
device.yaml
```

解析：

```text
DeviceDefinition
StateDefinition
CommandDefinition
EventDefinition
CapabilityDefinition
```

Dart：

```dart
class DeviceDefinition {}

class StateDefinition {}

class CommandDefinition {}

class EventDefinition {}
```

验收：

```text
device.yaml
      ↓
Dart Object
      ↓
正确读取
```

---

# 6. Phase 2 — Schema Validation

增加验证：

```text
device.id
device.model
protocol.version
api.version
state
commands
events
```

错误示例：

```text
missing device.id
invalid state type
invalid command parameter
duplicate command
unsupported type
```

CLI：

```bash
device validate device.yaml
```

验收：

```text
正确文件 → PASS
错误文件 → 明确 ERROR
```

---

# 7. Phase 3 — Protocol Frame

实现：

```text
FrameEncoder
FrameDecoder
CRC16
Sequence
Length
Type
Flags
```

格式：

```text
VER
TYPE
FLAGS
SEQ
LENGTH
PAYLOAD
CRC16
```

测试：

```text
正常 Frame
空 Payload
最大 Payload
错误 CRC
错误 Length
错误 Version
错误 Type
```

---

# 8. Phase 4 — Codec

先实现：

```text
JsonCodec
```

接口：

```dart
abstract class Codec {

  List<int> encode(Object message);

  Object decode(List<int> data);
}
```

测试：

```text
COMMAND
RESPONSE
EVENT
STATE
PATCH
```

后续再实现：

```text
CBOR
MessagePack
Binary Codec
```

不要在 MVP 阶段同时实现多个 Codec。

---

# 9. Phase 5 — Fragment

实现：

```text
FragmentEncoder
FragmentDecoder
FragmentAssembler
```

处理：

```text
MSG_ID
INDEX
TOTAL
LENGTH
DATA
```

必须测试：

```text
正常顺序
乱序
重复
丢失
超时
错误 TOTAL
错误 LENGTH
```

测试 Payload：

```text
100B
500B
1KB
5KB
10KB
50KB
```

---

# 10. Phase 6 — Transport

先不要做 BLE。

首先：

```text
SimulatorTransport
```

接口：

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
SimulatorTransport
```

可以直接在内存中：

```text
Flutter
   ↕
Memory Channel
   ↕
Virtual Device
```

---

# 11. Phase 7 — Virtual Device

创建：

```text
VirtualDevice
```

接口：

```dart
abstract class VirtualDevice {

  Future<void> start();

  Future<void> stop();

  Future<void> reset();

  DeviceState get state;

  Future<void> handleCommand(...);
}
```

实现：

```text
VirtualLight
```

状态：

```text
power
brightness
color_temperature
```

---

# 12. Phase 8 — Virtual Hardware

创建：

```text
VirtualHardware
```

实现：

```text
VirtualPwm
VirtualGpio
VirtualSensor
```

例如：

```text
brightness
    ↓
VirtualPwm
    ↓
PWM = 80
```

---

# 13. Phase 9 — Device Logic

实现：

```text
LightDeviceLogic
```

负责：

```text
setPower
setBrightness
setColorTemperature
```

不负责：

```text
BLE
WebView
HTTP
Flutter Widget
```

---

# 14. Phase 10 — DeviceClient

实现：

```text
DeviceClient
```

负责：

```text
Command
Response
Event
State
Request ID
```

示例：

```dart
await device.command(
  "light.set_brightness",
  {
    "value": 80,
  },
);
```

验收：

```text
DeviceClient
    ↓
Protocol
    ↓
SimulatorTransport
    ↓
VirtualDevice
```

完整跑通。

---

# 15. Phase 11 — Device API

建立统一 API：

```text
getDeviceInfo()
getState()
command()
subscribeEvent()
```

Flutter 不应该直接调用：

```text
Protocol
Transport
Frame
Fragment
```

业务层只调用：

```text
DeviceClient
```

---

# 16. Phase 12 — Riverpod

建立：

```text
DeviceManagerProvider
DeviceSessionProvider
DeviceStateProvider
ConnectionStateProvider
ManifestProvider
```

结构：

```text
DeviceManager
    │
    ├── Session A
    ├── Session B
    └── Session C
```

验收：

```text
Simulator State
      ↓
DeviceClient
      ↓
Riverpod
      ↓
Flutter UI
```

---

# 17. Phase 13 — UI Package

建立：

```text
ui_builder
```

输入：

```text
ui/
├── manifest.json
├── index.html
├── app.js
├── style.css
└── assets/
```

输出：

```text
build/ui.pkg
```

命令：

```bash
device ui build
```

---

# 18. Phase 14 — UI Package Validation

执行：

```bash
device ui validate ui.pkg
```

检查：

```text
manifest
entry
version
device type
protocol version
hash
required files
```

错误必须明确。

例如：

```text
UI package entry not found
Protocol version mismatch
Invalid manifest
Missing index.html
```

---

# 19. Phase 15 — UI Runtime

Device Studio 加载：

```text
ui.pkg
```

流程：

```text
ui.pkg
 ↓
extract
 ↓
local HTTP server
 ↓
WebView
```

HTTP：

```text
127.0.0.1:<random-port>
```

---

# 20. Phase 16 — UI Adapter

实现：

```text
GET /api/device
GET /api/state
POST /api/command
GET /api/manifest
WebSocket /api/events
```

Command：

```json
{
  "request_id": 1,
  "cmd": "light.set_brightness",
  "params": {
    "value": 80
  }
}
```

---

# 21. Phase 17 — WebSocket

实现：

```text
DeviceState
DeviceEvent
DevicePatch
```

流程：

```text
Virtual Device
      ↓
DeviceClient
      ↓
Riverpod
      ↓
WebSocket
      ↓
WebView
```

---

# 22. Phase 18 — Device Studio

建立：

```text
Device Studio
```

页面：

```text
Device List
Simulator
UI Preview
Inspector
Protocol Console
Logs
```

第一版不追求漂亮。

重点是：

```text
能调试
能看到数据
能控制设备
```

---

# 23. Phase 19 — Inspector

显示：

```text
Device ID
Model
Protocol
API Version
UI Version
State Version
Connection
```

State：

```text
power
brightness
color_temperature
```

Command：

```text
light.set_power
light.set_brightness
light.set_color_temperature
```

---

# 24. Phase 20 — Protocol Console

显示：

```text
TX
RX
```

每条显示：

```text
Timestamp
Direction
Frame Type
SEQ
Length
Payload
CRC
```

例如：

```text
12:30:01 TX COMMAND
SEQ=100
LEN=18
01 01 00 64 ...

12:30:01 RX RESPONSE
SEQ=101
LEN=20
01 02 00 65 ...
```

---

# 25. Phase 21 — Fault Injection

实现：

```text
Packet Loss
Packet Delay
Packet Duplicate
CRC Error
Timeout
Disconnect
Wrong Sequence
```

UI：

```text
Packet Loss: 10%
Delay: 100ms
```

---

# 26. Phase 22 — Reconnect

模拟：

```text
Connected
 ↓
Disconnect
 ↓
Reconnecting
 ↓
Connecting
 ↓
Handshake
 ↓
Sync State
 ↓
Connected
```

必须重新：

```text
HELLO
HELLO_ACK
State Sync
```

不能假设旧 Session 仍然有效。

---

# 27. Phase 23 — State / Patch

实现：

```text
Full State
Patch
State Version
```

测试：

```text
100
101
102
```

人为制造：

```text
100
102
```

必须自动：

```text
Request Full State
```

---

# 28. Phase 24 — Command Queue

实现：

```text
Serial
Replaceable
Cancelable
```

重点测试：

```text
brightness slider
```

快速变化：

```text
10
20
30
40
50
60
70
80
```

可以只发送：

```text
80
```

---

# 29. Phase 25 — Code Generator

输入：

```text
device.yaml
```

输出：

```text
generated/
├── dart/
├── c/
├── simulator/
└── manifest/
```

第一版只生成：

```text
device_api.h
device_api.c
device_state.h
device_state.c
device_commands.c
device_api.dart
virtual_device.dart
manifest.json
```

---

# 30. Phase 26 — C Device SDK

建立：

```text
sdk/device/
```

提供：

```text
Protocol
Frame
Codec
Fragment
Command Router
State Manager
Event Manager
Transport Interface
```

---

# 31. Phase 27 — Hardware Adapter

定义：

```c
typedef struct {
    void (*set_power)(bool value);
    void (*set_brightness)(uint8_t value);
    uint16_t (*get_temperature)(void);
} HardwareAdapter;
```

真实设备：

```text
RealHardwareAdapter
```

模拟：

```text
VirtualHardwareAdapter
```

---

# 32. Phase 28 — 第一个真实设备

选择一个最简单设备：

```text
Smart Light
```

硬件：

```text
MCU
BLE
PWM
```

实现：

```text
BLE Transport
      ↓
Protocol
      ↓
Device SDK
      ↓
Generated Code
      ↓
Light Hardware
```

---

# 33. Phase 29 — BLE Transport

这时候才实现：

```text
BleTransport
```

接口和：

```text
SimulatorTransport
```

完全相同。

Flutter：

```text
DeviceClient
     │
 Protocol
     │
 Transport
     │
 ┌───┴────┐
 ▼        ▼
Simulator BLE
```

---

# 34. Phase 30 — Simulator / Real Device 一致性测试

同一个测试：

```text
set brightness = 80
```

必须分别测试：

```text
Simulator
Real Device
```

两边结果：

```text
State
Response
Event
```

必须一致。

---

# 35. Phase 31 — Package Cache

实现：

```text
UI Cache
```

Key：

```text
device type
model
version
hash
```

测试：

```text
第一次 → 下载/安装
第二次 → Cache Hit
Version Changed → Update
Hash Changed → Update
Corrupted → Reinstall
```

---

# 36. Phase 32 — Logging

统一日志：

```text
TRACE
DEBUG
INFO
WARN
ERROR
```

格式：

```text
timestamp
level
module
device
seq
request_id
message
```

---

# 37. Phase 33 — Testing

Protocol：

```text
CRC
Length
Version
Type
Sequence
```

Fragment：

```text
Loss
Duplicate
Out-of-order
Timeout
```

Device：

```text
Reset
Reconnect
State Sync
Command
Event
```

UI：

```text
Load
Reload
Cache
Corrupted Package
Version Mismatch
```

---

# 38. Phase 34 — Stress Test

Payload：

```text
100B
500B
1KB
5KB
10KB
50KB
```

测试：

```text
Packet Loss = 0%
Packet Loss = 1%
Packet Loss = 5%
Packet Loss = 10%
```

观察：

```text
Throughput
Retry
Latency
Memory
CPU
```

---

# 39. Phase 35 — App Crash Recovery

测试：

```text
WebView Crash
HTTP Server Restart
Flutter App Restart
Device Restart
BLE Disconnect
```

要求：

```text
重新建立 Session
重新 Handshake
重新同步 State
```

---

# 40. Phase 36 — Security

MVP：

```text
Session Token
```

Production：

```text
Device Identity
Challenge
Authentication
Session Key
Encryption
```

---

# 41. Phase 37 — UI Hot Reload

开发目录：

```text
ui/
```

监听：

```text
HTML
JS
CSS
Assets
```

修改后：

```text
File Changed
 ↓
Build
 ↓
Reload WebView
```

目标：

> UI 开发体验接近 Flutter Hot Reload。

---

# 42. Phase 38 — Device Studio 完善

最终增加：

```text
Device Manager
Package Manager
Simulator Manager
Inspector
Protocol Analyzer
Log Viewer
Performance
Fault Injection
Code Generator
```

---

# 43. 推荐 CLI

最终提供：

```bash
device create
device validate
device build
device simulate
device ui build
device ui validate
device generate
device test
```

例如：

```bash
device create smart_light
```

生成：

```text
devices/smart_light/
├── device.yaml
├── ui/
├── simulator/
└── generated/
```

---

# 44. 一个完整设备开发示例

创建：

```bash
device create smart_light
```

编辑：

```text
device.yaml
```

开发：

```text
ui/
```

构建：

```bash
device ui build
```

生成：

```text
ui.pkg
```

启动：

```bash
device simulate smart_light
```

或者：

```text
打开 Device Studio
```

选择：

```text
Smart Light
```

然后：

```text
Load ui.pkg
Start Simulator
```

---

# 45. 完整测试闭环

最终必须能够：

```text
点击 UI
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
SimulatorTransport
   ↓
Virtual Device
   ↓
Device Logic
   ↓
Virtual Hardware
   ↓
State Changed
   ↓
DeviceClient
   ↓
Riverpod
   ↓
WebSocket
   ↓
WebView
   ↓
UI 更新
```

这是 V3 最重要的验收流程。

---

# 46. Git 分阶段

建议：

```text
main
develop
```

功能：

```text
feature/protocol
feature/simulator
feature/device-client
feature/ui-runtime
feature/device-studio
feature/codegen
feature/device-sdk
feature/ble
```

Milestone：

```text
v3.0-protocol
v3.1-simulator
v3.2-ui-runtime
v3.3-device-studio
v3.4-codegen
v3.5-device-sdk
v3.6-real-device
```

---

# 47. 开发优先级

必须严格按照：

```text
Protocol
   ↓
Simulator
   ↓
DeviceClient
   ↓
UI Runtime
   ↓
Device Studio
   ↓
Code Generator
   ↓
Device SDK
   ↓
BLE
```

不要一开始就：

```text
BLE
Cloud
OTA
账号
服务器
```

---

# 48. MVP 不做什么

第一版不做：

```text
Cloud
User Account
Remote Control
OTA
Device Marketplace
Plugin System
复杂权限系统
多协议同时支持
复杂 UI Editor
```

只做：

```text
Smart Light
Simulator
UI Package
Device Studio
Protocol
DeviceClient
Code Generator
```

---

# 49. V3 第一里程碑

完成：

```text
device.yaml
     ↓
Virtual Light
     ↓
DeviceClient
     ↓
Device Studio
     ↓
ui.pkg
     ↓
WebView
```

用户点击：

```text
Brightness = 80
```

模拟设备：

```text
brightness = 80
```

UI：

```text
显示 80
```

---

# 50. V3 第二里程碑

完成：

```text
Protocol
Frame
Fragment
ACK
Retry
State
Patch
Event
```

并能在 Protocol Console 看到完整通信。

---

# 51. V3 第三里程碑

完成：

```text
device.yaml
      ↓
Code Generator
      ↓
C
Dart
Simulator
Manifest
```

---

# 52. V3 第四里程碑

完成：

```text
C Generated Code
       ↓
Device SDK
       ↓
MCU
       ↓
BLE
       ↓
Flutter Mobile App
```

---

# 53. 最终验收

真实设备和模拟设备都必须支持：

```text
HELLO
COMMAND
RESPONSE
EVENT
STATE
PATCH
ACK
NACK
PING
PONG
```

并支持：

```text
Fragment
Retry
Reconnect
State Sync
```

---

# 54. 最终开发体验

开发者只需要：

```text
1. 定义 device.yaml
2. 开发 UI
3. device ui build
4. Device Studio 模拟
5. 调试 Protocol
6. 测试异常
7. device generate
8. 拷贝 generated/c
9. 放入 Device SDK
10. 编译 MCU
```

理想情况下：

> **没有真实硬件，也可以完成 90% 以上的设备 UI 和协议开发。**

---

# 55. V3 最终产品架构

```text
                         Device Studio
                              │
       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
       ▼                      ▼                      ▼
   UI Package            Simulator              Codegen
       │                      │                      │
       ▼                      ▼                      ▼
    WebView             Virtual Device          C / Dart
       │                      │                      │
       └──────────────┬───────┘                      │
                      ▼                              │
                 Device API                         │
                      │                              │
                 DeviceClient                        │
                      │                              │
                   Protocol                          │
                      │                              │
              ┌───────┴────────┐                     │
              ▼                ▼                     │
          Simulator           BLE                    │
              │                │                      │
              ▼                ▼                      │
       Virtual Hardware   Real Hardware               │
                                                   Device SDK
                                                       │
                                                       ▼
                                                      MCU
```

---

# 56. V3 最终目标

最终形成：

```text
                    Device Platform
                           │
          ┌────────────────┼────────────────┐
          │                │                │
       UI SDK         Device SDK      Simulator SDK
          │                │                │
       ui.pkg          Firmware        Virtual Device
          │                │                │
          └────────────────┼────────────────┘
                           │
                    Device Studio
                           │
                 Windows / macOS
                           │
                    Development
                           │
                    Real Device
```

核心思想：

> **一份 Device Definition，生成多端代码；一套 Protocol，连接模拟设备和真实设备；一个 Device Studio，完成从 UI 到 Firmware 的大部分开发。**

---

# 57. V3 开发完成定义

当以下流程全部成功时，认为 V3 基础架构完成：

```text
device.yaml
    ↓
生成 Dart / C / Simulator
    ↓
UI build
    ↓
ui.pkg
    ↓
Device Studio
    ↓
WebView
    ↓
Device API
    ↓
DeviceClient
    ↓
Protocol
    ↓
SimulatorTransport
    ↓
Virtual Device
    ↓
Virtual Hardware
    ↓
State / Event
    ↓
WebSocket
    ↓
UI 更新
    ↓
Code Generator
    ↓
C Code
    ↓
Device SDK
    ↓
Real MCU
```

最终目标不是“做一个 App”。

而是：

> **建立一套让设备厂商可以在 PC 上开发、模拟、测试、打包 UI，并最终生成真实设备代码的完整 Device UI 开发平台。**

---
