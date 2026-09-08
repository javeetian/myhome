import 'package:flutter/material.dart';

/// web 平台占位：WebView 不可用。
Widget buildHost({required String url, VoidCallback? onPageLoaded}) {
  return const Center(child: Text('当前平台不支持 WebView'));
}
