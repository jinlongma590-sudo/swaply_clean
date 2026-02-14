// lib/utils/image_utils.dart
// Supabase 图片流量优化工具

import 'package:flutter/foundation.dart';

/// Supabase 图片优化配置
class SupabaseImageConfig {
  /// Supabase 存储域名（用于识别需要优化的图片）
  static const List<String> supabaseDomains = [
    'rhckybselarzglkmlyqs.supabase.co',
    'supabase.co',
    // 添加其他可能的 Supabase 域名
  ];

  /// 检查 URL 是否来自 Supabase 存储
  static bool isSupabaseImage(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    final host = uri.host.toLowerCase();
    return supabaseDomains.any((domain) => host.contains(domain));
  }

  /// 生成优化后的图片 URL
  /// 
  /// 参数说明：
  /// - width: 目标宽度（像素），高度按比例自动计算
  /// - quality: 压缩质量 (1-100)，默认 60
  /// - format: 输出格式，默认 'webp'（体积最小）
  /// - resize: 调整模式，默认 'cover'（裁剪填充）
  /// - height: 可选，指定高度（如果同时指定 width 和 height，会按指定尺寸裁剪）
  static String getOptimizedUrl(
    String originalUrl, {
    int? width,
    int? height,
    int quality = 60,
    String format = 'webp',
    String resize = 'cover',
  }) {
    // 非 Supabase 图片不处理
    if (!isSupabaseImage(originalUrl)) {
      return originalUrl;
    }

    // 解析原始 URL
    final uri = Uri.parse(originalUrl);
    final params = Map<String, String>.from(uri.queryParameters);

    // 添加图片转换参数
    if (width != null) params['width'] = width.toString();
    if (height != null) params['height'] = height.toString();
    params['quality'] = quality.toString();
    params['format'] = format;
    params['resize'] = resize;

    // 构建新 URL
    return uri.replace(queryParameters: params).toString();
  }

  /// 为列表项（缩略图）生成优化 URL
  /// 目标：15KB - 30KB 之间
  static String getThumbnailUrl(String originalUrl) {
    return getOptimizedUrl(
      originalUrl,
      width: 400,
      quality: 50,
      format: 'webp',
      resize: 'cover',
    );
  }

  /// 为商品详情页生成优化 URL
  /// 目标：100KB 左右
  static String getDetailUrl(String originalUrl) {
    return getOptimizedUrl(
      originalUrl,
      width: 1080,
      quality: 75,
      format: 'webp',
      resize: 'contain', // 详情页显示完整图片
    );
  }

  /// 为用户头像生成优化 URL
  static String getAvatarUrl(String originalUrl) {
    return getOptimizedUrl(
      originalUrl,
      width: 120,
      height: 120,
      quality: 70,
      format: 'webp',
      resize: 'cover',
    );
  }
}

/// 优化的图片加载组件配置
class OptimizedImageConfig {
  /// 不同场景的预设配置
  static Map<String, dynamic> get thumbnail => {
        'width': 400,
        'quality': 50,
        'format': 'webp',
        'resize': 'cover',
        'estimatedSizeKB': 20, // 预估大小：15-30KB
      };

  static Map<String, dynamic> get detail => {
        'width': 1080,
        'quality': 75,
        'format': 'webp',
        'resize': 'contain',
        'estimatedSizeKB': 100,
      };

  static Map<String, dynamic> get avatar => {
        'width': 120,
        'height': 120,
        'quality': 70,
        'format': 'webp',
        'resize': 'cover',
        'estimatedSizeKB': 10,
      };
}