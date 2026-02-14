import 'dart:async';
import 'dart:io' show Platform;
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

// 通知服务（用于前台消息刷新）
import 'package:swaply/services/notification_service.dart';

// 引入你的 App 入口
import 'package:swaply/core/app.dart';

// QA Mode for automation testing
const bool kQaMode = bool.fromEnvironment('QA_MODE', defaultValue: false);

// ✅ 前台通知实例（仅用于前台通知）
final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

// ✅ [性能优化] 标记初始化状态,避免重复初始化
bool _fcmInitialized = false;

// ================================================
// ✅ [推送通知] Firebase 后台消息处理器(顶级函数)
// 必须在 main() 之外定义,这样 App 被清理后也能接收通知
// ✅✅✅ 关键修改：简化逻辑，因为原生层已经处理通知显示
// ================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 必须初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    debugPrint('🔔 [Background] 收到后台消息: ${message.data['title'] ?? 'No title'}');
    debugPrint('📦 [Background] Data: ${message.data}');
    debugPrint('✅ [Background] 原生层已创建并显示通知（ACTION_VIEW Intent）');
    debugPrint('✅ [Background] 无需 Flutter 层处理，等待用户点击通知');
  }

  // ✅ 原生层（MyFirebaseMessagingService）已经：
  // 1. 创建了本地通知
  // 2. 使用 ACTION_VIEW Intent
  // 3. 设置了正确的深链 URI
  // Flutter 层不需要做任何事情
}

// ✅ [推送通知] 显示本地通知的通用方法(仅前台使用)
Future<void> _showLocalNotification(RemoteMessage message) async {
  // ✅ 从 data 中获取 title 和 body（因为后端改为纯 data message）
  final title = message.data['title'] ?? 'Swaply';
  final body = message.data['body'] ?? '';
  final payload = message.data['payload'] ??
      message.data['deep_link'] ??
      message.data['link'] ??
      message.data['deeplink'] ??
      '';

  if (title.isEmpty || body.isEmpty) {
    debugPrint('⚠️ [Foreground] Title 或 Body 为空，跳过通知');
    return;
  }

  final offerId = message.data['offer_id'] ?? '';
  final listingId = message.data['listing_id'] ?? '';

  final notificationId = offerId.isNotEmpty
      ? offerId.hashCode.abs()
      : (listingId.isNotEmpty
      ? listingId.hashCode.abs()
      : message.hashCode.abs());

  final groupKey = offerId.isNotEmpty
      ? 'offer_$offerId'
      : (listingId.isNotEmpty ? 'listing_$listingId' : 'swaply_messages');

  final threadIdentifier = groupKey;

  debugPrint('🔔 [Foreground] ID: $notificationId, Group: $groupKey');
  debugPrint('🔔 [Foreground] Title: $title');
  debugPrint('🔔 [Foreground] Body: $body');
  debugPrint('🔔 [Foreground] Payload: $payload');

  final androidDetails = AndroidNotificationDetails(
    'swaply_high_importance',
    'Swaply Notifications',
    channelDescription: 'Notifications for offers, messages, and updates',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
    color: const Color(0xFF1877F2),
    groupKey: groupKey,
    setAsGroupSummary: false,
    onlyAlertOnce: true,
  );

  final iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    threadIdentifier: threadIdentifier,
  );

  final details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  // ✅ 关键修复: show 方法的前4个参数保持位置参数，payload 使用命名参数
  await _localNotifications.show(
    notificationId,
    title,
    body,
    details,
    payload: payload,
  );
}

// ✅ [性能优化] 推送通知初始化(延迟到首屏后)
Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  // ✅ 修复: 第一个参数改为位置参数（适配 v17.2.4）
  await _localNotifications.initialize(
    initSettings, // ✅ 位置参数，不是命名参数
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        debugPrint('🔔 [LocalNotification-Foreground] 点击本地通知: $payload');
        DeepLinkService.instance.handle(payload);
      }
    },
  );

  // ✅ 检查 app 是否由本地通知启动
  final launchDetails =
  await _localNotifications.getNotificationAppLaunchDetails();
  if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
    final payload = launchDetails.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) {
      debugPrint('🚀 [LocalNotification-Launch] App 由通知启动');
      debugPrint('🔗 [LocalNotification-Launch] Payload: $payload');

      Future.delayed(const Duration(milliseconds: 100), () {
        debugPrint('🔗 [LocalNotification-Launch] 处理 payload...');
        DeepLinkService.instance.handle(payload);
      });
    }
  }

  // ✅ 创建 Android 通知渠道
  const channel = AndroidNotificationChannel(
    'swaply_high_importance',
    'Swaply Notifications',
    description: 'Notifications for offers, messages, and updates',
    importance: Importance.high,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
  AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

// ✅ [性能优化] Firebase Messaging 初始化(延迟到首屏后)
Future<void> _initFirebaseMessaging() async {
  if (_fcmInitialized) {
    debugPrint('⚠️ Firebase Messaging 已经初始化,跳过');
    return;
  }

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
    }

    // 2. 获取 FCM Token
    try {
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('🔔 FCM Token 已获取(长度: ${token.length})');
        debugPrint('📌 Token 将在登录成功后自动保存到数据库');
      } else {
        debugPrint('⚠️ FCM Token 为空(可能在模拟器上运行)');
      }
    } catch (e) {
      debugPrint('⚠️ 获取 FCM Token 失败: $e');
      debugPrint('💡 提示:如果在模拟器上运行,请确保安装了 Google Play Services');
    }

    // 3. 监听 Token 刷新
    messaging.onTokenRefresh.listen(
          (newToken) {
        debugPrint('🔔 FCM Token 已刷新');
        debugPrint('📌 新 Token 将由 NotificationService 自动保存');
      },
      onError: (error) {
        debugPrint('⚠️ Token 刷新失败: $error');
      },
    );

    // 4. ✅ 前台消息处理（显示本地通知）
    // 后台消息由 MyFirebaseMessagingService 处理
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('🔔 [Foreground] 收到前台消息');
      debugPrint('📦 [Foreground] Data: ${message.data}');
      _showLocalNotification(message);
      
      // ✅ [修复：新消息不刷新] 收到前台消息时刷新通知列表
      try {
        debugPrint('🔄 [Foreground] 尝试刷新通知列表...');
        await NotificationService.refresh(limit: 100, includeRead: true);
        debugPrint('✅ [Foreground] 通知列表刷新成功');
      } catch (e) {
        debugPrint('⚠️ [Foreground] 刷新通知列表失败（可能用户未登录）: $e');
      }
    });

    _fcmInitialized = true;
    debugPrint('✅ Firebase Messaging 初始化成功');
  } catch (e, stackTrace) {
    debugPrint('❌ Firebase Messaging 初始化失败: $e');
    debugPrint('📍 堆栈: $stackTrace');
    debugPrint('💡 App 将继续运行,但推送通知功能可能不可用');
  }
}

// ✅ [性能优化] 延迟初始化推送通知(首屏后执行)
void _initPushNotificationsLazy() {
  Future.delayed(const Duration(seconds: 1), () async {
    debugPrint('🔔 [Lazy] 开始延迟初始化推送通知...');

    try {
      await _initLocalNotifications();
      debugPrint('✅ [Lazy] 本地通知初始化成功');
    } catch (e) {
      debugPrint('❌ [Lazy] 本地通知初始化失败: $e');
    }

    try {
      await _initFirebaseMessaging();
      debugPrint('✅ [Lazy] Firebase Messaging 初始化成功');
    } catch (e) {
      debugPrint('❌ [Lazy] Firebase Messaging 初始化失败: $e');
    }
  });
}

Future<void> main() async {
  // ✅ 0. 调试日志：当前运行模式
  debugPrint('QA_MODE define = ${const bool.fromEnvironment("QA_MODE")}');
  debugPrint('kDebugMode = $kDebugMode');

  // ✅ [启动页调查] 记录启动开始时间
  final appStartTime = DateTime.now();
  debugPrint('[SplashDebug] 🚀 ==================== APP START ====================');
  debugPrint('[SplashDebug] 📱 Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  debugPrint('[SplashDebug] ⏱️  Start time: $appStartTime');

  // ✅ 1. 确保绑定初始化
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[SplashDebug] ✅ WidgetsFlutterBinding.ensureInitialized()');

  // ✅ 2. 保留启动图
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  debugPrint('[SplashDebug] 📸 FlutterNativeSplash.preserve() called');

  // ✅ 3. 错误处理
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[GlobalFlutterError] ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[GlobalUncaughtError] $error\n$stack');
    return true;
  };

  // ✅ 4. 并行初始化
  final startTime = DateTime.now();
  debugPrint('⏱️ [Startup] 开始初始化...');
  debugPrint('[SplashDebug] ⏱️ 并行初始化开始: $startTime');

  await Future.wait([
    // Firebase 初始化
    Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then((_) {
      debugPrint('✅ Firebase 初始化成功');
    }).catchError((e) {
      debugPrint('❌ Firebase 初始化失败: $e');
    }),

    // Supabase 初始化
    Supabase.initialize(
      url: 'https://rhckybselarzglkmlyqs.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
    ).then((_) {
      debugPrint('✅ Supabase 初始化成功');
    }).catchError((e) {
      debugPrint('❌ Supabase 初始化失败: $e');
    }),

    // 系统 UI 配置
    Future(() async {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: [
          SystemUiOverlay.top,
          SystemUiOverlay.bottom,
        ],
      );

      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,

        // ✅ 关键：让系统导航栏透明，由 Flutter 自己画底色
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,

        // ✅ 关键：Android 10+ 防止系统强制加深/加遮罩
        systemNavigationBarContrastEnforced: false,
      ));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      debugPrint('✅ 系统 UI 配置完成');
    }),
  ]);

  final initDuration = DateTime.now().difference(startTime).inMilliseconds;
  debugPrint('⏱️ [Startup] 核心初始化完成,耗时: ${initDuration}ms');

  // ✅ 5. 注册后台消息处理器
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('✅ Firebase 后台消息处理器注册成功');
  } catch (e) {
    debugPrint('⚠️ Firebase 后台消息处理器注册失败: $e');
  }

  // ✅ 6. OAuth 状态恢复
  await OAuthEntry.restoreState();
  debugPrint('✅ OAuth 状态恢复完成');

  // ✅ 7. 延迟初始化推送通知
  _initPushNotificationsLazy();

  debugPrint(
      '⏱️ [Startup] 总耗时: ${DateTime.now().difference(startTime).inMilliseconds}ms');
  debugPrint('🚀 [Startup] 启动应用...');

  // ✅ 8. 启动应用
  runApp(const SwaplyApp());
}
