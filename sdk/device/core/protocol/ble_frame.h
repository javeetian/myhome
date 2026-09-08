/* BLE Frame：与 Dart lib/protocol/ble_frame.dart 字节级一致。
 * 布局：VER(1) TYPE(1) FLAGS(1) SEQ(2BE) LENGTH(2BE) PAYLOAD(N) CRC16(2BE)
 * CRC 覆盖 Header + Payload。 */
#ifndef BLE_FRAME_H
#define BLE_FRAME_H

#include <stddef.h>
#include <stdint.h>

#define BLE_FRAME_VERSION     1
#define BLE_FRAME_HEADER_SIZE 7
#define BLE_FRAME_CRC_SIZE    2
#define BLE_FRAME_MAX_PAYLOAD 0xFFFF

/* 帧类型 (与 Dart FrameType 注册表一致, WORK_V2 §10.1 + §16.5 扩展) */
#define FRAME_COMMAND        0x01
#define FRAME_RESPONSE       0x02
#define FRAME_EVENT          0x03
#define FRAME_STATE          0x04
#define FRAME_PATCH          0x05
#define FRAME_ACK            0x10
#define FRAME_NACK           0x11
#define FRAME_HELLO          0x20
#define FRAME_HELLO_ACK      0x21
#define FRAME_PING           0x22
#define FRAME_PONG           0x23
#define FRAME_RESOURCE_REQ   0x30
#define FRAME_RESOURCE_RESP  0x31
#define FRAME_STATE_REQUEST  0x32

typedef struct {
    uint8_t  version;
    uint8_t  type;
    uint8_t  flags;
    uint16_t sequence;
    uint16_t length;
    const uint8_t* payload;
} ble_frame_t;

/* 编码：out 至少需要 length + 9 字节；返回总长，容量不足返回 -1 */
int ble_frame_encode(const ble_frame_t* frame, uint8_t* out, size_t out_cap);

/* 解码：恰好一帧 (严格定长)。成功返回总长；CRC 错误返回 -2；其余失败 -1 */
int ble_frame_decode(const uint8_t* data, size_t len, ble_frame_t* out);

#endif /* BLE_FRAME_H */
