import 'package:flutter/material.dart';

import 'studio_home_page.dart';

/// Device Studio 桌面应用 (WORK_V3 §28)。
class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Device Studio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const StudioHomePage(),
    );
  }
}
