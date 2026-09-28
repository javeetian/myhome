import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 打包期图片压缩（纯 Dart，无外部工具、无 Python —— 跟着 Studio 一起发布）。
///
/// UI 里的 PNG 多是照片级渲染图+渐变：无损压缩压不动（icon-192.png 37 KB → 35 KB），
/// 但它们是**调色板友好的**——量化成 256 色以内通常省 50–70%，图标尺寸下肉眼无差别。
///
/// 策略（实测于 light2 的 icon-192.png，37,542 B）：
/// - `octree` + **关闭抖动**：这个包的 Floyd-Steinberg 实现有问题（256 色下平均误差
///   0.69 → 8.05，还更大），关掉抖动反而画质最好、体积最小；
/// - 色数从 64 起试，**画质过关就早停**：64 色 12.3 KB / 误差 1.3，观感与
///   Pillow FASTOCTREE 版的 7.1 KB 一致；32 色 9.5 KB 但渐变出现可见色带，故不取；
/// - 带透明通道的图直接跳过（`quantize` 会丢 alpha，见 image 4.10.1
///   `filter/dither_image.dart`）；已经是调色板的 PNG 也不再动第二次。
///
/// 只作用于**打包结果**：源文件不动；解不动、带透明、或压完没变小，都原样放行。
/// 结果字节确定（无随机），保持 ui.pkg 的「可复现构建」性质。
class UiImageOptimizer {
  UiImageOptimizer._();

  /// 依次尝试的调色板色数；从小到大，画质过关即采用（省得最多）。
  static const List<int> colorBudgets = <int>[64, 128, 256];

  /// 早停阈值：平均误差 ≤ 2/255 视为肉眼无差别（实测 64 色图标 1.3）。
  static const double imperceptibleError = 2.0;

  /// 兜底阈值：照片在 256 色下仍有细微差异，平均误差 ≤ 4/255 可接受；
  /// 超过就不压了（保留原图，宁可大也不糊）。
  static const double acceptableError = 4.0;

  /// 超过这个像素数就跳过：打包（含热重载）不应被大图拖住。
  static const int maxPixels = 4 * 1000 * 1000;

  /// 该扩展名是否支持压缩。
  /// 只做 PNG：JPEG 本身有损，重编码省得有限还再掉一次画质。
  static bool supports(String relPath) => relPath.toLowerCase().endsWith('.png');

  /// 压缩 PNG 字节；无收益或失败返回 null（调用方保留原始数据）。
  static Uint8List? optimize(Uint8List bytes) {
    try {
      final decoded = img.decodePng(bytes);
      if (decoded == null ||
          decoded.width * decoded.height > maxPixels ||
          decoded.hasPalette || // 已经是调色板 PNG：二次量化 = 有损叠有损
          _hasTransparency(decoded)) {
        return null;
      }
      return _pick(decoded, bytes.length);
    } catch (_) {
      return null; // 花式 PNG（16bit/交错/异常块）解不动就原样放行
    }
  }

  /// 逐档量化，返回第一个「压小了 + 画质过关」的结果。
  static Uint8List? _pick(img.Image source, int originalLength) {
    for (final colors in colorBudgets) {
      final quantized = img.quantize(
        source,
        numberOfColors: colors,
        method: img.QuantizeMethod.octree,
        dither: img.DitherKernel.none,
      );
      final out = img.encodePng(quantized, level: 9);
      if (out.length >= originalLength) {
        break; // 色数往上只会更大，没戏
      }
      final limit = colors == colorBudgets.last
          ? acceptableError
          : imperceptibleError;
      if (_meanError(source, quantized) <= limit) {
        return out;
      }
    }
    return null;
  }

  /// 三通道平均绝对误差 (0–255)，与原图逐像素比。
  static double _meanError(img.Image source, img.Image quantized) {
    final target = quantized.convert(numChannels: 3);
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final a = source.getPixel(x, y);
        final b = target.getPixel(x, y);
        sum += ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs())
            .toDouble();
        count += 3;
      }
    }
    return sum / count;
  }

  /// 有任何像素不是全不透明就为 true（半透明、全透明都算）。
  static bool _hasTransparency(img.Image image) {
    if (!image.hasAlpha) {
      return false;
    }
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a < 255) {
          return true;
        }
      }
    }
    return false;
  }
}
