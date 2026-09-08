/// 统一日志系统 (WORK_V2 §31/§32)。
///
/// 格式 (§31)：
/// ```text
/// [TIME] [LEVEL] [MODULE] [DEVICE] [SEQ] [REQUEST_ID] MESSAGE
/// 例：11:22:33.456 DEBUG BLE device=abc seq=100 write 32 bytes
/// ```
/// 等级 (§32)：trace < debug < info < warn < error。
/// 开发版本默认 debug，正式版本建议 info。
class AppLog {
  /// 全局实例 (跨层使用)。
  static final AppLog instance = AppLog();

  /// 当前日志等级：低于此等级的日志被过滤。
  LogLevel level;

  /// 输出通道 (测试可注入收集)。
  final void Function(String line) output;

  AppLog({this.level = LogLevel.debug, this.output = print});

  void trace(String module, String message, {String? deviceId, int? seq, int? requestId}) =>
      log(LogLevel.trace, module, message, deviceId: deviceId, seq: seq, requestId: requestId);

  void debug(String module, String message, {String? deviceId, int? seq, int? requestId}) =>
      log(LogLevel.debug, module, message, deviceId: deviceId, seq: seq, requestId: requestId);

  void info(String module, String message, {String? deviceId, int? seq, int? requestId}) =>
      log(LogLevel.info, module, message, deviceId: deviceId, seq: seq, requestId: requestId);

  void warn(String module, String message, {String? deviceId, int? seq, int? requestId}) =>
      log(LogLevel.warn, module, message, deviceId: deviceId, seq: seq, requestId: requestId);

  void error(String module, String message, {String? deviceId, int? seq, int? requestId}) =>
      log(LogLevel.error, module, message, deviceId: deviceId, seq: seq, requestId: requestId);

  /// 记录一条日志；低于当前等级时过滤。
  void log(
    LogLevel level,
    String module,
    String message, {
    String? deviceId,
    int? seq,
    int? requestId,
  }) {
    if (level.index < this.level.index) {
      return;
    }
    final now = DateTime.now();
    final time = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}'
        '.${now.millisecond.toString().padLeft(3, '0')}';
    final parts = <String>[
      time,
      level.name.toUpperCase(),
      module,
      if (deviceId != null) 'device=$deviceId',
      if (seq != null) 'seq=$seq',
      if (requestId != null) 'request_id=$requestId',
    ];
    output('${parts.join(' ')} $message');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// 日志等级 (§32)。
enum LogLevel { trace, debug, info, warn, error }
