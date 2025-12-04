// lib/services/image_normalizer.dart
//
// 统一把选中的图片转换成：最长边 <= 1440、质量 ≈85% 的 JPG（内存中完成，不落盘）
// - iOS / Android：用 flutter_image_compress 的 compressWithList（纯 bytes）
// - Web：直接回传原始 bytes（浏览器端多数已是 jpg/png；若是 HEIC，建议提示或后端转码）
//
// 用法：
//   final res = await ImageNormalizer.normalizeXFile(xfile);
//   final jpgBytes = res.bytes;   // 处理后的 JPG 字节
//   final ext      = res.ext;     // "jpg"
//   final mime     = res.mimeType;// "image/jpeg"

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cross_file/cross_file.dart';
// 用别名，避免 “Undefined name 'CompressFormat' / 'FlutterImageCompress'” 的解析错误
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

class NormalizedImageResult {
  final Uint8List bytes;
  final String ext;       // 一律 "jpg"
  final String mimeType;  // 一律 "image/jpeg"
  const NormalizedImageResult(this.bytes)
      : ext = 'jpg',
        mimeType = 'image/jpeg';
}

class ImageNormalizer {
  static const int _maxDim = 1440; // 最长边
  static const int _quality = 85;  // 压缩质量

  static bool _isHeicExt(String? nameOrPath) {
    final p = (nameOrPath ?? '').toLowerCase();
    return p.endsWith('.heic') || p.endsWith('.heif');
  }

  static bool _isJpeg(String? nameOrPath) {
    final p = (nameOrPath ?? '').toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg');
  }

  /// 入口：从 XFile 读取为 bytes，再做 JPG 归一化（不使用 file.path、不落盘）
  static Future<NormalizedImageResult> normalizeXFile(XFile file) async {
    final raw = await file.readAsBytes();

    // Web 上 flutter_image_compress 支持有限，直接返回原始（多数已是 jpg/png）
    if (kIsWeb) {
      return NormalizedImageResult(raw);
    }

    // 移动端：非 JPG 或分辨率过大，都转成 JPG 并限制尺寸
    return await _normalizeBytesToJpeg(
      raw,
      treatAsHeic: _isHeicExt(file.path),
      alreadyJpeg: _isJpeg(file.path),
    );
  }

  /// 直接从 bytes 归一化到 JPG（给其他调用方使用）
  static Future<NormalizedImageResult> normalizeBytesToJpeg(
      Uint8List input,
      ) async {
    if (kIsWeb) return NormalizedImageResult(input);
    return await _normalizeBytesToJpeg(input);
  }

  // ---------------- internal (pure-bytes) ----------------

  static Future<NormalizedImageResult> _normalizeBytesToJpeg(
      Uint8List input, {
        bool treatAsHeic = false,
        bool alreadyJpeg = false,
      }) async {
    // 统一用 compressWithList（纯内存）做一次有损压缩，同时限制最长边
    final out = await fic.FlutterImageCompress.compressWithList(
      input,
      minWidth: _maxDim,
      minHeight: _maxDim,
      quality: _quality,
      format: fic.CompressFormat.jpeg, // 👈 统一输出 JPG
      keepExif: true,
    );

    // compressWithList 必定返回 List<int>，这里转回 Uint8List
    return NormalizedImageResult(Uint8List.fromList(out));
  }
}
