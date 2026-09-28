import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:myhome/ui_runtime/ui_image_optimizer.dart';

/// 合成一张"照片级"测试图：径向渐变 + 固定种子噪声。
/// 噪声是必须的——纯渐变 PNG 本身就能压到极小，量化反而更大，测不出收益。
///
/// [alpha] 为 null 时无 alpha 通道；否则表示边缘处最多掉多少不透明度
/// （0 = 有 alpha 通道但全不透明；> 0 = 真的半透明）。
Uint8List photoLikePng({int size = 192, int? alpha}) {
  final image =
      img.Image(width: size, height: size, numChannels: alpha == null ? 3 : 4);
  final random = Random(20260928);
  final center = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - center;
      final dy = y - center;
      final d = sqrt(dx * dx + dy * dy) / center; // 0(中心) → ~1.41(角)
      final r = (215 - d * 90 + random.nextInt(25) - 12).round().clamp(0, 255);
      final g = (170 - d * 70 + random.nextInt(25) - 12).round().clamp(0, 255);
      final b = (120 - d * 60 + random.nextInt(25) - 12).round().clamp(0, 255);
      if (alpha == null) {
        image.setPixelRgb(x, y, r, g, b);
      } else {
        final a = (255 - d * alpha).round().clamp(0, 255);
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }
  return img.encodePng(image);
}

void main() {
  test('supports：只认 PNG', () {
    expect(UiImageOptimizer.supports('icons/icon-192.png'), isTrue);
    expect(UiImageOptimizer.supports('A.PNG'), isTrue);
    expect(UiImageOptimizer.supports('photo.jpg'), isFalse);
    expect(UiImageOptimizer.supports('app.js'), isFalse);
  });

  test('照片级 PNG → 量化后有收益、尺寸不变、能解回来', () {
    final source = photoLikePng();
    final optimized = UiImageOptimizer.optimize(source);

    expect(optimized, isNotNull);
    expect(optimized!.length, lessThan(source.length),
        reason: '量化后应更小 (${source.length} → ${optimized.length})');
    final decoded = img.decodePng(optimized);
    expect(decoded, isNotNull);
    expect(decoded!.width, 192);
    expect(decoded.height, 192);
  });

  test('带透明通道的 PNG：跳过压缩（quantize 会丢 alpha）', () {
    final source = photoLikePng(size: 64, alpha: 120);
    expect(UiImageOptimizer.optimize(source), isNull);
  });

  test('有 alpha 通道但全不透明：照常压缩', () {
    final source = photoLikePng(size: 96, alpha: 0);
    final optimized = UiImageOptimizer.optimize(source);

    expect(optimized, isNotNull);
    expect(optimized!.length, lessThan(source.length));
    expect(img.decodePng(optimized), isNotNull);
  });

  test('已经压过的调色板 PNG：不再二次量化', () {
    final once = UiImageOptimizer.optimize(photoLikePng());
    expect(once, isNotNull);
    expect(img.decodePng(once!)!.hasPalette, isTrue);
    expect(UiImageOptimizer.optimize(once), isNull);
  });

  test('非 PNG / 垃圾字节 → null (调用方保留原数据)', () {
    expect(UiImageOptimizer.optimize(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    expect(
      UiImageOptimizer.optimize(Uint8List.fromList('not a png'.codeUnits)),
      isNull,
    );
  });

  test('压不小就返回 null (纯色小图)', () {
    final flat = img.Image(width: 8, height: 8);
    img.fill(flat, color: img.ColorRgb8(200, 200, 200));
    final source = img.encodePng(flat);
    // 纯色 PNG 已经极小，量化最多持平；持平/更大都应返回 null
    final optimized = UiImageOptimizer.optimize(source);
    if (optimized != null) {
      expect(optimized.length, lessThan(source.length));
    }
  });
}
