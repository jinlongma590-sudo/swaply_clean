import 'dart:async';
import 'dart:ui'; // PlatformDispatcher
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ [推送通知] Firebase 核心导入
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

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

// ================================================
// ✅ [推送通知] Firebase 后台消息处理器（顶级函数）
// 必须在 main() 之外定义，这样 App 被清理后也能接收通知
// ================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 必须初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('🔔 [Background] 收到后台消息: ${message.notification?.title}');

  // 显示本地通知
  await _showLocalNotification(message);
}

// ✅ [推送通知] 本地通知点击处理（后台）
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  final payload = details.payload;
  if (payload != null && payload.isNotEmpty) {
    debugPrint('🔔 [Background] 点击通知: $payload');
    // ✅ 符合架构：通过 DeepLinkService 处理跳转
    DeepLinkService.instance.handle(payload);
  }
}

// ✅ [推送通知] 显示本地通知的通用方法
Future<void> _showLocalNotification(RemoteMessage message) async {
  final notification = message.notification;
  final data = message.data;

  if (notification == null) return;

  // 构建深链 payload（符合 NotificationService.buildXXXPayload 格式）
  final payload = data['payload'] ??
      data['deep_link'] ??
      data['link'] ??
      '';

  const androidDetails = AndroidNotificationDetails(
    'swaply_notifications',
    'Swaply Notifications',
    channelDescription: 'Notifications for offers, messages, and updates',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
    color: Color(0xFF1877F2),
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await _localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    details,
    payload: payload,
  );
}

// ✅ [推送通知] 初始化本地通知
Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        debugPrint('🔔 [Foreground] 点击通知: $payload');
        // ✅ 符合架构：通过 DeepLinkService 处理跳转
        DeepLinkService.instance.handle(payload);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // ✅ 创建 Android 通知渠道
  const channel = AndroidNotificationChannel(
    'swaply_notifications',
    'Swaply Notifications',
    description: 'Notifications for offers, messages, and updates',
    importance: Importance.high,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

// ================================================
// ✅ [推送通知] 初始化 Firebase Messaging
// 🔧 修复：添加完整的错误处理，确保失败不会阻塞 App 启动
// ================================================
Future<void> _initFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;

    // 1. 请求通知权限
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('🔔 通知权限状态: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('⚠️ 请求通知权限失败: $e');
      // 权限请求失败不应该阻塞启动，继续执行
    }

    // 2. 获取 FCM Token（添加错误处理）
    try {
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('🔔 FCM Token: $token');
        // ✅ Token 会在 NotificationService.subscribeUser 时保存到 Supabase
      } else {
        debugPrint('⚠️ FCM Token 为空（可能在模拟器上运行）');
      }
    } catch (e) {
      // 🔧 关键修复：getToken 失败不应该阻塞启动
      debugPrint('⚠️ 获取 FCM Token 失败: $e');
      debugPrint('💡 提示：如果在模拟器上运行，请确保安装了 Google Play Services');
      debugPrint('💡 或者在真机上测试推送通知功能');
      // 不抛出异常，让 App 继续启动
    }

    // 3. 监听 Token 刷新
    messaging.onTokenRefresh.listen(
          (newToken) {
        debugPrint('🔔 FCM Token 刷新: $newToken');
        // ✅ Token 刷新会在 NotificationService 中处理
      },
      onError: (error) {
        debugPrint('⚠️ Token 刷新失败: $error');
      },
    );

    // 4. 前台消息处理
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 [Foreground] 收到消息: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // 5. 点击通知打开 App
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 [Opened] 点击通知打开App');
      final payload = message.data['payload'] ??
          message.data['deep_link'] ??
          message.data['link'] ??
          '';
      if (payload.isNotEmpty) {
        // ✅ 符合架构：通过 DeepLinkService 处理跳转
        DeepLinkService.instance.handle(payload);
      }
    });

    // 6. 检查是否从通知启动
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🔔 [Initial] 从通知启动App');
      final payload = initialMessage.data['payload'] ??
          initialMessage.data['deep_link'] ??
          initialMessage.data['link'] ??
          '';
      if (payload.isNotEmpty) {
        // ✅ 符合架构：延迟处理，等待 App 完全初始化
        // 不干预 AuthFlowObserver 的首次导航
        Future.delayed(const Duration(seconds: 1), () {
          DeepLinkService.instance.handle(payload);
        });
      }
    }

    debugPrint('✅ Firebase Messaging 初始化成功');
  } catch (e, stackTrace) {
    // 🔧 最外层兜底：即使整个 Firebase Messaging 失败，也不能阻塞启动
    debugPrint('❌ Firebase Messaging 初始化失败: $e');
    debugPrint('📍 堆栈: $stackTrace');
    debugPrint('💡 App 将继续运行，但推送通知功能可能不可用');
    // 不抛出异常，让 main() 继续执行
  }
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

  // ================================================
  // ✅ [推送通知] Firebase 初始化（必须在最前面）
  // ================================================
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase 初始化成功');
  } catch (e) {
    debugPrint('❌ Firebase 初始化失败: $e');
    debugPrint('💡 App 将继续运行，但 Firebase 功能可能不可用');
    // 不抛出异常，让 App 继续启动
  }

  // ✅ [推送通知] 设置后台消息处理器（必须在 runApp 之前）
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('✅ Firebase 后台消息处理器注册成功');
  } catch (e) {
    debugPrint('⚠️ Firebase 后台消息处理器注册失败: $e');
  }

  // ================================================
  // ✅ 初始化本地通知
  // ================================================
  try {
    await _initLocalNotifications();
    debugPrint('✅ 本地通知初始化成功');
  } catch (e) {
    debugPrint('❌ 本地通知初始化失败: $e');
  }

  // ✅ [推送通知] 初始化 FCM（添加了完整错误处理）
  await _initFirebaseMessaging();

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
      authFlowType: AuthFlowType.pkce, // ✅ 使用 PKCE 流程（更安全的持久化）
      autoRefreshToken: true, // ✅ 自动刷新 token（防止过期）
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
      SystemUiOverlay.top, // 显示顶部状态栏
      SystemUiOverlay.bottom, // 显示底部导航栏
    ],
  );

  // ✅ 修复 2：设置全局状态栏样式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    // iOS 配置
    statusBarBrightness: Brightness.light, // iOS：浅色状态栏（深色文字）

    // Android 配置
    statusBarIconBrightness:
    Brightness.dark, // ✅ 修复：深色图标（黑色），在浅色背景上清晰可见
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

  // ================================================
  // ✅ 启动应用
  // 符合架构：所有导航由 AuthFlowObserver 和 DeepLinkService 控制
  // ================================================
  runApp(const SwaplyApp());
}
