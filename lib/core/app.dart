// lib/core/app.dart
//
// 全局唯一 App 入口（唯一 MaterialApp）
// ● 挂 rootNavKey
// ● 深链 DeepLinkService 单例集中 bootstrap（首帧后启动）
// ● 登录后调用 ensureWelcomeForCurrentUser（写 pending flag）
// ● HomePage / MainNavigationPage 只负责 UI，不负责全局逻辑
// ● 全工程只有这一个 MaterialApp —— 根本解决黑屏 / GlobalKey 冲突
//
// ✅ [方案 2 修复] DeepLinkService.bootstrap() 现在会真正等待初始链接处理完成
//    调用者无需额外等待，语义清晰，职责明确

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
// ✅ 1. 引入 ScreenUtil
import 'package:flutter_screenutil/flutter_screenutil.dart';
// ✅ [P0 修复] 引入 FlutterNativeSplash
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/core/navigation/app_router.dart';
import 'package:swaply/services/deep_link_service.dart';
import 'package:swaply/services/welcome_dialog_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/providers/language_provider.dart';
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/services/oauth_entry.dart';  // ✅ [P0 修复] 新增：恢复 OAuth 状态
import 'package:swaply/pages/main_navigation_page.dart'; // ✅ 兜底路由所需

// ✅ 类名修改为 SwaplyApp (匹配 main.dart)
class SwaplyApp extends StatefulWidget {
  const SwaplyApp({super.key});

  @override
  State<SwaplyApp> createState() => _SwaplyAppState();
}

class _SwaplyAppState extends State<SwaplyApp> {
  bool _booted = false;
  bool _welcomeScheduled = false;

  // 确保 DeepLinkService.bootstrap() 全局只运行一次
  bool _dlBooted = false;

  /// ✅ 统一启动屏一致性：等 “初始导航稳定” 再移除 Native Splash
  /// - 桌面点 App：AuthFlowObserver 很快完成 initial navigation
  /// - 网页/通知拉起：DeepLinkService 先处理初始链接，再由 AuthFlowObserver 做最终仲裁
  /// 这样不会出现 “Splash 掀开 → 露出一帧 MainNavigation → 再跳转” 的不一致观感
  Future<void> _waitUntilInitialNavigationOrTimeout() async {
    // 这个超时只是兜底，避免极端情况下 splash 卡死
    const timeout = Duration(seconds: 3);
    final start = DateTime.now();

    while (mounted) {
      if (AuthFlowObserver.hasCompletedInitialNavigation) {
        return;
      }
      if (DateTime.now().difference(start) >= timeout) {
        if (kDebugMode) {
          debugPrint('[App] ⏱️ Wait initial navigation timeout, removing splash anyway');
        }
        return;
      }
      await Future.delayed(const Duration(milliseconds: 16));
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

      // ✅ [方案 2 - 关键修复] 先初始化深链服务
      // bootstrap() 现在会真正等待初始链接处理完成
      // 不需要额外的轮询等待，语义清晰，更可靠
      if (!kIsWeb) {
        if (kDebugMode) {
          debugPrint('[App] 🚀 Bootstrapping DeepLinkService...');
        }

        await DeepLinkService.instance.bootstrap();

        if (kDebugMode) {
          debugPrint('[App] ✅ DeepLinkService bootstrap completed');
        }
      }

      // ✅ [关键] 深链初始化完成后，再启动认证流观察
      // 这样 AuthFlowObserver 的 initialSession 事件处理时
      // 就能正确检测到 _handlingBusinessDeepLink 标志
      if (kDebugMode) {
        debugPrint('[App] 🔐 Starting AuthFlowObserver...');
      }

      AuthFlowObserver.I.start();

      // ✅ 统一在这里移除 Splash（等初始导航稳定后再移除）
      // 这是全局唯一的 Splash 移除点，保证桌面启动 / 网页拉起 / 通知拉起观感一致
      await _waitUntilInitialNavigationOrTimeout();
      try {
        FlutterNativeSplash.remove();
        if (kDebugMode) {
          debugPrint('[App] ✅ Native Splash removed (after initial navigation ready)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[App] ⚠️ Failed to remove splash: $e');
        }
      }

      setState(() {
        _booted = true;
      });

      if (kDebugMode) {
        debugPrint('[App] ✅ App initialization completed');
      }
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
            onUnknownRoute: (settings) =>
                MaterialPageRoute(builder: (_) => const MainNavigationPage()), // ✅ 兜底，防黑屏
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
