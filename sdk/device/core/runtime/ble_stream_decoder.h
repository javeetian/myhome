/**
 * BLE 字节流 → 帧 解码器 (WORK_V2 §8.4 "Frame Decoder")。
 *
 * 处理 BLE 写入/Notify 字节流的两类问题：
 *   半包 (一帧拆到多次写入) → 缓冲等待
 *   粘包 (一次写入含多帧)   → 循环提取
 *
 * CRC / 字段校验失败的帧按声明长度跳过，继续扫描后续字节。
 * 局限 (与 Dart 实现一致)：无同步标记，若 LENGTH 字段本身损坏导致误跳，
 * 流对齐可能丢失 —— 靠上层超时重置恢复。
 */
#ifndef BLE_STREAM_DECODER_H
#define BLE_STREAM_DECODER_H

#include <stdint.h>

#include "../protocol/ble_frame.h"

/** 接收缓冲上限 (单帧最大字节数)。超出的帧按错误丢弃并重新对齐。 */
#ifndef BLE_STREAM_RX_CAPACITY
#define BLE_STREAM_RX_CAPACITY \
    (BLE_FRAME_HEADER_SIZE + 512 + BLE_FRAME_CRC_SIZE)
#endif

typedef struct ble_stream_decoder {
    uint8_t buf[BLE_STREAM_RX_CAPACITY];
    uint16_t len;

    /** 解出一帧回调。frame->payload 指向 buf 内部，回调返回后失效。 */
    void (*on_frame)(const ble_frame_t* frame, void* ctx);
    /** 坏帧回调 (CRC/校验失败，该帧已按声明长度丢弃)。 */
    void (*on_error)(const char* reason, void* ctx);
    void* ctx;
} ble_stream_decoder_t;

/** 初始化 (绑定回调)。 */
void ble_stream_decoder_init(ble_stream_decoder_t* d,
                             void (*on_frame)(const ble_frame_t*, void*),
                             void (*on_error)(const char*, void*),
                             void* ctx);

/** 喂入一段字节 (BLE 写入/Notify 回调里调用)。 */
void ble_stream_decoder_add(ble_stream_decoder_t* d, const uint8_t* chunk,
                            uint16_t chunk_len);

/** 清空缓冲 (重连/异常恢复时调用)。 */
void ble_stream_decoder_reset(ble_stream_decoder_t* d);

/** 当前缓冲字节数 (诊断用)。 */
uint16_t ble_stream_decoder_buffered(const ble_stream_decoder_t* d);

#endif /* BLE_STREAM_DECODER_H */
