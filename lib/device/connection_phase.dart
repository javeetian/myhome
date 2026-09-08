/// 会话连接状态生命周期 (WORK_V2 §12.6)。
///
/// ```text
/// disconnected → connecting → ... → connected
/// connected → disconnecting → disconnected
/// 任何状态 → error
/// ```
///
/// discovering / negotiating 目前发生在 ReactiveBleTransport.connect 内部，
/// 尚不可观测；handshaking (HELLO) 归 Phase 10，loadingUi 已接入 (Phase 9)，
/// syncingState 归 Phase 11 —— 届时在对应阶段接入。
enum ConnectionPhase {
  disconnected,
  scanning,
  connecting,
  discovering,
  negotiating,
  handshaking,
  loadingUi,
  syncingState,
  connected,
  disconnecting,
  error,
}
