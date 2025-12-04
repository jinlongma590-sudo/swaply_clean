// lib/services/offer_detail_cache.dart
//
// OfferDetailCache —— OfferDetailPage 专用内存缓存
//
// 功能：
// 1. 缓存 offer 详情 + 消息列表
// 2. 5 分钟自动过期
// 3. 支持预取（从通知页面跳转前预加载）
// 4. 页面关闭时自动清理
//
// 架构合规性：
// ✅ 不干扰 AuthFlowObserver
// ✅ 不干扰 DeepLinkService
// ✅ 纯内存缓存，无持久化
// ✅ 线程安全（单例模式）

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:swaply/services/offer_service.dart';
import 'package:swaply/services/message_service.dart';

class OfferDetailCache {
  // 单例模式
  OfferDetailCache._();
  static final OfferDetailCache _instance = OfferDetailCache._();
  static OfferDetailCache get instance => _instance;

  // 简单内存缓存（Map 存储）
  static final Map<String, _CacheEntry> _cache = {};

  // 缓存过期时间（5 分钟）
  static const _maxAge = Duration(minutes: 5);

  // Debug 日志
  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[OfferDetailCache] $message');
    }
  }

  /// 🚀 预取数据（fire-and-forget，不阻塞导航）
  ///
  /// 使用场景：通知页面点击通知时调用
  /// ```dart
  /// OfferDetailCache.prefetch(offerId);  // 不需要 await
  /// await navPush('/offer-detail', arguments: {'offerId': offerId});
  /// ```
  static Future<void> prefetch(String offerId) async {
    if (offerId.isEmpty) return;

    // 如果缓存有效，直接返回
    if (_isValid(offerId)) {
      _log('Cache hit for prefetch: $offerId');
      return;
    }

    _log('Prefetching data for offer: $offerId');

    try {
      // 并行请求 offer 详情 + 消息列表
      final results = await Future.wait([
        OfferService.getOfferDetails(offerId),
        MessageService.getOfferMessages(offerId: offerId),
      ], eagerError: false);

      final details = results[0] as Map<String, dynamic>?;
      final messages = results[1] as List<Map<String, dynamic>>?;

      if (details != null || messages != null) {
        _cache[offerId] = _CacheEntry(
          details: details,
          messages: messages ?? [],
          timestamp: DateTime.now(),
        );
        _log('Prefetch success: $offerId (${messages?.length ?? 0} messages)');
      }
    } catch (e) {
      _log('Prefetch failed for $offerId: $e');
      // 静默失败，不影响正常流程
    }
  }

  /// 获取缓存的 offer 详情
  ///
  /// 返回 null 表示缓存未命中或已过期
  static Map<String, dynamic>? getDetails(String offerId) {
    final entry = _cache[offerId];
    if (entry == null) {
      _log('Cache miss (details): $offerId');
      return null;
    }

    if (DateTime.now().difference(entry.timestamp) > _maxAge) {
      _log('Cache expired (details): $offerId');
      _cache.remove(offerId);
      return null;
    }

    _log('Cache hit (details): $offerId');
    return entry.details;
  }

  /// 获取缓存的消息列表
  ///
  /// 返回 null 表示缓存未命中或已过期
  static List<Map<String, dynamic>>? getMessages(String offerId) {
    final entry = _cache[offerId];
    if (entry == null) {
      _log('Cache miss (messages): $offerId');
      return null;
    }

    if (DateTime.now().difference(entry.timestamp) > _maxAge) {
      _log('Cache expired (messages): $offerId');
      _cache.remove(offerId);
      return null;
    }

    _log('Cache hit (messages): $offerId (${entry.messages.length} messages)');
    return entry.messages;
  }

  /// 检查缓存是否有效
  static bool _isValid(String offerId) {
    final entry = _cache[offerId];
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) <= _maxAge;
  }

  /// 清理指定 offer 的缓存
  ///
  /// 使用场景：页面 dispose 时调用
  static void clear(String offerId) {
    if (_cache.remove(offerId) != null) {
      _log('Cache cleared: $offerId');
    }
  }

  /// 清理所有缓存
  ///
  /// 使用场景：用户登出时调用
  static void clearAll() {
    final count = _cache.length;
    _cache.clear();
    _log('All cache cleared ($count entries)');
  }

  /// 获取缓存统计信息（用于调试）
  static Map<String, dynamic> getStats() {
    final now = DateTime.now();
    int validCount = 0;
    int expiredCount = 0;

    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) <= _maxAge) {
        validCount++;
      } else {
        expiredCount++;
      }
    }

    return {
      'total': _cache.length,
      'valid': validCount,
      'expired': expiredCount,
      'max_age_minutes': _maxAge.inMinutes,
    };
  }

  /// 手动清理过期缓存（可选）
  ///
  /// 通常不需要手动调用，因为每次访问时会自动清理
  static void cleanupExpired() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (now.difference(entry.value.timestamp) > _maxAge) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      _log('Cleaned up ${keysToRemove.length} expired entries');
    }
  }
}

/// 缓存条目（内部使用）
class _CacheEntry {
  final Map<String, dynamic>? details;
  final List<Map<String, dynamic>> messages;
  final DateTime timestamp;

  _CacheEntry({
    required this.details,
    required this.messages,
    required this.timestamp,
  });

  @override
  String toString() {
    return '_CacheEntry(hasDetails: ${details != null}, '
        'messageCount: ${messages.length}, '
        'timestamp: $timestamp)';
  }
}