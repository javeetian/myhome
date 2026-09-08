import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/webview_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeWebViewEnvironment(); // Windows: WebView2 环境 (WORK_V3)
  runApp(const ProviderScope(child: MyApp()));
}
