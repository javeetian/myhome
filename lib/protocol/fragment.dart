import 'dart:async';
import 'dart:math';

import 'ble_frame.dart';
import 'frame_sequencer.dart';

/// 分片层异常。
class FragmentException implements Exception {
  const FragmentException(this.message);

  final String message;

  @override
  String toString() => 'FragmentException: $message';
}

/// Fragment 头 (WORK_V2 §8.2)，编码进 Frame Payload 前 8 字节 (大端)。
///
/// ```text
/// ┌────────┬────────┬────────┬────────┬──────────┐
/// │ MSG_ID │ INDEX  │ TOTAL  │ LENGTH │   DATA   │
/// │ 2B     │ 2B     │ 2B     │ 2B     │ N bytes  │
/// └────────┴────────┴────────┴────────┴──────────┘
/// ```
class FragmentHeader {
  FragmentHeader({
    required this.msgId,
    required this.index,
    required this.total,
    required this.length,
  });

  static const int size = 8;

  /// 消息标识 (与业务 Request ID 无关，由分片层分配)。
  final int msgId;

  /// 分片序号 (0..total-1)。
  final int index;

  /// 总分片数。
  final int total;

  /// 本分片 DATA 长度。
  final int length;

  List<int> encode() => <int>[
        (msgId >> 8) & 0xFF,
        msgId & 0xFF,
        (index >> 8) & 0xFF,
        index & 0xFF,
        (total >> 8) & 0xFF,
        total & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ];

  static FragmentHeader decode(List<int> payload) {
    if (payload.length < size) {
      throw FragmentException('Payload 不足 Fragment 头: ${payload.length} < $size');
    }
    return FragmentHeader(
      msgId: (payload[0] << 8) | payload[1],
      index: (payload[2] << 8) | payload[3],
      total: (payload[4] << 8) | payload[5],
      length: (payload[6] << 8) | payload[7],
    );
  }
}

/// 发送方向分片器 (WORK_V2 §8.3)：
///   Application Message → Fragment[] → Frame[] → BLE
///
/// 每个 Fragment 包成独立 Frame，SEQ 由 [FrameSequencer] 连续分配 (§7.4)。
class Fragmenter {
  Fragmenter({
    required this.mtu,
    this.frameType = FrameType.command,
    FrameSequencer? sequencer,
  }) : sequencer = sequencer ?? FrameSequencer();

  /// 协商 MTU (ATT 层)。
  final int mtu;

  /// 数据帧 TYPE (§10.1)。
  final int frameType;

  final FrameSequencer sequencer;

  /// 单个 Fragment 最大 DATA 长度：
  ///   Frame头(7) + Fragment头(8) + DATA + CRC(2) ≤ mtu - 3 (ATT 写入头)
  int get maxDataSize =>
      mtu - 3 - BleFrame.headerSize - FragmentHeader.size - BleFrame.crcSize;

  /// 拆分消息为帧序列。
  /// 空消息也产生 1 个 TOTAL=1 / LENGTH=0 的 Fragment。
  List<BleFrame> fragment(int msgId, List<int> message) {
    if (maxDataSize <= 0) {
      throw FragmentException('MTU 过小 ($mtu)：无空间承载数据');
    }
    if (msgId < 0 || msgId > 0xFFFF) {
      throw FragmentException('非法 MSG_ID: $msgId');
    }
    final total =
        message.isEmpty ? 1 : (message.length + maxDataSize - 1) ~/ maxDataSize;
    final frames = <BleFrame>[];
    for (var index = 0; index < total; index++) {
      final start = index * maxDataSize;
      final data = message.sublist(start, min(start + maxDataSize, message.length));
      frames.add(
        BleFrame(
          version: BleFrame.currentVersion,
          type: frameType,
          flags: 0,
          sequence: sequencer.next(),
          payload: <int>[
            ...FragmentHeader(
              msgId: msgId,
              index: index,
              total: total,
              length: data.length,
            ).encode(),
            ...data,
          ],
        ),
      );
    }
    return frames;
  }
}

/// 接收方向组装器 (WORK_V2 §8.4)：
///   BLE → Frame → Fragment → Assembler → 完整 Message
///
/// 支持多消息交错 (按 MSG_ID 分组)；乱序免疫 (按 INDEX 存储)。
/// 活动超时：每收到一个分片重置计时，超时丢弃整个消息 (§8.6)，
/// 后续 NACK 重传在 Phase 4 实现。
class FragmentAssembler {
  FragmentAssembler({
    this.timeout = const Duration(seconds: 5),
    this.onComplete,
    this.onDiscard,
  });

  final Duration timeout;

  /// 消息组装完成回调 (可变，可在构造后赋值)。
  /// 携带帧类型：同一条消息的 Fragment 必须 TYPE 一致，否则丢弃。
  void Function(int msgId, int frameType, List<int> message)? onComplete;

  /// 消息被丢弃回调 (msgId 可能为 null：Payload 短于 Fragment 头)。
  void Function(int? msgId, String reason)? onDiscard;

  final Map<int, _Assembly> _assemblies = <int, _Assembly>{};

  /// 处理一个数据帧。完成时回调 [onComplete]，异常时回调 [onDiscard]。
  void add(BleFrame frame) {
    FragmentHeader header;
    List<int> data;
    try {
      header = FragmentHeader.decode(frame.payload);
      data = frame.payload.sublist(FragmentHeader.size);
    } on FragmentException {
      _discard(null, '长度不足');
      return;
    }

    if (header.length != data.length) {
      _discard(header.msgId, '错误 LENGTH');
      return;
    }
    if (header.total <= 0) {
      _discard(header.msgId, '错误 TOTAL');
      return;
    }
    if (header.index < 0 || header.index >= header.total) {
      _discard(header.msgId, 'INDEX 越界');
      return;
    }

    final assembly = _assemblies[header.msgId];
    if (assembly == null) {
      _assemblies[header.msgId] = _Assembly(
        msgId: header.msgId,
        total: header.total,
        frameType: frame.type,
        timeout: timeout,
        onTimeout: _discard,
      );
    } else if (assembly.total != header.total) {
      _discard(header.msgId, '错误 TOTAL');
      return;
    } else if (assembly.frameType != frame.type) {
      _discard(header.msgId, 'TYPE 不一致');
      return;
    }

    final current = _assemblies[header.msgId]!;
    if (current.parts.containsKey(header.index)) {
      // 重复 Fragment：忽略 (§8.5)，重置活动计时
      current.resetTimer();
      return;
    }

    current.parts[header.index] = data;
    if (current.parts.length == current.total) {
      final parts = current.parts;
      final message = <int>[];
      for (var i = 0; i < current.total; i++) {
        message.addAll(parts[i]!);
      }
      _assemblies.remove(header.msgId);
      current.cancel();
      onComplete?.call(header.msgId, current.frameType, message);
      return;
    }
    current.resetTimer();
  }

  void _discard(int? msgId, String reason) {
    if (msgId != null) {
      final assembly = _assemblies.remove(msgId);
      assembly?.cancel();
    }
    onDiscard?.call(msgId, reason);
  }

  /// 释放全部资源 (取消所有计时器)。
  void dispose() {
    for (final assembly in _assemblies.values) {
      assembly.cancel();
    }
    _assemblies.clear();
  }
}

/// 单个消息的组装状态。
class _Assembly {
  _Assembly({
    required this.msgId,
    required this.total,
    required this.frameType,
    required Duration timeout,
    required void Function(int, String) onTimeout,
  })  : _timeout = timeout,
        _onTimeout = onTimeout {
    resetTimer();
  }

  final int msgId;
  final int total;

  /// 该消息的帧类型 (首片确定，后续分片必须一致)。
  final int frameType;

  final Duration _timeout;
  final void Function(int, String) _onTimeout;
  final Map<int, List<int>> parts = <int, List<int>>{};

  Timer? _timer;

  /// 活动计时：每收到一个分片重置 (§8.6 等待下一片超时 → 丢弃整个消息)。
  void resetTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, () => _onTimeout(msgId, '超时'));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
