// lib/router/nav_throttler.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// Same folder import to avoid package name typos
import 'root_nav.dart' as root;

/// Navigation throttler to avoid rapid double-taps and duplicate pushes.
class NavThrottler {
  NavThrottler._();

  static DateTime? _lastAt;
  static String? _lastKey;

  static bool _ready(
      String? key, {
        Duration minInterval = const Duration(milliseconds: 300),
      }) {
    final now = DateTime.now();

    // 1) time interval throttle
    if (_lastAt != null && now.difference(_lastAt!) < minInterval) {
      if (kDebugMode) {
        debugPrint(
          '[NavThrottler] drop "${key ?? "(no-key)"}" '
              '(interval < ${minInterval.inMilliseconds}ms)',
        );
      }
      return false;
    }

    // 2) deduplicate by key
    if (key != null && _lastKey == key) {
      if (kDebugMode) debugPrint('[NavThrottler] drop duplicate key "$key"');
      return false;
    }

    _lastAt = now;
    _lastKey = key;
    return true;
  }

  /// push by named route (String)
  static Future<T?> pushNamed<T extends Object?>(
      String name, {
        Object? arguments,
        String? dedupKey, // default: route name
        Duration minInterval = const Duration(milliseconds: 300),
      }) {
    final key = dedupKey ?? name;
    if (!_ready(key, minInterval: minInterval)) {
      return Future<T?>.value(null);
    }
    return root.navPush<T>(name, arguments: arguments);
  }

  /// replaceAll (clear stack then go)
  static Future<T?> replaceAll<T extends Object?>(
      String name, {
        Object? arguments,
        String? dedupKey,
        Duration minInterval = const Duration(milliseconds: 300),
      }) {
    final key = dedupKey ?? name;
    if (!_ready(key, minInterval: minInterval)) {
      return Future<T?>.value(null);
    }
    return root.navReplaceAll<T>(name, arguments: arguments);
  }

  /// push a custom Route<T>
  static Future<T?> pushRoute<T extends Object?>(
      Route<T> route, {
        String? dedupKey, // default: route.settings.name or hash
        Duration minInterval = const Duration(milliseconds: 300),
      }) {
    final key = dedupKey ?? route.settings.name ?? route.hashCode.toString();
    if (!_ready(key, minInterval: minInterval)) {
      return Future<T?>.value(null);
    }
    return root.navPushRoute<T>(route);
  }

  /// maybePop (no throttling)
  static Future<bool> maybePop<T extends Object?>([T? result]) {
    return root.navMaybePop<T>(result);
  }

  /// manually reset throttling state (optional)
  static void reset() {
    _lastAt = null;
    _lastKey = null;
  }
}
