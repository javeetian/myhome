import 'dart:io';

import 'package:flutter/material.dart';

import 'webview_host_mobile.dart';
import 'webview_host_windows.dart';

/// 非 web 平台分派：Windows → webview_windows；其余 → webview_flutter。
Widget buildHost({required String url, VoidCallback? onPageLoaded}) {
  if (Platform.isWindows) {
    return WindowsWebViewHost(url: url, onPageLoaded: onPageLoaded);
  }
  return MobileWebViewHost(url: url, onPageLoaded: onPageLoaded);
}
