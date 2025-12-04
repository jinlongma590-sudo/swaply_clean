// lib/core/app.dart
//
// 全局唯一 App 入口（唯一 MaterialApp）
// ● 挂 rootNavKey
// ● 深链 DeepLinkService 单例集中 bootstrap（首帧后启动）
// ● 登录后调用 ensureWelcomeForCurrentUser（写 pending flag）
// ● HomePage / MainNavigationPage 只负责 UI，不负责全局逻辑
// ● 全工程只有这一个 MaterialApp —— 根本解决黑屏 / GlobalKey 冲突
//

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  @override
  void initState() {
    super.initState();

    // ✅ [P0 修复] 新增：恢复 OAuth 状态
    // 解决进程重启后 inFlight 状态丢失的问题
    OAuthEntry.restoreState();

    // 启动全局认证流观察 —— 唯一导航源
    AuthFlowObserver.I.start();

    // ✅ [P0 修复] 深链 + Splash 移除：在首帧后统一处理
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dlBooted) return;
      _dlBooted = true;

      // ✅ 统一在这里移除 Splash（确保首帧已渲染）
      // 这是全局唯一的 Splash 移除点，避免 iOS 冷启动黑屏
      FlutterNativeSplash.remove();

      if (!kIsWeb) {
        await DeepLinkService.instance.bootstrap();
      }

      setState(() {
        _booted = true;
      });
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
