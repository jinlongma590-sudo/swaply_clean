// lib/core/app.dart
//
// ✅ [性能优化] 关键改动：
// 1. 减少 splash 等待超时时间（3秒 → 1.5秒）
// 2. 优化初始导航等待逻辑
// 3. 减少不必要的延迟

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
// ✅ 1. 引入 ScreenUtil
import 'package:flutter_screenutil/flutter_screenutil.dart';
// ✅ [P0 修复] 引入 FlutterNativeSplash
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/core/navigation/app_router.dart';
import 'package:swaply/services/deep_link_service.dart';
import 'package:swaply/providers/language_provider.dart';
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/pages/main_navigation_page.dart';

// ✅ 类名修改为 SwaplyApp (匹配 main.dart)
class SwaplyApp extends StatefulWidget {
  const SwaplyApp({super.key});

  @override
  State<SwaplyApp> createState() => _SwaplyAppState();
}

class _SwaplyAppState extends State<SwaplyApp> {
  bool _booted = false;
  final bool _welcomeScheduled = false;

  // 确保 DeepLinkService.bootstrap() 全局只运行一次
  bool _dlBooted = false;
  
  // 记录应用启动时间（用于计算启动页显示时长）
  late final DateTime _appStartTime = DateTime.now();

  /// ✅ [性能优化] 减少等待超时时间
  /// 原来：3秒超时
  /// 优化后：1.5秒超时（大部分情况下初始导航在500ms内完成）
  Future<void> _waitUntilInitialNavigationOrTimeout() async {
    // ✅ 减少超时时间：3秒 → 1.5秒
    const timeout = Duration(milliseconds: 1500);
    final start = DateTime.now();

    // ✅ 优化轮询频率：16ms → 50ms（减少CPU占用）
    const pollInterval = Duration(milliseconds: 50);

    while (mounted) {
      if (AuthFlowObserver.hasCompletedInitialNavigation) {
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        debugPrint('✅ [App] 初始导航完成，耗时: ${elapsed}ms');
        return;
      }
      if (DateTime.now().difference(start) >= timeout) {
        if (kDebugMode) {
          debugPrint(
              '[App] ⏱️ Wait initial navigation timeout (1.5s), removing splash anyway');
        }
        return;
      }
      await Future.delayed(pollInterval);
    }
  }

  @override
  void initState() {
    super.initState();

    // ✅ [P0 修复] 新增：恢复 OAuth 状态
    // 解决进程重启后 inFlight 状态丢失的问题
    OAuthEntry.restoreState();

    // ✅ [冷启动深链修复] 关键改动：在首帧后立即初始化 DeepLinkService
    // 必须在 AuthFlowObserver.start() 之前完成，避免时序竞态
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dlBooted) return;
      _dlBooted = true;

      final startTime = DateTime.now();

      // ✅ [方案 2 - 关键修复] 先初始化深链服务
      // bootstrap() 现在会真正等待初始链接处理完成
      // 不需要额外的轮询等待，语义清晰，更可靠
      if (!kIsWeb) {
        if (kDebugMode) {
          debugPrint('[App] 🚀 Bootstrapping DeepLinkService...');
        }

        try {
          await DeepLinkService.instance.bootstrap();
          final bootstrapTime =
              DateTime.now().difference(startTime).inMilliseconds;
          debugPrint(
              '[App] ✅ DeepLinkService bootstrap completed (${bootstrapTime}ms)');
        } catch (e) {
          debugPrint('[App] ⚠️ DeepLinkService bootstrap failed: $e');
        }
      }

      // ✅ [关键] 深链初始化完成后，再启动认证流观察
      // 这样 AuthFlowObserver 的 initialSession 事件处理时
      // 就能正确检测到 _handlingBusinessDeepLink 标志
      if (kDebugMode) {
        debugPrint('[App] 🔐 Starting AuthFlowObserver...');
      }

      try {
        AuthFlowObserver.I.start();
        final authTime = DateTime.now().difference(startTime).inMilliseconds;
        debugPrint('[App] ✅ AuthFlowObserver started (${authTime}ms)');
      } catch (e) {
        debugPrint('[App] ⚠️ AuthFlowObserver start failed: $e');
      }

      // ✅ [性能优化] 等待初始导航或超时（最多1.5秒）
      await _waitUntilInitialNavigationOrTimeout();

      // ✅ 移除 Splash
      try {
        final beforeRemove = DateTime.now();
        FlutterNativeSplash.remove();
        final afterRemove = DateTime.now();
        final removeTime = afterRemove.difference(beforeRemove).inMilliseconds;
        final totalTime = afterRemove.difference(startTime).inMilliseconds;
        
        debugPrint('[App] ✅ Native Splash removed (移除耗时: ${removeTime}ms, 总耗时: ${totalTime}ms)');
        debugPrint('[SplashDebug] 🚫 FlutterNativeSplash.remove() called at: $afterRemove');
        debugPrint('[SplashDebug] ⏱️  Splash display duration: ${afterRemove.difference(_appStartTime).inMilliseconds}ms');
        
        // ✅ 通知 DeepLinkService 启动页已移除（解决安卓设备深链拉起时启动页logo不显示问题）
        DeepLinkService.notifySplashRemoved();
        debugPrint('[SplashDebug] 📢 notifySplashRemoved() called');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[App] ⚠️ Failed to remove splash: $e');
        }
      }

      if (mounted) {
        setState(() {
          _booted = true;
        });
      }

      final totalBootTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[App] ✅ App initialization completed (${totalBootTime}ms)');
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 2. 必须用 ScreenUtilInit 包裹整个 MaterialApp
    return ScreenUtilInit(
      // ⚠️ 调整为 UI 设计稿尺寸 (标准通常是 375x812)
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) {
        return ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: MaterialApp(
            title: 'Swaply ZW',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavKey, // Global Navigator（唯一）

            // 路由配置 (保持原有逻辑)
            onGenerateRoute: AppRouter.onGenerateRoute,
            onUnknownRoute: (settings) => MaterialPageRoute(
                builder: (_) => const MainNavigationPage()), // ✅ 兜底，防黑屏
            initialRoute: '/', // 由 AuthFlowObserver 接管跳转

            theme: ThemeData(
              primaryColor: const Color(0xFF1877F2),
              useMaterial3: false,
              scaffoldBackgroundColor: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
