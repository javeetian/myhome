# WORK_EXECUTE_V2.md

# WORK_V2 执行情况记录

**版本：** V2.0
**文档类型：** EXECUTE / 执行记录
**最后更新：** 2026-09-08
**对应计划：** [WORK_V2.md](WORK_V2.md)（计划文档保持不变，执行状态只记录在本文件）

---

# 0. 文档定位

```text
WORK_V2.md      → 计划 ("每个阶段做什么、如何验证")
WORK_EXECUTE_V2.md → 执行 ("每个阶段实际做了什么、验证结果、遗留问题")
```

WORK_V2.md §50 的检查清单**不在原文档勾选**，状态统一维护在本文件。

---

# 1. 执行状态总览

```text
Phase 0  环境与工程初始化      ✅ 完成 (2026-09-08)
Phase 1  BLE Transport         ✅ 代码完成，真机验收 ⏸ 待硬件
Phase 2  Frame + CRC           ✅ 完成 (2026-09-08，纯 Dart 无硬件依赖)
Phase 3  Fragment              ✅ 完成 (2026-09-08，纯 Dart)
Phase 4  ACK / Retry / Queue   ✅ 完成 (2026-09-08，纯 Dart)
Phase 5  Device Protocol       ✅ 完成 (2026-09-08，纯 Dart)
Phase 6  DeviceClient          ✅ 完成 (2026-09-08，纯 Dart)
Phase 7  Riverpod              ✅ 完成 (2026-09-08)
Phase 8  UI Adapter            ⬜ 未开始 (下一目标)
Phase 9  WebView Runtime       ⬜ 未开始
Phase 10 Manifest / UI Package ⬜ 未开始
Phase 11 State / Patch / Event ⬜ 未开始
Phase 12 Security / Production ⬜ 未开始
```

对应 WORK_V2 §50 清单：

```text
1. 创建 Flutter 工程        ✅
2. 加入 Riverpod            ✅
3. 加入 BLE Plugin          ✅
4. 实现 BleTransport        ✅ (代码 + 单测)
5. 建立 ESP32/AC7014 GATT   ⏸ 需要硬件 (见 §2)
6. Flutter ↔ Device 双向通信 ⏸ 需要硬件；回环 echo 单测已就绪
7. 实现 BLE Frame           ✅
8. 实现 CRC                ✅
9. 实现 Fragment           ✅
10. 实现 ACK               ✅
11. 实现 Retry             ✅
12. 实现 Device Protocol   ✅ (消息模型 + JSON Codec；DeviceClient 下一阶段)
13. 实现 DeviceClient      ✅
14. 接入 Riverpod          ✅ (会话控制器 + provider 族)
```

---

# 2. ⚠️ 硬件依赖（阻塞项）

> **Phase 1 真机验收与设备固件相关项阻塞于缺少真实 BLE 硬件。**
> Phase 2/3/4 (Frame / Fragment / ACK) 为纯 Dart，不受硬件阻塞。

按 WORK_V2 §30，MVP 至少需要：

```text
ESP32 开发板 ×1
(或 AC7014 模块 ×1)
```

缺少硬件的直接后果：

| 阻塞项 | 对应 WORK_V2 | 说明 |
|---|---|---|
| Flutter ↔ Device 真机双向通信验收 | §6.5 / §6.6 / §50-6 | 回环 echo 单测 (test/ble/echo_test.dart) 已覆盖 1/10/100/200/500/1000 字节，真机未验 |
| MTU 实际协商验证 | §6.4 | 代码按协商结果保存 MTU，真机行为未验 |
| 固件 GATT 服务建立 | §40 / §50-5 | 设备端 TX/RX 特征与 BleConstants UUID 对齐待做 |
| Phase 1 完成条件 | §6.6 | "Flutter ↔ Device 稳定双向通信" 未真机证明 |

**硬件到位后待执行的验收动作：**

```text
1. 设备端建立 GATT：service/tx/rx = lib/ble/ble_constants.dart 中的 UUID
2. 设备端 echo 固件：Notify 原样返回 Write 字节
3. 真机跑通 echo 大小矩阵 (1/10/100/200/500/1000 字节)
4. 记录实际协商 MTU 与吞吐量基线 (供 Phase 2 分片设计参考)
```

---

# 3. Phase 0 执行记录 ✅

**日期：** 2026-09-08

## 3.1 完成内容

- 目录结构补齐：`lib/protocol/`、`lib/storage/`（§5.2 要求的 7 个目录齐备）
- 依赖齐备：flutter_riverpod / webview_flutter / flutter_reactive_ble / shelf / web_socket_channel

## 3.2 验证结果（§5.4 完成条件）

| 条件 | 结果 |
|---|---|
| flutter analyze | ✅ 无问题 |
| flutter test | ✅ 通过 |
| flutter run (Chrome) | ✅ 扫描页 6/6 UI 元素渲染 + 零控制台错误（headless Chrome 驱动验证） |
| iOS Build | ✅ Runner.app 30.5MB（--no-codesign） |
| Android Build | ✅ app-debug.apk |

## 3.3 过程中修复的问题

1. **flutter_riverpod 版本冲突**：SDK 3.11.5 无法用 riverpod 3.4.x（需 Dart ≥3.12），
   约束改为 `^3.3.2`。升级 Flutter 到 3.47.2 后可恢复 3.4.x。
2. **permission_handler 14.x 构建失败**：其 android 插件构建脚本面向 AGP 9 / Gradle 9，
   与工程 (AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20) 不兼容。
   解决：permission_handler `^13.0.2` → `^12.0.3`（配 android 13.0.1 旧式脚本）。
   工具链升级 AGP 9 后可恢复。
3. **BleScanner 平台判断 bug**：`Platform.isMacOS` 在 web 上反映浏览器宿主 OS，
   导致 web 误构造 FlutterReactiveBle（FRB 仅支持 Android/iOS）。
   修复：先判 `kIsWeb`，支持白名单只留 Android/iOS。
4. **widget 测试挂起**：真实 FRB 内部定时器导致测试失败。
   解决：测试注入 FakeBleScanner（Riverpod override），生产代码零改动。

## 3.4 遗留

- `flutter doctor`：Android SDK 缺 cmdline-tools、license 未接受（不影响构建，影响工具链维护）。

---

# 4. Phase 1 执行记录 ✅（代码）/ ⏸（真机）

**日期：** 2026-09-08

## 4.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/ble/ble_constants.dart | §6.3 | UUID 统一管理（service/tx/rx/uiBundle） |
| lib/ble/ble_transport.dart | §6.1 | 字节级抽象：connect/disconnect/write/notifications/requestMtu |
| lib/ble/ble_peripheral.dart | §5.2 | 插件窄接口接缝（可注入 Fake） |
| lib/ble/reactive_ble_peripheral.dart | §5.2 | flutter_reactive_ble 适配器 |
| lib/ble/reactive_ble_transport.dart | §6.2/6.4 | 连接流程：Connect → MTU 协商 → GATT 校验 → 订阅 RX；MTU 拒绝回退 23；失败路径清理；连接状态流 |

## 4.2 重构

- 原 lib/ble/ble_transport.dart（混入 JSON 协议，违反 §2.1 分层纪律）
  → 改名 `BleDeviceSession` 迁至 lib/device/ble_device_session.dart，
  标注 TODO：Phase 5+ 重建于新 Transport 之上。

## 4.3 测试（15/15 通过）

| 文件 | 覆盖 |
|---|---|
| test/ble/reactive_ble_transport_test.dart | 11 例：MTU 协商值生效 / MTU 拒绝回退 / 缺服务失败清理 / 缺特征失败 / 连接超时 / write 路由 TX / Notify 转发 / 未连接守卫 / 重复连接 / 断开语义 / 自发断开 / echo 回环 |
| test/ble/echo_test.dart | §6.5 大小矩阵 1/10/100/200/500/1000 字节 + 5KB 往返 |
| test/ble/fake_ble_peripheral.dart | 可脚本化假外设 |
| test/ble/fake_ble_transport.dart | 回环假传输（§11.4 MockBleTransport 雏形） |

## 4.4 未完成（均待硬件，见 §2）

- §6.5 真机验证
- §6.6 完成条件（真机稳定双向通信）

---

# 5. Phase 2 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（Frame 编解码为纯 Dart，单测完全覆盖 §7.5 矩阵）

## 5.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/protocol/crc16.dart | §7.3 | CRC-16/CCITT-FALSE（poly 0x1021, init 0xFFFF, 无反射）；已知答案锚点 "123456789" → 0x29B1；支持增量计算 |
| lib/protocol/ble_frame.dart | §7.2 | BleFrame encode/decode/validate；头部 7B (VER+TYPE+FLAGS+SEQ+LENGTH，大端)；FrameType 合法值注册；FrameException |
| lib/protocol/frame_sequencer.dart | §7.4 | SEQ 生成器，2 字节回绕 (65535 → 0) |

## 5.2 设计决策（固件侧需对齐）

- 字节序：SEQ / LENGTH / CRC 全部大端
- CRC 覆盖 Header + Payload（不含 CRC 字段本身）
- 最大 Payload 65535（LENGTH 2 字节上限）
- decode 为严格定长（恰好一帧）；粘包/半包归 Phase 3 Assembler
- 校验顺序：长度 → CRC → 字段合法性（Version/Type）；CRC 错误优先于字段错误
- FrameType 当前合法值：0x01-0x05（§10.1 数据帧预注册）、0x10/0x11（§9.1 ACK/NACK）；Phase 4/5 扩展
- SEQ 仅 Transport 使用，禁止作业务 Request ID（§7.4）

## 5.3 测试（§7.5 矩阵全部覆盖）

| 用例 | 结果 |
|---|---|
| 正常 Frame 全字段往返 | ✅ |
| 空 Payload | ✅ |
| 最大 Payload 65535 字节 | ✅ |
| CRC 错误（Payload 翻转 / 头部翻转） | ✅ |
| Length 错误（声明不符 / 截断 / 不足头部） | ✅ |
| Version 错误（CRC 合法的坏版本帧） | ✅ |
| 非法 Type（CRC 合法的未注册 TYPE 帧） | ✅ |
| SEQ 溢出（65535 → 0 回绕） | ✅ |
| CRC16 已知答案 ×3 + 单字节翻转检测 + 增量一致性 | ✅ |

全套单测 34/34 通过，flutter analyze 无问题。

---

# 6. Phase 3 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（Fragmenter / Assembler 为纯 Dart，单测覆盖 §8.5/§8.7）

## 6.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/protocol/fragment.dart | §8.2/8.3/8.4 | FragmentHeader (MSG_ID/INDEX/TOTAL/LENGTH 各 2B 大端)；Fragmenter (Message → Frame[]，SEQ 连续分配)；FragmentAssembler (按 MSG_ID 分组、按 INDEX 存储、活动超时) |

## 6.2 设计决策（固件侧需对齐）

- Fragment 头编码在 Frame Payload 前 8 字节；INDEX 用 2 字节（MTU=23 时 50KB 消息需 1.6 万+ 分片，1 字节不够）
- 单 Fragment DATA 上限：`mtu - 3(ATT头) - 7(Frame头) - 8(Fragment头) - 2(CRC)`；mtu=247 时 227 字节
- 空消息产生 1 个 TOTAL=1/LENGTH=0 的 Fragment
- 乱序免疫：按 INDEX 存储，收齐后按序拼接；多消息交错：按 MSG_ID 分组
- 活动超时：每收一片重置计时，超时丢弃整个消息（§8.6）；NACK 重传 Phase 4 实现
- 异常处理策略：重复 Fragment → 忽略；TOTAL 不一致 / INDEX 越界 / LENGTH 不符 / Payload 短于头 → 丢弃整个消息

## 6.3 测试（§8.5/§8.7 全覆盖）

| 用例 | 结果 |
|---|---|
| 大小矩阵 100/500/1K/5K/10K/50K 字节往返 | ✅ |
| 随机乱序 / 随机重复 | ✅ |
| 缺 Fragment 活动超时丢弃 + 同 MSG_ID 可重新组装 | ✅ |
| 错误 TOTAL / 错误 LENGTH / INDEX 越界 / Payload 不足 | ✅ |
| 多消息交错 / 单 Fragment / 空消息 / SEQ 连续 / MTU 过小 | ✅ |

全套单测 54/54 通过，flutter analyze 无问题。

---

# 7. Phase 4 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（可靠通道为纯 Dart；测试用脚本化 FakeBleDevice 复用本项目的解码/组装逻辑 dogfooding）

## 7.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/protocol/frame_stream_decoder.dart | §8.4 补全 | 字节流 → 帧：半包缓冲 / 粘包循环提取 / 坏帧按声明长度跳过继续扫描 |
| lib/protocol/reliable_channel.dart | §9.1/9.2/9.3/9.5 | 发送：FIFO 队列 (Window=1) → 分片 → 逐帧写入 → 等 ACK；超时重发同字节 (同 SEQ 去重)；NACK 立即失败；接收：解码 → ACK/NACK 路由 + 数据帧组装 |

## 7.2 设计决策（固件侧需对齐）

- ACK/NACK 帧 Payload = MSG_ID (2B 大端)，MVP 无附加字段；NACK → 立即失败不重试
- 重发复用完全相同的帧字节 (同 SEQ)，设备侧据此去重 (§7.4)
- 总发送次数 = maxRetry + 1 (§9.2)；默认 maxRetry=3 / ackTimeout=2s / assembleTimeout=5s
- Window=1 (§9.5)：前一消息未 ACK/未失败前，后续消息不写入 BLE
- 迟到/未知 ACK 忽略；队列串行 (Replaceable/Cancelable 分类留待 §9.4 后续)
- 入站数据帧按 TYPE 路由：0x10/0x11 → ACK 处理；0x01-0x05 → 组装

## 7.3 测试

| 用例 | 结果 |
|---|---|
| 正常 ACK / 分片写入 / Window=1 串行 / 重发字节一致 | ✅ |
| ACK 丢失 → 超时重发成功 / 超 maxRetry 失败且队列继续 | ✅ |
| NACK 立即失败 / 未知迟到 ACK 忽略 / 断开时 send 失败 | ✅ |
| 设备→App 分片消息经字节流重组 (双向) | ✅ |
| 解码器：半包全切分点 / 粘包 / 坏帧跳过续扫 / 超大 LENGTH 等待 | ✅ |

全套单测 71/71 通过 (连续两轮)，flutter analyze 无问题。

---

# 8. Phase 5 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（协议模型与编解码为纯 Dart）

## 8.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/protocol/protocol_messages.dart | §10.2-10.5 | sealed ProtocolMessage：DeviceCommand / DeviceResponse / DeviceEvent / DeviceState / DevicePatch + DeviceError + ProtocolErrorCodes (3001 起步) |
| lib/protocol/codec.dart | §10.6 | MessageCodec 抽象 (encode/decode(frameType, bytes)) |
| lib/protocol/json_codec.dart | §10.6 | JsonCodec：字段名与 doc 示例逐字对齐 |
| lib/protocol/ble_frame.dart | §10.1 | FrameType 注册表补全：0x20-0x23 (HELLO/PING 系列)、0x30/0x31 (RESOURCE 系列) |

## 8.2 设计决策（固件侧需对齐）

- 消息类型由 Frame TYPE 字节区分，JSON 体内不重复类型字段（PATCH 的 "type":"patch" 按 §16.3 示例保留）
- decode 签名 `decode(int frameType, List<int> data)` —— 对 §10.6 草图的修正：类型在帧头
- 错误响应：status='error' + error{code,message}；错误码 3001 无效参数 / 3002 未知命令 / 3003 忙 / 3004 不支持
- STATE/PATCH 仅最小结构（version + state / version + ops），Gap 检测等语义 Phase 11 完善
- 缺字段/类型不符 → ProtocolException（严格校验，尽早暴露固件问题）

## 8.3 测试（§10.2-10.5 示例逐字对齐）

| 用例 | 结果 |
|---|---|
| Command/Response/Event 与 doc 示例 JSON 逐字一致 | ✅ |
| 各类型 round-trip + Unicode 参数 | ✅ |
| 缺字段 / 类型错误 / 非法 JSON / 非业务帧类型 → ProtocolException | ✅ |
| FrameType 新增 6 类通过 validate | ✅ |

全套单测 88/88 通过，flutter analyze 无问题。

---

# 9. Phase 6 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（Mock 传输 (FakeBleDevice) 全链路测试，§11.4）

## 9.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/device/device_client.dart | §11.1 | DeviceClient：connect/disconnect/command/events/patches/states/getState；request_id 与响应配对；业务错误正常返回、传输失败抛异常 |
| lib/protocol/fragment.dart | 升级 | Assembler 追踪帧类型：onComplete 携带 frameType；同消息分片 TYPE 不一致 → 丢弃 |
| lib/protocol/reliable_channel.dart | 升级 | messages 流改发 IncomingMessage(msgId/frameType/data) |

## 9.2 分层验证（§11.2/§11.3）

- DeviceClient 零 import BLE Plugin：只依赖 BleTransport 抽象 ✓
- 不接触 HTML/WebView/DOM，只处理 Command/Response/Event/State/Patch ✓
- 依赖链：DeviceClient → ReliableChannel → BleTransport → Plugin ✓

## 9.3 语义约定

- command()：业务错误 (status='error') 作为正常返回值；ACK 超时/NACK/断开/响应超时抛异常
- getState() 返回最近缓存状态；主动拉取 STATE 在 Phase 11 §16.6
- 未知 request_id 的响应忽略；设备不应主动发命令 (忽略)
- 协议解码失败的入站消息丢弃 (兜底)

## 9.4 测试（§11.4 全部脱离真实 BLE）

| 用例 | 结果 |
|---|---|
| command 响应配对 / request_id 自增 / 业务错误正常返回 | ✅ |
| 响应超时 / 传输 ACK 超时异常传播 / 未知 request_id 忽略 | ✅ |
| events / patches / getState 缓存 / 未收状态抛错 | ✅ |
| 未连接 command 抛错 / disconnect 失败所有进行中命令 | ✅ |
| 全套 101/101 通过 (连续两轮) | ✅ |

---

# 10. Phase 7 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（ProviderContainer + Fake 传输测试）

## 10.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/device/connection_phase.dart | §12.6 | ConnectionPhase 枚举 (disconnected → ... → connected / error) |
| lib/device/device_session.dart | §12.5 | 不可变会话快照：phase/deviceId/client/deviceState/error |
| lib/providers/device_session_provider.dart | §12.3/12.4 | DeviceSessionController (单会话形态) + deviceClientProvider/connectionPhaseProvider/deviceStateProvider |
| lib/providers/ble_provider.dart | §12.3 | bleTransportProvider：懒构造 + 平台守卫 + 抽象类型 (测试可 override) |
| lib/ble/ble_transport.dart | §6.1 扩展 | 抽象接口新增 connectionStates (断线感知是 Transport 职责, §20) |

## 10.2 重构

- 旧演示栈改名让位：DemoDeviceChannel / MockDemoDeviceChannel / BleDemoDeviceChannel
  + demoDeviceSessionControllerProvider → lib/providers/demo_device_session_provider.dart
  (Phase 8 由新栈替代后整体移除)

## 10.3 状态生命周期 (§12.6)

当前可观测转移：disconnected → connecting → connected；connected → disconnecting → disconnected；
设备侧主动断线 → disconnected；任何异常 → error。
discovering/negotiating 在 transport 内部尚不可观测；handshaking/loadingUi/syncingState
分别待 Phase 10/9/11 接入。多设备 DeviceManager 待多设备需求实现。

## 10.4 测试

| 用例 | 结果 |
|---|---|
| 初始态 / connect 成功中间态 (门控观察) / connect 失败 → error | ✅ |
| 设备状态推送 / disconnect 转移 / 设备主动断线 / 重复 connect 释放旧会话 | ✅ |
| 命令经会话 client 全链路收发 | ✅ |
| 全套 109/109 通过；Chrome 回归 6/6 UI + 零错误 | ✅ |

**注：** Riverpod 3 微任务批处理会合并瞬间状态变化，测试中间态需用门控 (connectGate)。

---

# 11. 下一步：Phase 8 UI Adapter

```text
目标 (WORK_V2 §13)：
  Shelf 本地 HTTP 服务器 (127.0.0.1 + 随机端口 + session token §13.5)
  GET /api/device、GET /api/state、POST /api/command、GET /api/resource/<path>、WS /ws (§13.2)
  HTTP → UI Adapter → DeviceClient (§13.3)
  旧 UiServer (DemoDeviceChannel) 由新 DeviceClient 版本替代
```

可立即开始。

---

# 12. 执行规则备忘（WORK_V2 §48/§49）

- 每个 Phase：代码 + 单测 + 真机测试 + 异常测试 + 日志 + 文档（本文件）
- 建议：Phase 完成后打 tag（如 v0.1-ble），开 feature/ble 分支
- 本文件更新与 git 操作需用户确认
