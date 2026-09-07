import 'ble_frame.dart';

/// 字节流 → 帧 解码器 (WORK_V2 §8.4 "Frame Decoder" 环节)。
///
/// 处理 BLE Notify 字节流的两类问题：
///   半包 (一帧拆到多个 chunk)  → 缓冲等待
///   粘包 (一个 chunk 含多帧)   → 循环提取
///
/// CRC / 字段校验失败的帧按声明长度跳过，继续扫描后续字节。
/// 局限：无同步标记，若 LENGTH 字段本身损坏导致误跳，流对齐可能丢失
/// (帧同步机制留待 Phase 12 完善)。
class FrameStreamDecoder {
  final List<int> _buffer = <int>[];

  /// 每解出一帧回调。
  void Function(BleFrame frame)? onFrame;

  /// 坏帧回调 (CRC / 校验失败，该帧已按声明长度丢弃)。
  void Function(List<int> bytes, String reason)? onError;

  /// 当前缓冲的字节数 (诊断用)。
  int get buffered => _buffer.length;

  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _buffer.addAll(chunk);
    _drain();
  }

  void _drain() {
    while (true) {
      if (_buffer.length < BleFrame.headerSize) {
        return;
      }
      final length = (_buffer[5] << 8) | _buffer[6];
      final frameSize = BleFrame.headerSize + length + BleFrame.crcSize;
      if (_buffer.length < frameSize) {
        return; // 半包：等待后续字节
      }
      final frameBytes = _buffer.sublist(0, frameSize);
      _buffer.removeRange(0, frameSize);
      try {
        onFrame?.call(BleFrame.decode(frameBytes));
      } on FrameException catch (e) {
        onError?.call(frameBytes, e.message);
      }
    }
  }

  /// 清空缓冲 (重连/异常恢复时调用)。
  void reset() => _buffer.clear();
}
