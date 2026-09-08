#include "ble_frame.h"
#include "crc16.h"

#include <string.h>

int ble_frame_encode(const ble_frame_t* frame, uint8_t* out, size_t out_cap) {
    const size_t total =
        BLE_FRAME_HEADER_SIZE + frame->length + BLE_FRAME_CRC_SIZE;
    if (out_cap < total) {
        return -1;
    }
    out[0] = frame->version;
    out[1] = frame->type;
    out[2] = frame->flags;
    out[3] = (uint8_t)(frame->sequence >> 8);
    out[4] = (uint8_t)(frame->sequence & 0xFF);
    out[5] = (uint8_t)(frame->length >> 8);
    out[6] = (uint8_t)(frame->length & 0xFF);
    if (frame->length > 0) {
        memcpy(out + BLE_FRAME_HEADER_SIZE, frame->payload, frame->length);
    }
    const uint16_t crc =
        crc16_ccitt(out, BLE_FRAME_HEADER_SIZE + frame->length);
    out[BLE_FRAME_HEADER_SIZE + frame->length] = (uint8_t)(crc >> 8);
    out[BLE_FRAME_HEADER_SIZE + frame->length + 1] = (uint8_t)(crc & 0xFF);
    return (int)total;
}

int ble_frame_decode(const uint8_t* data, size_t len, ble_frame_t* out) {
    if (len < BLE_FRAME_HEADER_SIZE + BLE_FRAME_CRC_SIZE) {
        return -1; /* 不足头部 */
    }
    const uint16_t length = ((uint16_t)data[5] << 8) | data[6];
    if (len != BLE_FRAME_HEADER_SIZE + length + BLE_FRAME_CRC_SIZE) {
        return -1; /* 声明长度不符 (粘包/半包由流解码器处理) */
    }
    const uint16_t crc_expect = ((uint16_t)data[len - 2] << 8) | data[len - 1];
    const uint16_t crc_actual = crc16_ccitt(data, BLE_FRAME_HEADER_SIZE + length);
    if (crc_expect != crc_actual) {
        return -2; /* CRC 错误 */
    }
    out->version = data[0];
    out->type = data[1];
    out->flags = data[2];
    out->sequence = ((uint16_t)data[3] << 8) | data[4];
    out->length = length;
    out->payload = data + BLE_FRAME_HEADER_SIZE;
    return (int)len;
}
