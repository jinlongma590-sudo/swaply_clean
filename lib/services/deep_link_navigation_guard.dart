// ========================================
// 热启动深链问题临时修复补丁
// ========================================
// 在找到具体问题之前，先用这个补丁降低失败率

import 'dart:io';
import 'package:flutter/foundation.dart';

/// ✅ 深链导航保护器
/// 防止其他代码在深链处理时干扰导航
class DeepLinkNavigationGuard {
  // 单例模式
  static final DeepLinkNavigationGuard _instance =
      DeepLinkNavigationGuard._internal();
  factory DeepLinkNavigationGuard() => _instance;
  DeepLinkNavigationGuard._internal();

  // ========================================
  // 核心状态
  // ========================================

  /// 是否正在处理深链
  bool _isHandling = false;

  /// 最后一次深链处理时间
  DateTime? _lastHandlingTime;

  /// 锁定的目标路由（深链要导航到的地方）
  String? _targetRoute;

  /// 锁定的参数
  Map<String, dynamic>? _targetArguments;

  // ========================================
  // 公开的检查方法
  // ========================================

  /// 是否正在处理深链
  bool get isHandlingDeepLink => _isHandling;

  /// 是否最近处理过深链（3秒内）
  bool get wasRecentDeepLink {
    if (_lastHandlingTime == null) return false;
    final elapsed = DateTime.now().difference(_lastHandlingTime!);
    return elapsed.inSeconds < 3;
  }

  /// 是否应该阻止指定路由的导航
  bool shouldBlockNavigation(String route) {
    // 如果正在处理深链，阻止所有其他导航
    if (_isHandling) {
      if (kDebugMode) {
        debugPrint('🚫 [Guard] 深链处理中，阻止导航到: $route');
      }
      return true;
    }

    // 如果最近处理过深链，阻止非目标路由的导航
    if (wasRecentDeepLink && route != _targetRoute) {
      if (kDebugMode) {
        debugPrint('🚫 [Guard] 最近有深链，阻止导航到: $route (目标是: $_targetRoute)');
      }
      return true;
    }

    return false;
  }

  // ========================================
  // 深链处理流程
  // ========================================

  /// 开始深链处理
  void startHandling(String targetRoute, {Map<String, dynamic>? arguments}) {
    _isHandling = true;
    _lastHandlingTime = DateTime.now();
    _targetRoute = targetRoute;
    _targetArguments = arguments;

    if (kDebugMode) {
      debugPrint('🔒 [Guard] 开始深链处理');
      debugPrint('   目标路由: $targetRoute');
      debugPrint('   参数: $arguments');
    }
  }

  /// 完成深链处理
  void finishHandling() {
    if (kDebugMode) {
      debugPrint('🔓 [Guard] 完成深链处理');
    }

    _isHandling = false;
    // 注意：不清除 _lastHandlingTime，用于后续的 wasRecentDeepLink 检查
  }

  /// 重置所有状态
  void reset() {
    _isHandling = false;
    _lastHandlingTime = null;
    _targetRoute = null;
    _targetArguments = null;

    if (kDebugMode) {
      debugPrint('♻️  [Guard] 重置所有状态');
    }
  }

  // ========================================
  // 辅助方法
  // ========================================

  /// 获取状态信息（用于调试）
  Map<String, dynamic> getStatus() {
    return {
      'isHandling': _isHandling,
      'wasRecent': wasRecentDeepLink,
      'targetRoute': _targetRoute,
      'targetArguments': _targetArguments,
      'lastHandlingTime': _lastHandlingTime?.toIso8601String(),
    };
  }
}

// ========================================
// 使用示例
// ========================================

/// 示例 1: 在 DeepLinkService 中使用
///
/// ```dart
/// class DeepLinkService {
///   final _guard = DeepLinkNavigationGuard();
///
///   Future<void> _handleUri(Uri uri) async {
///     try {
///       // ✅ 1. 开始深链处理
///       _guard.startHandling('/listing', arguments: {'id': listingId});
///
///       // 2. 等待系统准备好（区分平台）
///       final waitTime = Platform.isIOS
///           ? const Duration(milliseconds: 800)
///           : const Duration(milliseconds: 50);
///       await Future.delayed(waitTime);
///
///       // 3. 执行导航
///       await navPush('/listing', arguments: {'id': listingId});
///
///       // 4. 再等一会，让导航完全完成
///       await Future.delayed(const Duration(milliseconds: 500));
///
///     } finally {
///       // ✅ 5. 标记完成
///       _guard.finishHandling();
///     }
///   }
/// }
/// ```

/// 示例 2: 在生命周期监听器中使用
///
/// ```dart
/// class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
///
///   final _guard = DeepLinkNavigationGuard();
///
///   @override
///   void didChangeAppLifecycleState(AppLifecycleState state) {
///     super.didChangeAppLifecycleState(state);
///
///     if (state == AppLifecycleState.resumed) {
///
///       // ✅ 检查是否应该阻止导航
///       if (_guard.shouldBlockNavigation('/home')) {
///         debugPrint('🚫 检测到深链，跳过热启动导航');
///         return;
///       }
///
///       // ✅ 延迟执行，给深链更多时间
///       Future.delayed(const Duration(milliseconds: 1000), () {
///         if (!_guard.wasRecentDeepLink) {
///           // 执行正常的热启动逻辑
///           _checkAuthOrNavigate();
///         }
///       });
///     }
///   }
/// }
/// ```

/// 示例 3: 在 AuthFlowObserver 中使用
///
/// ```dart
/// class AuthFlowObserver {
///
///   final _guard = DeepLinkNavigationGuard();
///
///   Future<void> start() async {
///
///     // ✅ 检查是否应该跳过
///     if (_guard.shouldBlockNavigation('/home')) {
///       debugPrint('[AuthFlowObserver] 检测到深链，跳过自动导航');
///       return;
///     }
///
///     // 原来的逻辑...
///   }
/// }
/// ```

// ========================================
// 全局访问点（可选）
// ========================================

/// 全局单例访问
final deepLinkGuard = DeepLinkNavigationGuard();

/// 便捷的全局方法
bool shouldBlockNavigationGlobally(String route) {
  return deepLinkGuard.shouldBlockNavigation(route);
}
