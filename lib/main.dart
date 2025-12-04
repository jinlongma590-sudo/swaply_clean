import 'dart:async';
import 'dart:ui'; // PlatformDispatcher
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ 1. 引入 Native Splash
import 'package:flutter_native_splash/flutter_native_splash.dart';

// 本地通知 & 深链处理
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swaply/services/deep_link_service.dart';

// ✅ [P0 修复] OAuth 状态恢复
import 'package:swaply/services/oauth_entry.dart';

// 引入你的 App 入口
import 'package:swaply/core/app.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  final payload = details.payload;
  if (payload != null && payload.isNotEmpty) {
    DeepLinkService.instance.handle(payload);
  }
}

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  // ✅ 兼容 3.38.1：删除 iOS 的 onDidReceiveLocalNotification 参数
  final iosInit = const DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

  // ✅ 兼容 3.38.1：initialize 里不再传 onDidReceiveLocalNotification
  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        DeepLinkService.instance.handle(payload);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

Future<void> main() async {
  // ✅ 2. 确保绑定初始化
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ✅ 3. 保留启动图，等首屏就绪再移除
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 错误处理
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[GlobalFlutterError] ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[GlobalUncaughtError] $error\n$stack');
    return true;
  };

  // 初始化本地通知
  await _initLocalNotifications();

  // ================================================
  // ✅ [Session 持久化修复] Supabase 初始化
  // 添加 authOptions 配置，解决从外部应用返回后
  // Session 丢失导致跳到登录页的问题
  // 注意：persistSession 在新版本中默认启用，无需显式设置
  // ================================================
  await Supabase.initialize(
    url: 'https://rhckybselarzglkmlyqs.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,  // ✅ 使用 PKCE 流程（更安全的持久化）
      autoRefreshToken: true,           // ✅ 自动刷新 token（防止过期）
      // persistSession 在新版本中默认启用，无需显式设置
    ),
  );

  // ================================================
  // ✅ 【状态栏修复】全局唯一配置
  // 符合 Swaply 单一导航源架构
  // 所有页面自动继承此配置
  // ================================================

  // ✅ 修复 1：显式启用状态栏和导航栏
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [
      SystemUiOverlay.top,    // 显示顶部状态栏
      SystemUiOverlay.bottom, // 显示底部导航栏
    ],
  );

  // ✅ 修复 2：设置全局状态栏样式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    // iOS 配置
    statusBarBrightness: Brightness.light, // iOS：浅色状态栏（深色文字）

    // Android 配置
    statusBarIconBrightness: Brightness.dark, // ✅ 修复：深色图标（黑色），在浅色背景上清晰可见
    statusBarColor: Colors.transparent, // 透明背景（让页面颜色透出来）

    // 底部导航栏配置
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // 设置竖屏模式
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ✅ [P0 修复] 删除此处的 FlutterNativeSplash.remove()
  // Splash 移除逻辑已移至 app.dart 的 postFrameCallback 中
  // 确保首帧渲染完成后再移除，避免 iOS 冷启动黑屏

  // ✅ [OAuth 修复] 在 runApp 之前恢复 OAuth 状态
  // 确保 MainNavigationPage 第一次 build 时，OAuthEntry.inFlight 已经是正确的值
  await OAuthEntry.restoreState();

  // 启动应用
  runApp(const SwaplyApp());
}
