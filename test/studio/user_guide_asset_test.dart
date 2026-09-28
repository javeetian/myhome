import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhome/tools/release_samples.dart';

void main() {
  testWidgets('使用文档随应用打包 (帮助菜单直接可读)', (WidgetTester tester) async {
    // pubspec 的 assets 段声明的路径必须与 Studio 帮助菜单里用的一致
    final content = await rootBundle.loadString('docs/使用文档.md');

    expect(content, contains('# Device Studio 使用文档'));
    expect(content, contains('.uipkgignore'));
    expect(content, contains('deviceApi'));

    // §7 移植第一步：源码不开放仓库，随安装包发到 samples\
    // (目录名必须与打包工具一致，见 lib/tools/release_samples.dart)
    expect(ReleaseSamples.dirName, 'samples');
    expect(content, contains(r'<安装目录>\samples\device_sdk'));
    expect(content, contains(r'samples\light1'));
  });
}
