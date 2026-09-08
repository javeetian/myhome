import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/webview_env.dart';
import 'studio_app.dart';

/// Device Studio 桌面入口 (WORK_V3 §28)。
///
/// 运行：
/// ```bash
/// flutter run -d windows -t lib/studio/studio_main.dart
/// ```
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeWebViewEnvironment(); // Windows: WebView2 环境
  runApp(const ProviderScope(child: StudioApp()));
}
