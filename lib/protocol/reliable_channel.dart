import 'dart:async';

import '../ble/ble_transport.dart';
import 'ble_frame.dart';
import 'fragment.dart';
import 'frame_stream_decoder.dart';

/// 组装完成的入站消息 (含帧类型，供上层 Codec 按类型解码 §10.1)。
class IncomingMessage {
  const IncomingMessage({
    required this.msgId,
    required this.frameType,
    required this.data,
  });

  final int msgId;
  final int frameType;
  final List<int> data;
}

/// 可靠发送通道 (WORK_V2 §9)：ACK / Retry / CommandQueue。
///
/// 发送方向 (§9.1/9.2/9.3/9.5)：
/// ```text
/// send(message) → CommandQueue (FIFO, Window=1)
///   → Fragmenter → 逐帧 BLE Write
///   → 等 ACK (ackTimeout) → 超时重发 (maxRetry) → 仍失败则报错
///   → 收 NACK → 立即失败
/// ```
/// 重发复用完全相同的帧字节 (同 SEQ)，设备侧可据此去重 (§7.4)。
///
/// 接收方向 (§8.4)：
/// ```text
/// BLE Notify 字节流 → FrameStreamDecoder → ACK/NACK 路由
///                                    └→ 数据帧 → FragmentAssembler → messages
/// ```
///
/// ACK/NACK 帧 Payload：MSG_ID (2B 大端)。MVP 无附加字段。
class ReliableChannel {
  ReliableChannel({
    required this.transport,
    required this.fragmenter,
    this.maxRetry = 3,
    this.ackTimeout = const Duration(seconds: 2),
    this.assembleTimeout = const Duration(seconds: 5),
  }) : _assembler = FragmentAssembler(timeout: assembleTimeout);

  final BleTransport transport;
  final Fragmenter fragmenter;

  /// 最大重发次数 (§9.2)：总发送次数 = maxRetry + 1。
  final int maxRetry;

  /// 等待 ACK 的超时。
  final Duration ackTimeout;

  /// 入站消息组装超时 (§8.6)。
  final Duration assembleTimeout;

  final FragmentAssembler _assembler;
  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final StreamController<IncomingMessage> _messages =
      StreamController<IncomingMessage>.broadcast();
  final List<_PendingSend> _queue = <_PendingSend>[];

  _PendingSend? _inflight;
  StreamSubscription<List<int>>? _sub;
  bool _started = false;
  int _nextMsgId = 0;

  /// 组装完成的入站消息流。
  Stream<IncomingMessage> get messages => _messages.stream;

  /// 发送失败回调 (msgId, 错误)。
  void Function(int msgId, Object error)? onSendError;

  /// 入站消息丢弃回调 (Phase 3 组装异常转发)。
  void Function(int? msgId, String reason)? onIncomingDiscard;

  /// 订阅 BLE 通知并开始处理入站数据。重复调用无副作用。
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _assembler.onComplete = (msgId, frameType, message) {
      if (!_messages.isClosed) {
        _messages.add(
          IncomingMessage(msgId: msgId, frameType: frameType, data: message),
        );
      }
    };
    _assembler.onDiscard = (msgId, reason) {
      onIncomingDiscard?.call(msgId, reason);
    };
    _decoder.onFrame = _handleFrame;
    _sub = transport.notifications.listen(_decoder.add);
  }

  /// 入队发送一条消息，返回分配的 MSG_ID。
  ///
  /// [frameType] 为数据帧 TYPE (§10.1)。不同类型消息 (命令 / 握手 / 资源)
  /// 共享同一 SEQ 序列 —— SEQ 仅属 Transport 层 (§7.4)。
  ///
  /// 消息按 FIFO 串行发送 (Window=1)：前一条未收到 ACK / 未失败前，
  /// 后续消息不会写入 BLE (§9.5)。
  Future<int> send(
    List<int> message, {
    int? msgId,
    int frameType = FrameType.command,
  }) async {
    final id = msgId ?? (_nextMsgId++ & 0xFFFF);
    final typedFragmenter = Fragmenter(
      mtu: fragmenter.mtu,
      frameType: frameType,
      sequencer: fragmenter.sequencer,
    );
    final pending = _PendingSend(id, typedFragmenter.fragment(id, message));
    _queue.add(pending);
    _pump();
    return pending.completer.future;
  }

  void _pump() {
    if (_inflight != null || _queue.isEmpty) {
      return;
    }
    _inflight = _queue.removeAt(0);
    _transmit(_inflight!);
  }

  Future<void> _transmit(_PendingSend pending) async {
    pending.transmissions++;
    try {
      for (final frame in pending.frames) {
        await transport.write(frame.encode());
      }
      pending.timer = Timer(ackTimeout, () => _onAckTimeout(pending));
    } catch (e) {
      _fail(pending, e);
    }
  }

  void _onAckTimeout(_PendingSend pending) {
    if (!identical(_inflight, pending)) {
      return; // 已被 ACK/NACK/失败处理
    }
    if (pending.transmissions <= maxRetry) {
      _transmit(pending); // 重发 (§9.2)
    } else {
      _fail(pending, TimeoutException('ACK 超时 (msgId=${pending.msgId})'));
    }
  }

  void _handleFrame(BleFrame frame) {
    switch (frame.type) {
      case FrameType.ack:
        _handleAck(frame.payload, nack: false);
      case FrameType.nack:
        _handleAck(frame.payload, nack: true);
      case FrameType.command ||
            FrameType.response ||
            FrameType.event ||
            FrameType.state ||
            FrameType.patch ||
            FrameType.hello ||
            FrameType.helloAck ||
            FrameType.ping ||
            FrameType.pong ||
            FrameType.resourceRequest ||
            FrameType.resourceResponse:
        _assembler.add(frame);
    }
  }

  void _handleAck(List<int> payload, {required bool nack}) {
    if (payload.length < 2) {
      return;
    }
    final msgId = (payload[0] << 8) | payload[1];
    final pending = _inflight;
    if (pending == null || pending.msgId != msgId) {
      return; // 未知 / 迟到 ACK：忽略
    }
    if (nack) {
      _fail(pending, StateError('收到 NACK (msgId=$msgId)'));
    } else {
      _complete(pending);
    }
  }

  void _complete(_PendingSend pending) {
    pending.timer?.cancel();
    pending.timer = null;
    _inflight = null;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(pending.msgId);
    }
    _pump();
  }

  void _fail(_PendingSend pending, Object error) {
    pending.timer?.cancel();
    pending.timer = null;
    _inflight = null;
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(error);
    }
    onSendError?.call(pending.msgId, error);
    _pump();
  }

  /// 释放资源：取消订阅与计时器，未完成发送以错误结束。
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _inflight?.timer?.cancel();
    for (final pending in _queue) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('channel disposed'));
      }
    }
    _queue.clear();
    _inflight = null;
    _assembler.dispose();
    await _messages.close();
  }
}

/// 队列中的一条待发送消息。
class _PendingSend {
  _PendingSend(this.msgId, this.frames);

  final int msgId;
  final List<BleFrame> frames;
  final Completer<int> completer = Completer<int>();

  /// 已发送次数 (含重发)。
  int transmissions = 0;

  Timer? timer;
}
