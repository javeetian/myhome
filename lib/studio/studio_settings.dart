import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 打包 ui.pkg 时压缩图片 (设置菜单 → 偏好设置)。
///
/// 开启后打包管线会对 PNG 做调色板量化 (见 `UiImageOptimizer`)：
/// 照片级渲染图通常省 50–70%，带画质守卫 (误差超阈值就不压)，透明图和已经
/// 量化过的图直接跳过。**只影响打包结果，不改源文件**；关掉即原样打包。
class CompressUiImages extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final compressUiImagesProvider =
    NotifierProvider<CompressUiImages, bool>(CompressUiImages.new);
