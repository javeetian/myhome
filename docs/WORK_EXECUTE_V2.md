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
Phase 8  UI Adapter            ✅ 完成 (2026-09-08)
Phase 9  WebView Runtime       ✅ 完成 (2026-09-08)
Phase 10 Manifest / UI Package ✅ 完成 (2026-09-08)
Phase 11 State / Patch / Event ⬜ 未开始 (下一目标)
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
15. 实现 Shelf             ✅ (Phase 8：UiServer + UiAdapter，随机端口 + token + Origin 校验)
16. WebView 加载本地 HTML  ✅ (Phase 9：entryUrl 链路 + Device API Runtime 注入；真机视觉验证待硬件)
17. HTTP → DeviceClient    ✅ (Phase 8 UiAdapter)
18. WebSocket → WebView    ✅ (Phase 8 pushStream 单向推送；Phase 9 JS 运行时自动接收)
19. State / Patch          ⏳ Phase 11 (消息模型已具备，Gap 检测等语义待实现)
20. Manifest               ✅ (Phase 10：模型 + HELLO 握手 + /api/device 暴露)
21. UI Package             ✅ (Phase 10：ui.pkg = tar.gz + 完整下载)
22. UI Cache               ✅ (Phase 10：deviceId+uiVersion 版本化缓存 + SHA256)
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

# 11. Phase 8 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（HTTP 层测试用 FakeBleDevice + 真实 TCP 回环）

## 11.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/ui_runtime/ui_adapter.dart | §13.3/§13.4 | HTTP/WS 语义 → DeviceClient：api/command、api/state、api/device、api/resource(501)、pushStream (state/event/patch → JSON) |
| lib/ui_runtime/ui_server.dart | §13.1/§13.2/§13.5 | 仅绑定 127.0.0.1 + 随机端口 + 随机 token；全部路由挂 `/s/<token>/` 前缀；Origin 校验；静态服务保留 (Phase 9 接 UI Package) |
| lib/providers/ui_runtime_provider.dart | §12.3 | UiServerController.start(DeviceClient, {staticRoot})；entryUrl (含 token) 暴露给 WebView |
| lib/device/demo_device.dart | §30 | 无硬件演示设备：复用本项目协议栈 dogfooding (解码/组装/编解码)，LED/亮度/温度 + 定时状态推送 |
| lib/device/device_client.dart | 小改 | 暴露 deviceId getter (/api/device 使用) |
| lib/providers/device_session_provider.dart | 小改 | connect() 支持注入 transport (演示/测试)，缺省仍走 bleTransportProvider |

## 11.2 移除（旧演示栈，§10.2 计划项）

- lib/device/demo_device_channel.dart / mock_demo_device_channel.dart / ble_demo_device_channel.dart
- lib/providers/demo_device_session_provider.dart
- lib/core/constants.dart（固定端口 8080 常量，§13.5 已要求随机端口）

## 11.3 设计决策（固件/UI 规范侧需对齐）

- **token 用路径前缀** `/s/<token>/`：设备页面全部相对路径即可自动携带 token，无需感知；WS 地址从 `location` 推导
- **Origin 校验**：带 Origin 头的请求必须来自本机 (127.0.0.1 / localhost / ::1)，否则 403
- **WS Phase 8 单向**（设备 → WebView）；WebView → 设备走 POST /api/command
- **错误语义**：适配层坏请求 → 400 + 3001；传输失败/超时 → 500 + 2002；Resource 未实现 → 501 + 5001；设备业务错误正常 200
- **shelf 行为**：`Request.url.path` 是相对路径 (无前导 /)，路由前统一归一化 —— 这是 shelf 的文档化行为，非 bug

## 11.4 测试（11/11 通过，全套 120/120）

| 用例 | 结果 |
|---|---|
| §13.5 随机端口 + 随机 token + entryUrl 格式 | ✅ |
| §13.2 api/device 信息 / api/command 往返 (echo 校验设备侧收到) / api/state (无状态 404) | ✅ |
| 设备业务错误 (status=error) 正常 200 / 适配层坏请求 400+3001 ×3 | ✅ |
| 无 token / 错 token → 404；非本机 Origin → 403 (本机放行) | ✅ |
| api/resource → 501+5001；静态 index.html / css + 目录穿越防护 | ✅ |
| §14.4 WS 推送 state / event / patch 顺序转发 | ✅ |

## 11.5 遗留

- Origin 白名单为"本机任意端口"，正式版可收紧到固定入口
- /api/resource 真实实现 Phase 10 §27
- 真实设备联调仍待硬件 (见 §2)；演示设备 (DemoDevice) 已覆盖无硬件全链路

---

# 12. Phase 9 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（注入/服务为纯 Dart + TCP 回环测试）；WebView 真机视觉验证待模拟器/真机

## 12.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/ui_runtime/js_bridge.dart | §14.3/§14.5 | Device API Runtime：window.deviceState + deviceApi (command/getState/onState/onEvent/onPatch)；Patch 自动应用 (replace/add/remove)；WS 自动连接；injectDeviceApi() 纯函数 |
| lib/ui_runtime/ui_server.dart | §14.2 | HTML 自动注入 `<script src="__device_api.js">`；提供 `/s/<token>/__device_api.js` 路由 |
| lib/ui_runtime/webview_host.dart | §23 | onPageLoaded 回调 (UI Ready 信号) |
| lib/providers/device_session_provider.dart | §12.6 | setPhase()：loadingUi → connected；error/disconnected/disconnecting 不可覆盖 |
| lib/ui/pages/scan_page.dart | §12.6 | UI Server 启动后进入 loadingUi |
| lib/ui/pages/device_page.dart | §20/§23 | 页面加载完成 → connected；设备断开/异常 → 提示并自动返回扫描页 |
| lib/device/demo_device.dart | §14.3 | 演示页改用官方 deviceApi (dogfooding，移除手写 fetch/WS 样板) |

## 12.2 设计决策（UI 开发规范侧需对齐）

- **Device API Runtime 由服务器注入**（`<head>` 后阻塞脚本）：设备页面零样板代码，
  不需要手写 fetch / WebSocket / token 逻辑，直接使用 `window.deviceApi`
- 注入点在 `<head>` 之后：保证页面脚本执行前 deviceApi 已就绪
- Patch 由运行时自动应用到 deviceState 并派发回调（JSON Patch 子集）
- UI Ready 信号：WebView onPageFinished → phase = connected (§23 生命周期)
- 设备断开/异常：控制页自动弹回扫描页并提示（§20 断线流程）

## 12.3 测试（9/9 通过，全套 129/129）

| 用例 | 结果 |
|---|---|
| injectDeviceApi：head 注入 / html 回退 / 前置兜底 | ✅ |
| 服务器：HTML 注入 / 非 HTML 不注入 / __device_api.js 提供 | ✅ |
| setPhase：loadingUi→connected / error 终态不可覆盖 / disconnected 不可覆盖 | ✅ |

## 12.4 未完成（待硬件/模拟器）

- WebView 真机视觉验证：页面渲染、deviceApi 调用、WS 推送的可视化确认
- Phase 10 接入后：entryUrl 加载真实 ui.pkg

---

# 14. Phase 10 执行记录 ✅

**日期：** 2026-09-08
**硬件依赖：** 无（协议 / 打包 / 缓存为纯 Dart + FakeBleDevice 全链路测试）

## 14.1 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/protocol/protocol_messages.dart | §39/§27 | DeviceHello / DeviceHelloAck / DeviceResourceRequest / DeviceResourceResponse |
| lib/protocol/json_codec.dart | §46 | 新消息编解码（资源二进制 base64 内嵌，MVP JSON 阶段） |
| lib/protocol/reliable_channel.dart | 修复 | 入站路由补全 0x20-0x23 / 0x30-0x31；send() 支持 frameType |
| lib/device/device_client.dart | §39/§27 | hello() / requestResource()（request_id 配对 + 超时 + 断线失败）；helloAck 缓存 |
| lib/device/device_manifest.dart | §15.1/§24 | DeviceManifest 模型 + 协议版本检查 |
| lib/ui_runtime/ui_package.dart | §15.2 | ui.pkg = tar.gz（固定 mtime，可复现构建） |
| lib/ui_runtime/ui_cache.dart | §15.4/§15.5 | 版本化缓存 + SHA256/size 校验 + 防目录穿越 |
| lib/ui_runtime/ui_runtime.dart | §15.3 | manifest → 缓存命中 → 下载 → 校验 → 解包 编排 |
| lib/ui_runtime/ui_server.dart | §27 | /api/resource 真实实现（本地命中 → 设备回退落盘） |
| lib/ui_runtime/ui_adapter.dart | §25/§26 | /api/device 返回 HELLO_ACK + manifest 信息 |
| lib/providers/device_session_provider.dart | §12.6 | handshaking 阶段接入（connect 内 HELLO 握手） |
| lib/device/demo_device.dart | §15 | 演示设备完整走官方流程（HELLO / RESOURCE / ui.pkg） |

## 14.2 设计决策（固件侧需对齐）

- HELLO / HELLO_ACK 带 request_id（应用层配对，与 Transport SEQ 分离 §14）
- 资源响应 MVP 用 base64 内嵌 JSON（§46 第一阶段）；正式版换二进制编码
- manifest.json 经 RESOURCE_REQUEST('manifest.json') 获取；ui.pkg 一次下载整包
- package{size, sha256} 可选；固件声明则校验（§15.5）
- ui.pkg 固定 mtime=0：同内容字节确定性，固件可离线计算 sha256
- 缓存目录 `ui/<deviceId>/<uiVersion>/`；命中直接加载（§15.3）

## 14.3 过程中修复的问题

1. **ReliableChannel 发送方向不带类型**：所有消息以 COMMAND(0x01) 帧发出，HELLO 无法被设备识别。
   修复：send() 增加 frameType 参数，与 Fragmenter 共享 SEQ 序列（SEQ 仅属 Transport 层 §7.4）
2. **ReliableChannel 入站路由缺类型**：0x20-0x23 / 0x30-0x31 帧被静默丢弃，HELLO_ACK 无法到达。
   修复：路由 case 补全（§7.2 决策更新）

## 14.4 测试（新增 35 例，全套 164/164）

| 用例 | 结果 |
|---|---|
| HELLO / RESOURCE 消息 round-trip + 缺字段异常 | ✅ 8 |
| DeviceManifest 解析 / 协议版本检查 | ✅ 7 |
| ui.pkg 多文件 / 字节确定性 / 空包 | ✅ 3 |
| UiCache 命中 / 校验失败不污染 / 防穿越 | ✅ 6 |
| UiRuntime 全流程 / 缓存命中不重复下载 / sha / 协议版本 | ✅ 6 |
| 会话 HELLO 握手 + 无响应失败 | ✅ 2 |
| /api/resource 三态 + /api/device manifest 信息 | ✅ 3 |

## 14.5 未完成（待硬件）

- 真机 ui.pkg 大文件传输实测（分片能力已具备）
- 设备固件侧 manifest / ui.pkg / HELLO 实现（§40）

---

# 15. 下一步：Phase 11 State / Patch / Event

```text
目标 (WORK_V2 §16)：
  STATE / PATCH / EVENT 完整语义 (§16.1-16.4)
  state_version Gap 检测 → 缺失触发全量 STATE_REQUEST (§16.5/§16.6)
  DeviceState (Riverpod) → WebSocket → WebView → JS Store (§16.4)
  主动拉取 STATE (getState 已有缓存版 → 全量同步版)
  syncingState 阶段接入 (§12.6)
```

可立即开始。

---

# 16. 执行规则备忘（WORK_V2 §48/§49）

- 每个 Phase：代码 + 单测 + 真机测试 + 异常测试 + 日志 + 文档（本文件）
- 建议：Phase 完成后打 tag（如 v0.1-ble），开 feature/ble 分支
- 本文件更新与 git 操作需用户确认
