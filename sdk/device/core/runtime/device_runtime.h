/**
 * 设备协议运行时 (WORK_V3 §43 sdk/device/core)：
 * BLE 字节流 → 帧 → 消息 → 业务命令 → 响应/状态/事件 → 分帧 → BLE。
 *
 * 职责划分：
 * ```text
 * 本运行时 (SDK 提供)          开发者 (device_app.c) 实现
 * ├── 帧流解码 (半包/粘包)      ├── hardware_adapter (真实驱动)
 * ├── 分片重组                  ├── device_api.h 声明的命令函数
 * ├── 传输层 ACK (§9.1)         └── get_state_json (当前状态上报)
 * ├── HELLO/PING/STATE_REQUEST 处理
 * └── COMMAND → device_handle_command → RESPONSE 帧
 * ```
 *
 * 依赖生成代码 (同一 include 路径下)：
 *   device_api.h    device_handle_command(cmd, params_json, out, cap)
 *   device_info.h   DEVICE_TYPE / DEVICE_MODEL / 协议版本 / 能力列表
 *
 * 用法 (胶水层, 见 README)：
 * ```c
 * static device_runtime_t g_rt;
 * void app_ble_init(void) {
 *     device_runtime_hooks_t hooks = {
 *         .send = jieli_ble_send,          // 内部调 custom_fff0_notify
 *         .get_state_json = my_state_json, // 返回 {"power":true,...}
 *         .now_ms = my_tick_ms,
 *     };
 *     device_runtime_init(&g_rt, &hooks, negotiated_mtu);
 * }
 * static void custom_fff0_write_handler(u8 *buffer, u16 buffer_size) {
 *     device_runtime_on_bytes(&g_rt, buffer, buffer_size);   // ← 唯一接入点
 * }
 * void my_state_changed(void) { device_runtime_notify_state_changed(&g_rt); }
 * ```
 */
#ifndef DEVICE_RUNTIME_H
#define DEVICE_RUNTIME_H

#include <stdint.h>

#include "ble_stream_decoder.h"
#include "fragment.h"

/** 运行时应答超时 (毫秒)：未收齐的分片消息超时丢弃 (§8.6)。 */
#ifndef DEVICE_RUNTIME_ASSEMBLE_TIMEOUT_MS
#define DEVICE_RUNTIME_ASSEMBLE_TIMEOUT_MS 5000
#endif

/** 状态/响应 JSON 缓冲上限。 */
#ifndef DEVICE_RUNTIME_JSON_MAX
#define DEVICE_RUNTIME_JSON_MAX 512
#endif

typedef struct device_runtime_hooks {
    /** 发送字节到手机 (内部封装 custom_fff0_notify 等平台 API)。必填。 */
    void (*send)(const uint8_t* data, uint16_t len, void* ctx);
    /**
     * 应用返回当前状态 JSON (不含外层 version)，如 `{"power":true}`。
     * 返回写入长度；<0 = 失败。必填 (STATE 上报用)。
     */
    int (*get_state_json)(char* out, int cap, void* ctx);
    /**
     * 可选：读取设备资源 (ui.pkg 等)，返回字节数；<0 = 不存在。
     * 传 NULL 时 RESOURCE_REQUEST 返回 5001 (Phase 10 接入 SPIFFS)。
     */
    int (*get_resource)(const char* path, uint8_t* out, int cap, void* ctx);
    /** 可选：单调毫秒时钟 (分片超时用)。NULL = 不做超时清理。 */
    uint32_t (*now_ms)(void);
    void* ctx;
} device_runtime_hooks_t;

typedef struct device_runtime {
    ble_stream_decoder_t decoder;
    frag_sender_t sender;
    frag_assembler_t assembler;
    device_runtime_hooks_t hooks;

    uint16_t next_msg_id;   /**< 出站消息 ID (分片层，与 request_id 无关) */
    uint32_t state_version; /**< 状态版本 (§16.2) */

    /* 诊断计数 */
    uint32_t rx_frames;
    uint32_t tx_frames;
    uint32_t bad_frames;
    uint32_t duplicate_frames;
} device_runtime_t;

/** 初始化。[mtu] 传实际协商结果 (不要假设 247, §6.4)。 */
void device_runtime_init(device_runtime_t* rt, const device_runtime_hooks_t* hooks,
                         uint16_t mtu);

/** BLE 写入/Notify 收到手机数据的入口 (胶水层唯一接入点)。 */
void device_runtime_on_bytes(device_runtime_t* rt, const uint8_t* data,
                             uint16_t len);

/** 周期调用 (主循环/定时器)：分片超时清理。 */
void device_runtime_tick(device_runtime_t* rt, uint32_t now_ms);

/** 设备状态变化后调用：版本 +1 并推送 STATE 给手机。 */
void device_runtime_notify_state_changed(device_runtime_t* rt);

/** 主动推送事件 (§10.4)：[data_json] 为事件数据对象，如 `{"value":25.5}`。 */
void device_runtime_send_event(device_runtime_t* rt, const char* name,
                               const char* data_json);

/** 断线/重连时调用：清空帧缓冲与组装状态 (§21 会话不可复用)。 */
void device_runtime_reset(device_runtime_t* rt);

/** 当前状态版本 (供 device_state_changed 使用)。 */
uint32_t device_runtime_state_version(const device_runtime_t* rt);

#endif /* DEVICE_RUNTIME_H */
