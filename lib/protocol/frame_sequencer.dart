/// Transport 层 SEQ 生成器 (WORK_V2 §7.4)。
///
/// SEQ 只服务于 Transport (ACK / 重复检测 / 重传 / 排序)，
/// 不能作为业务 Request ID。2 字节大端，溢出回绕：65535 → 0 (§7.5)。
class FrameSequencer {
  int _next = 0;

  /// 下一个 SEQ (0..65535)。
  int next() {
    final current = _next;
    _next = (_next + 1) & 0xFFFF;
    return current;
  }
}
