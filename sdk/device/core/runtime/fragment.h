/**
 * 分片层 (WORK_V2 §8)：Application Message ↔ Fragment ↔ Frame。
 *
 * 分片头 (8 字节，大端，编码在 Frame Payload 前)：
 * ```text
 * ┌────────┬────────┬────────┬────────┬──────────┐
 * │ MSG_ID │ INDEX  │ TOTAL  │ LENGTH │   DATA   │
 * │ 2B     │ 2B     │ 2B     │ 2B     │ N bytes  │
 * └────────┴────────┴────────┴────────┴──────────┘
 * ```
 * 嵌入式实现：无动态内存 (固定槽位 + 固定缓冲)，容量由下方宏配置。
 */
#ifndef DEVICE_FRAGMENT_H
#define DEVICE_FRAGMENT_H

#include <stdint.h>

#include "../protocol/ble_frame.h"

#define FRAGMENT_HEADER_SIZE 8

/** 接收方向：单个消息最大字节数 (App→设备，通常是命令)。 */
#ifndef DEVICE_RX_MESSAGE_MAX
#define DEVICE_RX_MESSAGE_MAX 1024
#endif
/** 接收方向：并发组装中的消息数。 */
#ifndef DEVICE_RX_ASSEMBLY_SLOTS
#define DEVICE_RX_ASSEMBLY_SLOTS 2
#endif
/** 接收方向：单消息最大分片数。 */
#ifndef DEVICE_RX_MAX_FRAGMENTS
#define DEVICE_RX_MAX_FRAGMENTS 64
#endif
/** 完成记录容量 (重复帧去重，环形)。 */
#ifndef DEVICE_RX_COMPLETED_CAPACITY
#define DEVICE_RX_COMPLETED_CAPACITY 16
#endif
/** 发送方向单帧缓冲上限 (MTU 上限 + 帧头尾)。 */
#ifndef DEVICE_TX_FRAME_MAX
#define DEVICE_TX_FRAME_MAX 260
#endif

/* ---------------- 发送方向：分片器 ---------------- */

/** 每帧发送回调 (通常直接写 BLE Notify)。 */
typedef void (*frag_send_fn)(const uint8_t* bytes, uint16_t len, void* ctx);

typedef struct frag_sender {
    uint16_t mtu;   /**< 协商 MTU (ATT)，单帧字节数 ≤ mtu - 3 */
    uint16_t seq;   /**< 帧 SEQ (仅 Transport 用, §7.4) */
    uint8_t frame_buf[DEVICE_TX_FRAME_MAX];
} frag_sender_t;

/** 初始化分片器。[mtu] 传协商结果，不要假设 247 (§6.4)。 */
void frag_sender_init(frag_sender_t* s, uint16_t mtu);

/** 单个 Fragment 最大 DATA 长度 (MTU 过小时返回 0)。 */
uint16_t frag_max_data_size(const frag_sender_t* s);

/**
 * 把一条消息分片并逐帧发送。
 * 空消息也产生 1 个 TOTAL=1/LENGTH=0 的分片 (与 Dart 实现一致)。
 * 返回实际发送的分片数；0 = 失败 (MTU 过小)。
 */
uint16_t frag_send_message(frag_sender_t* s, uint16_t msg_id, uint8_t frame_type,
                           const uint8_t* data, uint16_t len,
                           frag_send_fn send, void* ctx);

/* ---------------- 接收方向：组装器 ---------------- */

typedef struct frag_assembly {
    uint8_t  in_use;
    uint8_t  frame_type;
    uint16_t msg_id;
    uint16_t total;
    uint16_t received;
    uint16_t len;
    uint32_t deadline_ms;
    uint32_t seen[DEVICE_RX_MAX_FRAGMENTS / 32 +
                  (DEVICE_RX_MAX_FRAGMENTS % 32 ? 1 : 0)]; /**< 已收分片位图 */
    uint8_t  data[DEVICE_RX_MESSAGE_MAX];
} frag_assembly_t;

typedef struct frag_assembler {
    frag_assembly_t slots[DEVICE_RX_ASSEMBLY_SLOTS];
    uint16_t completed[DEVICE_RX_COMPLETED_CAPACITY]; /**< 环形完成记录 */
    uint8_t  completed_count;
    uint8_t  completed_head;
    uint32_t timeout_ms;

    /** 消息组装完成 (data 指向组装缓冲，回调返回后失效)。 */
    void (*on_complete)(uint16_t msg_id, uint8_t frame_type, const uint8_t* data,
                        uint16_t len, void* ctx);
    /** 消息被丢弃 (msg_id 无效时传 0xFFFF)。 */
    void (*on_discard)(uint16_t msg_id, const char* reason, void* ctx);
    /** 重复帧 (发送端重发)：接收端应重发 ACK (§7.4 去重语义)。 */
    void (*on_duplicate)(uint16_t msg_id, void* ctx);
    void* ctx;
} frag_assembler_t;

void frag_assembler_init(frag_assembler_t* a, uint32_t timeout_ms,
                         void (*on_complete)(uint16_t, uint8_t, const uint8_t*,
                                             uint16_t, void*),
                         void (*on_discard)(uint16_t, const char*, void*),
                         void (*on_duplicate)(uint16_t, void*),
                         void* ctx);

/** 处理一个数据帧 (已通过 CRC 校验)。 */
void frag_assembler_add(frag_assembler_t* a, const ble_frame_t* frame);

/** 周期调用：清理超时未收齐的消息，超时返回 1。 */
int frag_assembler_tick(frag_assembler_t* a, uint32_t now_ms);

/** 会话重置 (重连后调用，避免新会话 MSG_ID 被误判为重复)。 */
void frag_assembler_reset(frag_assembler_t* a);

#endif /* DEVICE_FRAGMENT_H */
