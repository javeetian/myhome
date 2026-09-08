/* CRC16/CCITT-FALSE：与 Dart lib/protocol/crc16.dart 字节级一致。 */
#ifndef CRC16_H
#define CRC16_H

#include <stddef.h>
#include <stdint.h>

/* poly 0x1021, init 0xFFFF, 无反射, 大端输出 */
uint16_t crc16_ccitt(const uint8_t* data, size_t len);

#endif /* CRC16_H */
