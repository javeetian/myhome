#include "ble_stream_decoder.h"

#include <string.h>

void ble_stream_decoder_init(ble_stream_decoder_t* d,
                             void (*on_frame)(const ble_frame_t*, void*),
                             void (*on_error)(const char*, void*),
                             void* ctx)
{
    if (d == NULL) {
        return;
    }
    d->len = 0;
    d->on_frame = on_frame;
    d->on_error = on_error;
    d->ctx = ctx;
}

void ble_stream_decoder_reset(ble_stream_decoder_t* d)
{
    if (d != NULL) {
        d->len = 0;
    }
}

uint16_t ble_stream_decoder_buffered(const ble_stream_decoder_t* d)
{
    return d == NULL ? 0 : d->len;
}

void ble_stream_decoder_add(ble_stream_decoder_t* d, const uint8_t* chunk,
                            uint16_t chunk_len)
{
    if (d == NULL || chunk == NULL || chunk_len == 0) {
        return;
    }

    /* 缓冲剩余空间不足：丢弃既有数据重新对齐 (避免半帧永久占位)。 */
    if ((uint32_t)d->len + chunk_len > BLE_STREAM_RX_CAPACITY) {
        if (chunk_len >= BLE_STREAM_RX_CAPACITY) {
            d->len = 0;
            if (d->on_error != NULL) {
                d->on_error("overflow", d->ctx);
            }
            return;
        }
        d->len = 0;
    }
    memcpy(d->buf + d->len, chunk, chunk_len);
    d->len = (uint16_t)(d->len + chunk_len);

    /* 循环提取完整帧 (粘包处理)。 */
    for (;;) {
        if (d->len < BLE_FRAME_HEADER_SIZE) {
            return; /* 半包：等后续字节 */
        }
        const uint16_t payload_len =
            (uint16_t)(((uint16_t)d->buf[5] << 8) | d->buf[6]);
        const uint32_t frame_size =
            (uint32_t)BLE_FRAME_HEADER_SIZE + payload_len + BLE_FRAME_CRC_SIZE;
        if (frame_size > BLE_STREAM_RX_CAPACITY) {
            /* 声明长度超缓冲上限：无法恢复，清空等对齐。 */
            d->len = 0;
            if (d->on_error != NULL) {
                d->on_error("frame too large", d->ctx);
            }
            return;
        }
        if (d->len < frame_size) {
            return; /* 半包 */
        }

        ble_frame_t frame;
        const int rc = ble_frame_decode(d->buf, frame_size, &frame);
        if (rc < 0) {
            if (d->on_error != NULL) {
                d->on_error(rc == -2 ? "crc error" : "bad frame", d->ctx);
            }
        } else if (d->on_frame != NULL) {
            d->on_frame(&frame, d->ctx);
        }

        /* 消费该帧，继续扫描 (坏帧也按声明长度跳过)。 */
        const uint16_t consumed = (uint16_t)frame_size;
        if (consumed < d->len) {
            memmove(d->buf, d->buf + consumed, (size_t)(d->len - consumed));
        }
        d->len = (uint16_t)(d->len - consumed);
    }
}
