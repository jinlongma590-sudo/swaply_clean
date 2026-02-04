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

// ✅ 前台通知实例
final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

// ✅ [关键修复] 后台 isolate 需要自己的 FlutterLocalNotificationsPlugin 实例
FlutterLocalNotificationsPlugin? _backgroundLocalNotifications;

// ✅ [性能优化] 标记初始化状态,避免重复初始化
bool _fcmInitialized = false;

// ================================================
// ✅ [推送通知] Firebase 后台消息处理器(顶级函数)
// 必须在 main() 之外定义,这样 App 被清理后也能接收通知
// ================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 必须初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('🔔 [Background] 收到后台消息: ${message.notification?.title}');
  debugPrint('📦 [Background] Data: ${message.data}');

  // ✅ [关键修复] 初始化后台 isolate 的本地通知实例
  if (_backgroundLocalNotifications == null) {
    _backgroundLocalNotifications = FlutterLocalNotificationsPlugin();

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
    await _backgroundLocalNotifications!.initialize(
      initSettings,  // ✅ 位置参数，不是命名参数
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          debugPrint('🔔 [Background-Init] 点击通知: $payload');
          DeepLinkService.instance.handle(payload);
        }
      },
    );
    debugPrint('✅ [Background] 本地通知已初始化');
  }

  // 显示本地通知
  await _showBackgroundLocalNotification(message);
}

// ✅ [推送通知] 本地通知点击处理(后台)
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  final payload = details.payload;
  if (payload != null && payload.isNotEmpty) {
    debugPrint('🔔 [LocalNotification-Background] 点击本地通知: $payload');
    DeepLinkService.instance.handle(payload);
  }
}

// ✅ [关键修复] 后台专用的本地通知显示方法
Future<void> _showBackgroundLocalNotification(RemoteMessage message) async {
  if (_backgroundLocalNotifications == null) {
    debugPrint('❌ [Background] 本地通知实例未初始化');
    return;
  }

  final notification = message.notification;
  final data = message.data;

  final title = notification?.title ?? data['title'] ?? 'Notification';
  final body = notification?.body ?? data['body'] ?? '';

  final payload = data['payload'] ??
      data['deep_link'] ??
      data['link'] ??
      data['deeplink'] ??
      '';

  if (payload.isEmpty) {
    debugPrint('⚠️ [Background] 没有 payload,跳过通知');
    return;
  }

  final offerId = data['offer_id'] ?? '';
  final listingId = data['listing_id'] ?? '';

  debugPrint('🔗 [Background] Payload: $payload');
  debugPrint('📋 [Background] Offer: $offerId, Listing: $listingId');

  final notificationId = offerId.isNotEmpty
      ? offerId.hashCode.abs()
      : (listingId.isNotEmpty ? listingId.hashCode.abs() : message.hashCode.abs());

  final groupKey = offerId.isNotEmpty
      ? 'offer_$offerId'
      : (listingId.isNotEmpty ? 'listing_$listingId' : 'swaply_messages');

  final threadIdentifier = groupKey;

  debugPrint('🔔 [Background] ID: $notificationId, Group: $groupKey');

  final androidDetails = AndroidNotificationDetails(
    'swaply_notifications',
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

  try {
    // ✅ 关键修复: 全部使用命名参数
    await _backgroundLocalNotifications!.show(
      notificationId,
      title,
      body,
      details,
      payload: payload,
    );
    debugPrint('✅ [Background] 通知已显示 (ID: $notificationId, Group: $groupKey)');
  } catch (e) {
    debugPrint('❌ [Background] 显示通知失败: $e');
  }
}

// ✅ [推送通知] 显示本地通知的通用方法(前台使用)
Future<void> _showLocalNotification(RemoteMessage message) async {
  final notification = message.notification;
  final data = message.data;

  if (notification == null) return;

  final payload = data['payload'] ??
      data['deep_link'] ??
      data['link'] ??
      data['deeplink'] ??
      '';

  final offerId = data['offer_id'] ?? '';
  final listingId = data['listing_id'] ?? '';

  final notificationId = offerId.isNotEmpty
      ? offerId.hashCode.abs()
      : (listingId.isNotEmpty ? listingId.hashCode.abs() : message.hashCode.abs());

  final groupKey = offerId.isNotEmpty
      ? 'offer_$offerId'
      : (listingId.isNotEmpty ? 'listing_$listingId' : 'swaply_messages');

  final threadIdentifier = groupKey;

  debugPrint('🔔 [Foreground] ID: $notificationId, Group: $groupKey');

  final androidDetails = AndroidNotificationDetails(
    'swaply_notifications',
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
    notification.title,
    notification.body,
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
    initSettings,  // ✅ 位置参数，不是命名参数
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        debugPrint('🔔 [LocalNotification-Foreground] 点击本地通知: $payload');
        DeepLinkService.instance.handle(payload);
      }
    },
  );

  // ✅ 检查 app 是否由本地通知启动
  final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
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
    'swaply_notifications',
    'Swaply Notifications',
    description: 'Notifications for offers, messages, and updates',
    importance: Importance.high,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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

    // 4. 前台消息处理
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 [Foreground] 收到消息: ${message.notification?.title}');
      _showLocalNotification(message);
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
  // ✅ 1. 确保绑定初始化
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ✅ 2. 保留启动图
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
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

  debugPrint('⏱️ [Startup] 总耗时: ${DateTime.now().difference(startTime).inMilliseconds}ms');
  debugPrint('🚀 [Startup] 启动应用...');

  // ✅ 8. 启动应用
  runApp(const SwaplyApp());
}
