# BLE 连接与传输性能

**日期：** 2026-09-19
**状态：** 已实施（app 侧） / 部分待验证（真机数据以设备串口 log 为准）
**目标：** 把「连上设备 → UI 可用」和「拉取 ui.pkg」两条路径的耗时压下来，并记录每个瓶颈的根因，避免重复踩坑。

---

# 1. 结论摘要

| 瓶颈 | 根因 | 处置 |
|---|---|---|
| 服务发现慢（860ms） | 每次 GATT 往返都要等一个**连接间隔**，默认 45ms（`conn_interval=36`） | GATT 连上后请求 `highPerformance` → 15ms（`conn_interval=12`），发现降到 **65ms** |
| 请求优先级反而更慢 | FRB 给 `requestConnectionPriority` 硬编码 **2 秒空转**，且这 2 秒**占着 RxAndroidBle 的每连接操作队列**，把后面的服务发现压后 1.7–3.4s | vendor 一份补丁版 `reactive_ble_mobile`（2s → 1ms），见 §3.2 |
| ui.pkg 下载慢 | 每块只有 224B，1.7KB 要 8 个往返；ACK 还占往返 | 分块 224→**512B**（4 块）；ACK 改**无回执写** |
| 连接建立前断开要干等 8 秒 | 链路已断（Android 先打 `close()`/`unregisterApp()`）时，我们只在收到 `connected` 才完成握手，收到 `disconnected` 什么都不做，一直等到超时 | 连接状态流里**收到 `disconnected` 且尚未连上 → 立即失败**（`连接建立前已断开`） |
| 心跳与业务消息抢道 | `startHeartbeat` 立即发首个 PING，而 ReliableChannel 是 **Window=1**：心跳会占掉在途名额，把 UI 资源请求挤后一个往返 | **心跳整体关闭**（见 §3.3）。BLE 链路监督 + `transport.connectionStates` 已覆盖断线感知 |
| 连接参数震荡 | **设备自己**按 `connection_param_table` 反复请求改参数（36→6→36），发现撞上震荡期就被拖长 | 未做（§6 备选：固件关掉 `connection_update_enable`） |

---

# 2. 实测数据

## 2.1 连接阶段（设备串口 log 时间轴）

```text
CONNECT_REQ                     10.729
订阅完成 (cccd fff3=01)          12.175   ← +1.45s：GATT 连接 ~0.45s + 服务发现 ~0.86s + MTU ~0.12s
HELLO                           12.265
HELLO_ACK                       12.268   ← 设备侧 3ms
manifest 请求                    13.041
manifest 响应 (文件系统)          13.056   ← 15ms
```

## 2.2 连接间隔对往返的影响

| 连接间隔 | 服务发现 | 单次往返 |
|---|---|---|
| 45ms（`conn_interval=36`） | ~860ms | ~90ms |
| 15ms（`conn_interval=12`） | **65ms** | ~30ms |

## 2.3 三次"请求高优先级"实验（说明为什么必须打补丁）

| 版本 | 连接阶段 | 连接后→UI | 设备侧间隔轨迹 |
|---|---|---|---|
| 无优先级请求 | **1.45s** | ~1.2s | 36 |
| await 优先级请求 | 2.49s | ~0.3s | 36 → 6 → **12** |
| fire-and-forget（补丁前） | **3.43s** | ~0.7s | 36 → 6 → 36 → **12** |

三种都拿不到"连接阶段 1.45s + 之后 15ms"的组合——因为 2 秒在**原生队列**里，Dart 侧 await 与否都躲不开。

---

# 3. 逐项说明

## 3.1 连接间隔：请求高优先级

`lib/ble/reactive_ble_transport.dart` 的 `_connectInternal()`，GATT 连上后立刻：

```dart
unawaited(_requestHighPriority(deviceId));   // 不能 await
```

- 能力接口 `ConnectionPriorityControl`（`lib/ble/ble_peripheral.dart`）——只有真实 BLE 实现
  （`ReactiveBlePeripheral`）实现它，Fake/虚拟设备不实现，用 `is` 做能力检测跳过，零波及。
- 失败只记日志，不影响功能（提速手段）。
- 设备侧实测接受了：`conn_interval` 由 36 变 12（15ms）。

## 3.2 FRB 的 2 秒坑（本仓库 vendor 补丁）

`flutter_reactive_ble 5.5.0` → `reactive_ble_mobile` → `ReactiveBleClient.kt` 里
`requestConnectionPriority(priority.code, 2, TimeUnit.SECONDS)`；RxAndroidBle 1.16.0 的
`ConnectionPriorityChangeOperation.getCallback()` 直接返回 `Single.timer(2s)`：

1. 这 2 秒是**人为固定延迟**（Android 没有"连接参数更新完成"回调）；
2. 这 2 秒里该操作**一直占着 RxAndroidBle 的每连接操作队列**，紧随其后的
   `discoverServices()` / `requestMtu()` / 读写全部被压后。

处置：`third_party/reactive_ble_mobile/`（vendored 副本，`pubspec.yaml` 里
`dependency_overrides` 指向它），把等待改成 `1, TimeUnit.MILLISECONDS`
（RxAndroidBle 要求 delay > 0）。真正的 `gatt.requestConnectionPriority()` 在
`startOperation()` 里已同步发出，这个值只影响"多久后报告成功"。
细节与升级步骤见 `third_party/reactive_ble_mobile/PATCH.md`。

## 3.3 关闭协议层心跳

**结论**：BLE 不需要应用层心跳。链路本身有链路监督超时（LL supervision timeout），
断线由 Android 上报、经 FRB 的 `connectionStates` 流到 `DeviceSessionController`
（连接期与重连期都已订阅），协议层再叠一层 PING/PONG 是多余的；
而 ReliableChannel 是 `Window=1`（一次只允许一条在途消息），心跳还会**抢占在途名额**，
把 UI 资源请求这类要紧的消息挤后一个往返。

**开关**（`lib/providers/device_session_provider.dart`）：

```dart
/// 心跳开关 (Phase 12 §22 扩展)。**当前关闭**：BLE 链路本身有链路监督超时，
/// 断线由 transport 的 connectionStates 上报……需要时改回 true 即恢复。
static bool heartbeatEnabled = false;
```

`connect()` 与重连路径里的 `client.startHeartbeat(...)` 都加了 `if (heartbeatEnabled)` 守卫；
`DeviceClient` 的 PING/PONG 实现**原样保留**，改回 `true` 即恢复，无需改其他代码。
单测「心跳失联 → 会话 disconnected」显式把开关打开后再测该路径。

**权衡**：关掉后"设备半死不活但其实没断链"的情况不会被心跳发现（例如设备固件卡住但仍回链路层 ACK）。
真需要这种探测时把开关打开即可。

## 3.4 失败要快：连接建立前断开就立刻报错

Android 侧若链路失败（设备拒绝、超时、`status=133/62` 等），GATT 层会先打
`close()` + `unregisterApp()`，FRB 随后在连接状态流里发 `disconnected`。
我们原先只在等到 `connected` 时才完成握手 Completer，收到 `disconnected` 什么都不做，
于是**白等到 `connectTimeout`（8s）**才报超时。

现在 `lib/ble/reactive_ble_transport.dart` 的 `_connectInternal()`：

```dart
} else if (state == BleConnectionState.disconnected) {
  // 还没连上就收到 disconnected：链路已断/被设备拒绝，立刻失败
  connected.completeError(StateError('连接建立前已断开 ($deviceId)'));
}
```

对应单测：`test/ble/reactive_ble_transport_test.dart` 的
「连接建立前就断开 → 立刻失败，不等超时」。

## 3.5 资源分块与 ACK

- **分块**：`sdk/device/core/runtime/device_runtime.c` 的 `RESOURCE_CHUNK_MAX` 224 → **512**
  （配合 `DEVICE_RUNTIME_JSON_MAX` 512 → 1024，因为 base64 后响应约 754B）。
  1.7KB 的 ui.pkg 从 8 块降到 4 块。
- **ACK**：`lib/protocol/reliable_channel.dart` 的 `_sendAck` 改用
  `transport.writeWithoutResponse()`（Android writeWithoutResponse）——ACK 不需要 GATT 写响应，
  省掉一次往返等待；丢了由对方的超时重传兜底。设备侧特征本身就支持
  `WRITE_WITHOUT_RESPONSE`（FFF1 = `0x0c`）。
- 三条路径的层级说明（为什么"一段一段"）：小消息一帧一次 BLE 写；大消息在协议层**分片**
  成多帧（`tx frame=49 len=366 frags=2`）；每块都有请求 + ACK 两次写。
  MTU 247 时单帧有效载荷 244B（减 9B 帧头）。

---

# 4. 改动文件

| 文件 | 改动 |
|---|---|
| `third_party/reactive_ble_mobile/**` | vendored 副本（+ `PATCH.md` 记录补丁） |
| `pubspec.yaml` | 增加 `dependency_overrides: reactive_ble_mobile` 指向本地 |
| `lib/ble/ble_peripheral.dart` | 新增能力接口 `ConnectionPriorityControl` |
| `lib/ble/reactive_ble_peripheral.dart` | 实现优先级请求（FRB 映射） |
| `lib/ble/reactive_ble_transport.dart` | GATT 连上后 fire-and-forget 请求高优先级；`writeWithoutResponse` |
| `lib/ble/ble_transport.dart` | 新增 `writeWithoutResponse` |
| `lib/protocol/reliable_channel.dart` | ACK 改无回执写 + `发送 ACK msgId/seq` 日志 |
| `sdk/device/core/runtime/device_runtime.{c,h}` | 分块 512B、JSON 缓冲 1024B、设备侧逐步日志 |

---

# 5. 验证清单

真机（**重新 build 安装**，改构造默认值时 hot reload 不生效）：

1. **app 侧**（`adb logcat | grep -iE "flutter|BluetoothGatt"`）：
   - `GATT 已连接 (~600ms)` → `已请求高优先级连接` → `服务发现完成` 应 **< 1.0s**（不是 2.7–3.4s）
   - `MTU=247` / `已订阅 0000fff3`
   - 握手：`发送 msgId=0` 之后不应出现 `重发`
2. **设备侧**（串口 log）：
   - `cccd fff3=01` 出现在连接后 ~1.5s 内
   - `conn_interval = 12`（15ms）尽快稳定，不再长时间卡在 36
   - `[myhome] rx frame type=32` … `tx frame=33` 的往返应降到 30–100ms
3. **全量下载**（先清 App 的 UI 缓存 / 或在 Studio 改一次 UI 让版本变化）：
   - 设备日志里 `rx frame type=48` 应为 **4 次**（512B/块），不再是 9 次
   - 总耗时显著低于改前的 ~5.6s

---

# 6. 仍未做的优化（按收益排序）

1. **固件**：`apps/.../rcsp/ble_rcsp_server.c:112` `connection_update_enable = 1 → 0`，
   关掉设备自己的连接参数震荡（发现不再被撞）。
   ⚠️ 以后要用 RCSP 音频流/低延迟场景时需恢复。
2. **连接后那几处 120–210ms 间隙**（总计 ~0.7s）：**已确认不是 app 侧的重建或 CPU**——
   初始连接期间没有任何已挂载 widget watch 会话状态，Dart 侧同步工作量在个位数 ms 级
   （详见 §7 归因）。当前证据指向 **Dart isolate 之外**：Android BLE 通知投递/写队列/连接间隔，
   以及 **debug 构建（JIT / VM service）** 的调度开销。
   下一步：用 `flutter run --profile`（AOT，≈ release 性能）复测；若间隙仍在，
   在 `lib/protocol/reliable_channel.dart` 的通知入口再打时间戳，区分"系统投递延迟"与"Dart 调度延迟"。
3. **协议往返数**：HELLO_ACK 直接带状态（省一个 STATE_REQUEST→STATE 往返）；
   MTU 协商挪到 UI 加载之后；`ReliableChannel` 的 `Window=1` 放宽以支持并行请求。

---

# 7. 归因记录：连接后的间隙到底在哪

实测（2026-09-19 设备串口日志）连接建立后的三个往返：

```text
12.540 HELLO        ← app 处理 +101ms
12.543 HELLO_ACK    ← 设备 3ms
12.754 app ACK      ← 间隙 211ms
12.802 STATE_REQUEST← +48ms
12.805 STATE        ← 设备 3ms
13.009 app ACK      ← 间隙 204ms
13.065 manifest 请求 ← +56ms
13.082 manifest 响应 ← 设备 17ms
13.204 app ACK      ← 间隙 122ms
```

ACK 是 `ReliableChannel` 在**消息组装完成的同一个回调里同步发出**的
（`lib/protocol/reliable_channel.dart` 的 `_sendAck`），所以这些间隙不可能来自
"app 处理完才回话"，只可能来自**通知送达 app 之前**或 **ACK 写出之后的投递**。

逐项排查（读码确认，非推测）：

| 嫌疑 | 结论 |
|---|---|
| Riverpod 重建 | **排除**。初始连接期间没有一个已挂载 widget watch `deviceSessionProvider` / `connectionPhaseProvider`；`deviceManagerProvider` 全工程只有 `ref.read` |
| 主 isolate 上的重活 | **排除**。全工程无 `Isolate`/`compute`；每块 `base64Decode`+`jsonDecode` 是 µs 级；1.7KB 包的 `sha256`+`gunzip`+`untar` 亚毫秒 |
| 日志 | 可忽略（三个往返共 ~10 行 `print`） |
| WebView 初始化 | 发生在 manifest 之后（`pushReplacement` 才建），不在这些间隙里 |
| **Android BLE 投递 + 队列 + 连接间隔** | **主要嫌疑**：这段仍在 45ms 间隔（`conn_interval` 直到 12.736 才降到 12），且 `writeWithoutResponse` 仍要排进 FRB/RxAndroidBle 队列 |
| **debug 构建（JIT / VM service）** | **次要嫌疑**：所有数据来自 `flutter run` debug 版 |

---

# 8. 顺带发现：release 包缺 INTERNET 权限（发布阻塞）

`android/app/src/main/AndroidManifest.xml` 原本**没有** `INTERNET` 权限——Flutter 模板只在
`src/debug/`、`src/profile/` 的 manifest 里声明。而本地 UI 服务器是 `shelf_io.serve`
（`lib/ui_runtime/ui_server.dart`），Android 对任何 socket（含 127.0.0.1 回环）都要求该权限：

```
release 包 → shelf_io.serve 抛 SocketException → uiServerStartFailed → UI 永远加载不出来
```

已修：主 manifest 补上 `<uses-permission android:name="android.permission.INTERNET" />`。
发布前请用 `flutter build apk --release` 装一次，确认 UI 能正常加载。
