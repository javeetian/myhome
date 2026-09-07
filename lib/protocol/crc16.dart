/// CRC-16/CCITT-FALSE 实现 (WORK_V2 §7.3)。
///
/// 参数 (固件侧需对齐)：
///   poly   0x1021
///   init   0xFFFF
///   refin  false / refout false
///   xorout 0x0000
///   校验值: "123456789" → 0x29B1
///
/// 覆盖范围：Frame Header + Payload (不含 CRC 字段本身)。
///
/// TODO(性能): 当前为逐位算法；大包吞吐成为瓶颈时换 256 表查表实现
/// (WORK_V2 §45 禁止过早优化)。
int crc16Ccitt(List<int> data, [int crc = 0xFFFF]) {
  for (final byte in data) {
    crc ^= (byte & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      final msb = crc & 0x8000;
      crc = (crc << 1) & 0xFFFF;
      if (msb != 0) {
        crc ^= 0x1021;
      }
    }
  }
  return crc;
}
