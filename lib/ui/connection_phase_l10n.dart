import '../device/connection_phase.dart';
import '../l10n/app_localizations.dart';

/// [ConnectionPhase] → 本地化文案 (开发者面板展示用)。
///
/// 放在 ui 层而非 device/ 核心层：核心层不依赖生成的 l10n 代码。
extension ConnectionPhaseL10n on ConnectionPhase {
  /// 当前状态的本地化名称。
  String label(AppLocalizations l10n) {
    switch (this) {
      case ConnectionPhase.disconnected:
        return l10n.phaseDisconnected;
      case ConnectionPhase.scanning:
        return l10n.phaseScanning;
      case ConnectionPhase.connecting:
        return l10n.phaseConnecting;
      case ConnectionPhase.discovering:
        return l10n.phaseDiscovering;
      case ConnectionPhase.negotiating:
        return l10n.phaseNegotiating;
      case ConnectionPhase.handshaking:
        return l10n.phaseHandshaking;
      case ConnectionPhase.loadingUi:
        return l10n.phaseLoadingUi;
      case ConnectionPhase.syncingState:
        return l10n.phaseSyncingState;
      case ConnectionPhase.connected:
        return l10n.phaseConnected;
      case ConnectionPhase.disconnecting:
        return l10n.phaseDisconnecting;
      case ConnectionPhase.reconnecting:
        return l10n.phaseReconnecting;
      case ConnectionPhase.error:
        return l10n.phaseError;
    }
  }
}
