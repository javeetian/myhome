/// 通信统计 (WORK_V2 §28 性能指标 / §33 Developer Mode)。
///
/// 指标：
///   TX/RX 字节数 (Transport 层统计)
///   重试次数 (ACK 超时重发)
///   命令往返延迟样本 → P50 / P95 / P99 (§28.3)
///   连接建立时间
class DeviceStats {
  /// 已发送字节数 (Frame 级)。
  int txBytes = 0;

  /// 已接收字节数 (Frame 级)。
  int rxBytes = 0;

  /// ACK 超时重发次数。
  int retries = 0;

  /// 命令往返延迟样本 (毫秒)。
  final List<int> _commandLatenciesMs = <int>[];

  /// 最近一次连接建立时间。
  DateTime? connectedAt;

  void markConnected() => connectedAt = DateTime.now();

  void addTx(int bytes) => txBytes += bytes;

  void addRx(int bytes) => rxBytes += bytes;

  void addRetry() => retries++;

  void recordCommandLatency(Duration latency) =>
      _commandLatenciesMs.add(latency.inMilliseconds);

  /// 命令延迟 P50 (§28.3)。
  int? get commandLatencyP50 => _percentile(0.50);

  /// 命令延迟 P95。
  int? get commandLatencyP95 => _percentile(0.95);

  /// 命令延迟 P99。
  int? get commandLatencyP99 => _percentile(0.99);

  /// 命令样本数。
  int get commandCount => _commandLatenciesMs.length;

  int? _percentile(double p) {
    if (_commandLatenciesMs.isEmpty) {
      return null;
    }
    final sorted = List<int>.of(_commandLatenciesMs)..sort();
    final index = ((sorted.length - 1) * p).round();
    return sorted[index];
  }
}
