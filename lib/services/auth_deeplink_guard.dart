// lib/services/auth_deeplink_guard.dart
import 'package:flutter/foundation.dart';

class AuthDeepLinkGuard {
  static String? _lastCode;
  static DateTime? _lastAt;

  /// 返回 true 表示可以处理；false 表示短时间重复、应忽略
  static bool shouldProcess(Uri uri) {
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return true;

    final now = DateTime.now();
    final same = (_lastCode == code) &&
        (_lastAt != null) &&
        now.difference(_lastAt!).inSeconds < 20;

    if (same) {
      debugPrint('[DeepLinkGuard] duplicate auth code ignored: $code');
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    return true;
  }
}
