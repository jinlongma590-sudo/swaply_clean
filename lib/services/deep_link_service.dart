// lib/services/deep_link_service.dart
// ✅ [热启动修复] 增加 Guard 保护，防止生命周期监听器干扰
// ✅ [iOS 优化] 区分冷热启动，热启动使用更长等待时间
// ✅ [架构简化] 移除复杂的标志延迟清除逻辑
// ✅ [协调优化] AuthFlowObserver 现在检查路由状态，不依赖标志时序
// ✅ [通知处理] 支持 Firebase 通知点击跳转 + 增强调试日志
// ✅ [Completer 机制] 确保 bootstrap() 等待初始链接处理完成
// ✅ [字段统一] 统一通知数据字段查找顺序
// ✅ [自动就绪] 自动调用 markAppReady() 处理队列中的通知
// ✅ [方案1+2] 提供 Completer 和状态查询接口，供 AuthFlowObserver 协调
// ✅ [iOS 修复] 增加等待时间，解决 iOS Universal Links 延迟传递问题
// 完全符合 Swaply 架构：
//    1. 只负责业务跳转，不碰鉴权流程
//    2. reset-password 使用 navReplaceAll（全局跳转）
//    3. 其他业务页面使用 navPush（业务跳转）
//    4. 提供协调标志和 Completer，供 AuthFlowObserver 等待

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:swaply/router/root_nav.dart';
import 'deep_link_navigation_guard.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  final List<Uri> _pending = [];
  static const int _maxPendingSize = 10;

  bool _bootstrapped = false;
  bool _flushing = false;
  bool _initialHandled = false;

  // ✅ [通知处理] 通知队列和就绪标志
  final List<String> _notificationQueue = [];
  bool _appReady = false;

  // ✅ [方案2] 标记是否已通过深链导航
  bool _hasNavigatedViaDeepLink = false;

  // ✅ [方案1] Completer 机制：等待初始链接处理完成
  Completer<void>? _initialLinkCompleter;

  // ✅ [热启动修复] Guard 实例
  final _guard = DeepLinkNavigationGuard();

  // ✅ [热启动检测] 标记当前是否是热启动场景
  bool _isHotStart = false;

  // ============================================================
  // ✅ Public Getters（供 AuthFlowObserver 和生命周期监听器查询）
  // ============================================================

  /// 是否正在处理初始深链（Completer 未完成）
  bool get isHandlingInitialLink =>
      _initialLinkCompleter != null && !_initialLinkCompleter!.isCompleted;

  /// 是否已通过深链成功导航到业务页面
  bool get hasNavigatedViaDeepLink => _hasNavigatedViaDeepLink;

  /// 获取 Completer 的 Future（供 AuthFlowObserver 等待）
  Future<void>? get initialLinkFuture => _initialLinkCompleter?.future;

  /// ✅ [热启动修复] 静态方法：供生命周期监听器检查
  static bool get isHandlingDeepLink =>
      DeepLinkNavigationGuard().isHandlingDeepLink;

  static bool get wasRecentDeepLink =>
      DeepLinkNavigationGuard().wasRecentDeepLink;

  /// ✅ [通知处理] 在 MainNavigationPage 首帧稳定后调用
  void markAppReady() {
    _appReady = true;
    _flushNotificationQueue();
    if (kDebugMode) {
      debugPrint('[DeepLink] ✅ App ready, flushing notification queue');
    }
  }

  /// ✅ [公共接口] 处理本地通知点击
  /// 用于 main.dart 中的本地通知点击处理
  /// 这个方法会启动 Guard 保护，确保不被 AuthFlowObserver 覆盖
  void handle(String link) {
    if (link.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DeepLink] ⚠️ Empty link, ignoring');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║   [DeepLink] 📱 Handle Local Notification Click           ║');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      debugPrint('🔗 Link: $link');
    }

    try {
      final uri = Uri.parse(link);

      if (kDebugMode) {
        debugPrint('🔍 Parsed URI:');
        debugPrint('   Scheme: ${uri.scheme}');
        debugPrint('   Host: ${uri.host}');
        debugPrint('   Path: ${uri.path}');
        debugPrint('   Query: ${uri.queryParameters}');
      }

      // ✅ [关键] 检测是否是热启动
      // 如果 _bootstrapped = true，说明 App 已经完成初始化，这是热启动
      final isHotStart = _bootstrapped;

      if (kDebugMode) {
        debugPrint('🔥 Hot Start: $isHotStart (bootstrapped: $_bootstrapped)');
      }

      // ✅ 设置热启动标志
      _isHotStart = isHotStart;

      // ✅ 使用 postFrameCallback 确保在渲染后处理
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (kDebugMode) {
          debugPrint('📍 Post-frame: Processing link...');
        }

        // ✅ 调用内部处理方法
        _handle(uri, isFromNotification: true);

        // ✅ 立即刷新队列
        flushQueue();

        if (kDebugMode) {
          debugPrint('✅ Link queued for processing');
          debugPrint('════════════════════════════════════════════════════════════');
          debugPrint('');
        }
      });

    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ Failed to parse link: $e');
        debugPrint('Stack trace: $st');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
    }
  }

  /// 解析 URL fragment（形如 #a=1&b=2）为 Map
  Map<String, String> _parseFragmentParams(String fragment) {
    final m = <String, String>{};
    if (fragment.isEmpty) return m;
    for (final kv in fragment.split('&')) {
      if (kv.isEmpty) continue;
      final i = kv.indexOf('=');
      if (i == -1) {
        m[Uri.decodeComponent(kv)] = '';
      } else {
        final k = Uri.decodeComponent(kv.substring(0, i));
        final v = Uri.decodeComponent(kv.substring(i + 1));
        m[k] = v;
      }
    }
    return m;
  }

  /// 导航就绪检测
  bool _navReady() =>
      rootNavKey.currentState != null && rootNavKey.currentContext != null;

  /// 等待导航树与会话恢复
  Future<void> _waitUntilReady({Duration max = const Duration(seconds: 2)}) async {
    final started = DateTime.now();
    while (!_navReady() && DateTime.now().difference(started) < max) {
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  /// ✅ 初始化：bootstrap() 返回时，初始链接已处理完成
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    // 前台深链
    _appLinks.uriLinkStream.listen((uri) {
      if (kDebugMode) debugPrint('[DeepLink] 🔗 uriLinkStream -> $uri');

      // ✅ [热启动检测] 前台链接标记为热启动
      _isHotStart = true;

      _handle(uri);
    }, onError: (err) {
      if (kDebugMode) debugPrint('[DeepLink] ❌ stream error: $err');
    });

    // 冷启动深链
    try {
      final initial = await _appLinks.getInitialLink();

      if (initial != null && !_initialHandled) {
        _initialHandled = true;

        // ✅ 冷启动标记
        _isHotStart = false;

        // ✅ [方案1] 创建 Completer，等待处理完成
        _initialLinkCompleter = Completer<void>();

        if (kDebugMode) {
          debugPrint('[DeepLink] 🚀 getInitialLink -> $initial');
          debugPrint('[DeepLink] 🚦 Creating Completer, will wait for completion');
        }

        await SchedulerBinding.instance.endOfFrame;

        // ✅ [iOS 关键修复] iOS 需要更长的等待时间
        // Universal Links 从系统传递到 Flutter 需要 200-800ms（不稳定！）
        // Android 的 App Links 传递更快（20-50ms）
        final waitTime = Platform.isIOS
            ? const Duration(milliseconds: 800)  // iOS: 800ms ← 修复竞态条件
            : const Duration(milliseconds: 50);   // Android: 50ms

        if (kDebugMode) {
          debugPrint('[DeepLink] ⏳ Waiting ${waitTime.inMilliseconds}ms for deep link propagation (${Platform.isIOS ? "iOS" : "Android"})...');
        }

        await Future.delayed(waitTime);

        _handle(initial, isInitial: true);

        // ✅ [方案1] 等待初始链接处理完成（带超时保护）
        try {
          await _initialLinkCompleter!.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              if (kDebugMode) {
                debugPrint('[DeepLink] ⚠️ Timeout waiting for initial link completion');
              }
              _completeInitialLink();
            },
          );

          if (kDebugMode) {
            debugPrint('[DeepLink] ✅ Initial link handling completed successfully');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[DeepLink] ❌ Error waiting for initial link: $e');
          }
          _completeInitialLink();
        }
      } else {
        if (kDebugMode) {
          debugPrint('[DeepLink] ℹ️ No initial link');
        }

        // ✅ 即使没有初始链接，也要创建并完成 Completer
        // 这样 AuthFlowObserver 不会无限等待
        _initialLinkCompleter = Completer<void>();
        _initialLinkCompleter!.complete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] ❌ initial link error: $e');
      _completeInitialLink();
    }

    // ✅ 设置通知处理器
    _setupNotificationHandlers();
  }

  /// ✅ [通知处理] 设置 Firebase 通知处理器
  void _setupNotificationHandlers() {
    // 冷启动：点击通知启动应用
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotification(message, source: 'initial');
      }
    });

    // 后台 → 前台：点击通知
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotification(message, source: 'opened');
    });

    if (kDebugMode) {
      debugPrint('[DeepLink] 🔔 Notification handlers registered');
    }

    // ✅ [关键修复] 在 handlers 注册完成后，自动标记 app 为 ready
    // 这样可以确保队列中的通知消息会被处理
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 延迟 800ms，确保 AuthFlowObserver 导航完成
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!_appReady) {
          if (kDebugMode) {
            debugPrint('[DeepLink] ✅ Auto-marking app as ready');
            debugPrint('[DeepLink] 📊 Pending notification queue size: ${_notificationQueue.length}');
          }
          markAppReady();
        }
      });
    });
  }

  /// ✅ [通知处理] 处理通知点击（增强调试版）
  /// ✅ [热启动修复] 正确检测和设置热启动状态
  void _handleNotification(RemoteMessage message, {required String source}) {
    // ✅ [热启动修复] 根据 source 检测是否是热启动
    // 'initial' = 冷启动（App 被通知启动）
    // 'opened' = 热启动（App 在后台，点击通知恢复）
    final isNotificationHotStart = source == 'opened';

    if (kDebugMode) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║   [DeepLink] 🔔 NOTIFICATION RECEIVED                      ║');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      debugPrint('📍 Source: $source');
      debugPrint('🔥 Hot Start: $isNotificationHotStart');
      debugPrint('📋 Message ID: ${message.messageId}');
      debugPrint('🕒 Sent time: ${message.sentTime}');
      debugPrint('');
      debugPrint('─────────────────────────────────────────────────────────────');
      debugPrint('📦 FCM Data (Full Map):');
      debugPrint('─────────────────────────────────────────────────────────────');

      if (message.data.isEmpty) {
        debugPrint('   ⚠️  Data is EMPTY!');
      } else {
        debugPrint('   Total fields: ${message.data.length}');
        debugPrint('   Keys: ${message.data.keys.toList()}');
        debugPrint('');
        message.data.forEach((key, value) {
          debugPrint('   [$key] = "$value"');
        });
      }

      debugPrint('');
      debugPrint('─────────────────────────────────────────────────────────────');
      debugPrint('🔍 Checking for deep link fields:');
      debugPrint('─────────────────────────────────────────────────────────────');
    }

    // ✅ [关键修复] 统一字段查找顺序，覆盖所有可能的字段名
    String? link;
    String? foundIn;

    // 按优先级检查所有可能的字段
    if (message.data.containsKey('payload')) {
      link = message.data['payload'];
      foundIn = 'payload';
    } else if (message.data.containsKey('deep_link')) {
      link = message.data['deep_link'];
      foundIn = 'deep_link';
    } else if (message.data.containsKey('link')) {
      link = message.data['link'];
      foundIn = 'link';
    } else if (message.data.containsKey('deeplink')) {
      link = message.data['deeplink'];
      foundIn = 'deeplink';
    }

    if (kDebugMode) {
      debugPrint('   [payload]   : ${message.data['payload'] ?? "NULL"}');
      debugPrint('   [deep_link] : ${message.data['deep_link'] ?? "NULL"}');
      debugPrint('   [link]      : ${message.data['link'] ?? "NULL"}');
      debugPrint('   [deeplink]  : ${message.data['deeplink'] ?? "NULL"}');
      debugPrint('');

      if (foundIn != null) {
        debugPrint('✅ Found link in field: "$foundIn"');
        debugPrint('✅ Link value: "$link"');
      } else {
        debugPrint('❌ No link field found in any of the expected fields!');
      }

      debugPrint('');
      debugPrint('─────────────────────────────────────────────────────────────');
      debugPrint('📱 Other notification fields:');
      debugPrint('─────────────────────────────────────────────────────────────');
      debugPrint('   [type]            : ${message.data['type'] ?? "NULL"}');
      debugPrint('   [offer_id]        : ${message.data['offer_id'] ?? "NULL"}');
      debugPrint('   [listing_id]      : ${message.data['listing_id'] ?? "NULL"}');
      debugPrint('   [notification_id] : ${message.data['notification_id'] ?? "NULL"}');
      debugPrint('   [click_action]    : ${message.data['click_action'] ?? "NULL"}');
      debugPrint('');

      if (message.notification != null) {
        debugPrint('─────────────────────────────────────────────────────────────');
        debugPrint('🔔 Notification object:');
        debugPrint('─────────────────────────────────────────────────────────────');
        debugPrint('   Title: ${message.notification?.title ?? "NULL"}');
        debugPrint('   Body: ${message.notification?.body ?? "NULL"}');
        debugPrint('');
      }
    }

    // ✅ 验证链接有效性
    if (link == null || link.isEmpty) {
      if (kDebugMode) {
        debugPrint('╔════════════════════════════════════════════════════════════╗');
        debugPrint('║   ❌ ERROR: No valid deep link found!                     ║');
        debugPrint('╚════════════════════════════════════════════════════════════╝');
        debugPrint('');
        debugPrint('⚠️  Notification has no deep link data!');
        debugPrint('⚠️  Available data fields: ${message.data.keys.toList()}');
        debugPrint('⚠️  Expected one of: payload, deep_link, link, deeplink');
        debugPrint('');
        debugPrint('📝 Troubleshooting:');
        debugPrint('   1. Check Edge Function buildFcmBody() function');
        debugPrint('   2. Verify "payload" field is included in FCM data');
        debugPrint('   3. Check Edge Function logs for buildDeepLinkPayload()');
        debugPrint('   4. Ensure notification record has offer_id/listing_id');
        debugPrint('');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║   ✅ Valid deep link found - Processing...                ║');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      debugPrint('🔗 Deep Link: $link');
      debugPrint('📍 Source field: $foundIn');
      debugPrint('⏳ App ready status: $_appReady');
      debugPrint('');
    }

    // ✅ 检查 App 是否就绪
    if (!_appReady) {
      _notificationQueue.add(link);
      if (kDebugMode) {
        debugPrint('⏸️  App not ready yet, queuing notification...');
        debugPrint('📥 Added to queue: $link');
        debugPrint('📊 Current queue size: ${_notificationQueue.length}');
        debugPrint('');
        debugPrint('ℹ️  Link will be processed after markAppReady() is called');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('🚀 App is ready, processing immediately...');
      debugPrint('🔥 Hot Start: $isNotificationHotStart');
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('');
    }

    _processNotificationLink(link, isHotStart: isNotificationHotStart);
  }

  /// ✅ [通知处理] 处理通知链接
  /// ✅ [热启动修复] 传递热启动状态
  void _processNotificationLink(String link, {bool isHotStart = false}) {
    try {
      final uri = Uri.parse(link);

      if (kDebugMode) {
        debugPrint('');
        debugPrint('╔════════════════════════════════════════════════════════════╗');
        debugPrint('║   [DeepLink] 🔗 Processing Notification Link              ║');
        debugPrint('╚════════════════════════════════════════════════════════════╝');
        debugPrint('');
        debugPrint('📝 Raw link: $link');
        debugPrint('🔥 Hot Start: $isHotStart');
        debugPrint('🔍 Parsed URI:');
        debugPrint('   Scheme: ${uri.scheme}');
        debugPrint('   Host: ${uri.host}');
        debugPrint('   Path: ${uri.path}');
        debugPrint('   Query: ${uri.query}');
        debugPrint('   Query params: ${uri.queryParameters}');
        debugPrint('');
      }

      // ✅ [热启动修复] 设置全局热启动标志
      _isHotStart = isHotStart;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (kDebugMode) {
          debugPrint('📍 Post-frame callback: Handling deep link...');
          debugPrint('🔥 _isHotStart set to: $_isHotStart');
        }
        _handle(uri, isFromNotification: true);
        flushQueue();

        if (kDebugMode) {
          debugPrint('✅ Notification link processing completed');
          debugPrint('════════════════════════════════════════════════════════════');
          debugPrint('');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('');
        debugPrint('╔════════════════════════════════════════════════════════════╗');
        debugPrint('║   ❌ ERROR: Failed to process notification link          ║');
        debugPrint('╚════════════════════════════════════════════════════════════╝');
        debugPrint('');
        debugPrint('🔴 Error: $e');
        debugPrint('📝 Link that failed: $link');
        debugPrint('');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
    }
  }

  /// ✅ [通知处理] 刷新通知队列
  void _flushNotificationQueue() {
    if (_notificationQueue.isEmpty) return;

    if (kDebugMode) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║   [DeepLink] 🚀 Flushing Notification Queue               ║');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      debugPrint('📊 Queue size: ${_notificationQueue.length}');
      debugPrint('');
    }

    final link = _notificationQueue.removeAt(0);

    if (kDebugMode) {
      debugPrint('🔗 Processing queued link: $link');
      debugPrint('❄️  Queue flushing: Treating as cold start (isHotStart=false)');
    }

    // ✅ [热启动修复] 队列中的通知视为冷启动
    // 原因：通知被加入队列说明 App 刚启动，_appReady 还是 false
    _processNotificationLink(link, isHotStart: false);

    if (_notificationQueue.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('⏳ Scheduling next item (${_notificationQueue.length} remaining)...');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }

      Future.delayed(const Duration(milliseconds: 300), () {
        _flushNotificationQueue();
      });
    } else {
      if (kDebugMode) {
        debugPrint('✅ Queue is now empty');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
    }
  }

  /// 所有深链 handler 统一入口
  void _handle(Uri uri, {bool isInitial = false, bool isFromNotification = false}) {
    if (_pending.length >= _maxPendingSize) {
      debugPrint('[DeepLink] ⚠️ pending queue full, dropping oldest');
      _pending.removeAt(0);
    }
    _pending.add(uri);

    if (isFromNotification && kDebugMode) {
      debugPrint('[DeepLink] 🔔 Added notification link to queue: $uri');
    }

    flushQueue();
  }

  /// 刷新队列
  void flushQueue() {
    if (_flushing) return;
    _flushing = true;

    Future.microtask(() async {
      try {
        await _waitUntilReady();
        final items = List<Uri>.from(_pending);
        _pending.clear();
        for (final u in items) {
          await _route(u);
        }
      } finally {
        _flushing = false;
      }
    });
  }

  // ============================================================
  // 深链路由解析（完全符合 Swaply 架构）
  // ============================================================
  Future<void> _route(Uri uri) async {
    final scheme = (uri.scheme).toLowerCase();
    final host = (uri.host).toLowerCase();
    final path = (uri.path).toLowerCase();

    if (kDebugMode) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║   [DeepLink] 🎯 Routing Deep Link                         ║');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      debugPrint('📝 Full URI: $uri');
      debugPrint('🔍 Components:');
      debugPrint('   Scheme: $scheme');
      debugPrint('   Host: $host');
      debugPrint('   Path: $path');
      debugPrint('   Query: ${uri.queryParameters}');
      debugPrint('   Hot Start: $_isHotStart');
      debugPrint('');
    }

    try {
      // ============================================================
      // ✅ 忽略 Supabase OAuth 回调
      // ============================================================
      if (scheme == 'cc.swaply.app' && host == 'login-callback') {
        if (kDebugMode) {
          debugPrint('⏭️  Skipping Supabase login callback');
          debugPrint('════════════════════════════════════════════════════════════');
          debugPrint('');
        }
        _completeInitialLink();
        return;
      }

      // ============================================================
      // 1) Reset Password 深链
      // ✅ 全局跳转，使用 navReplaceAll
      // ============================================================
      final isResetByHost = host == 'reset-password';
      final isResetByPath = path.contains('reset-password');

      if (isResetByHost || isResetByPath) {
        if (kDebugMode) {
          debugPrint('🔐 Matched: Reset Password Link');
          debugPrint('');
        }

        final qp = uri.queryParameters;
        final fp = _parseFragmentParams(uri.fragment);

        final err = qp['error'] ?? fp['error'];
        final errCode = qp['error_code'] ?? fp['error_code'];
        final errDesc = qp['error_description'] ?? fp['error_description'];

        if (kDebugMode) {
          debugPrint('🔍 Query params: $qp');
          debugPrint('🔍 Fragment params: $fp');
        }

        String? code = qp['code'];
        if (code == null || code.isEmpty) code = fp['code'];

        String? token = qp['token'];
        if (token == null || token.isEmpty) token = fp['token'];

        String? accessToken = qp['access_token'];
        if (accessToken == null || accessToken.isEmpty) accessToken = fp['access_token'];

        String? refreshToken = qp['refresh_token'];
        if (refreshToken == null || refreshToken.isEmpty) {
          refreshToken = fp['refresh_token'];
        }

        final type = qp['type'] ?? fp['type'];

        if (kDebugMode) {
          debugPrint('🔑 Extracted parameters:');
          debugPrint('   code=${code != null && code.isNotEmpty ? "***${code.substring(code.length > 10 ? code.length - 10 : 0)}" : "NULL"}');
          debugPrint('   token=${token != null && token.isNotEmpty ? "***${token.substring(token.length > 10 ? token.length - 10 : 0)}" : "NULL"}');
          debugPrint('   access_token=${accessToken != null && accessToken.isNotEmpty ? "***${accessToken.substring(accessToken.length > 10 ? accessToken.length - 10 : 0)}" : "NULL"}');
          debugPrint('   type=$type');
        }

        final args = <String, dynamic>{};

        if (code != null && code.isNotEmpty) {
          args['code'] = code;
        }
        if (token != null && token.isNotEmpty) {
          args['token'] = token;
        }
        if (accessToken != null && accessToken.isNotEmpty) {
          args['access_token'] = accessToken;
        }
        if (refreshToken != null && refreshToken.isNotEmpty) {
          args['refresh_token'] = refreshToken;
        }
        if (type != null) {
          args['type'] = type;
        }

        if (err != null && err.isNotEmpty) {
          args['error'] = err;
        }
        if (errCode != null && errCode.isNotEmpty) {
          args['error_code'] = errCode;
        }
        if (errDesc != null && errDesc.isNotEmpty) {
          args['error_description'] = errDesc;
        }

        if (kDebugMode) {
          debugPrint('📦 Arguments for ResetPasswordPage: ${args.keys.toList()}');
          debugPrint('🚀 Navigating to: /reset-password');
          debugPrint('');
        }

        await SchedulerBinding.instance.endOfFrame;
        navReplaceAll('/reset-password', arguments: args);

        if (kDebugMode) {
          debugPrint('✅ Navigation completed');
          debugPrint('════════════════════════════════════════════════════════════');
          debugPrint('');
        }

        // Reset password 不算业务深链导航
        _completeInitialLink();
        return;
      }

      // ============================================================
      // ✅ [热启动修复] 开始处理业务深链，启动 Guard 保护
      // ============================================================
      if (kDebugMode) {
        debugPrint('🚦 Business deep link handling: STARTED');
        debugPrint('');
      }

      // ============================================================
      // 2) Offer 深链
      // ✅ 业务跳转，使用 navPush
      // ============================================================
      final isOfferByHost = host == 'offer';
      final isOfferByPath = path.contains('/offer');
      if (isOfferByHost || isOfferByPath) {
        final offerId = uri.queryParameters['offer_id'] ?? uri.queryParameters['id'];
        final listingId = uri.queryParameters['listing_id'] ??
            uri.queryParameters['listingid'] ??
            uri.queryParameters['listing'];

        if (offerId != null && offerId.isNotEmpty) {
          // ✅ [热启动修复] 启动 Guard 保护
          _guard.startHandling('/offer-detail', arguments: {
            'offer_id': offerId,
            if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
          });

          if (kDebugMode) {
            debugPrint('💼 Matched: Offer Link');
            debugPrint('   offer_id: $offerId');
            debugPrint('   listing_id: ${listingId ?? "NULL"}');
            debugPrint('🔒 Guard 保护已启动');
          }

          // ✅ [iOS 热启动修复] 区分冷热启动的等待时间
          Duration waitTime;
          if (Platform.isIOS) {
            waitTime = _isHotStart
                ? const Duration(milliseconds: 1500)  // iOS 热启动：1500ms
                : const Duration(milliseconds: 800);   // iOS 冷启动：800ms
          } else {
            waitTime = const Duration(milliseconds: 50);  // Android：50ms
          }

          if (kDebugMode) {
            debugPrint('⏳ 等待 ${waitTime.inMilliseconds}ms (${_isHotStart ? "热启动" : "冷启动"})...');
          }

          await Future.delayed(waitTime);

          if (kDebugMode) {
            debugPrint('🚀 Navigating to: /offer-detail');
            debugPrint('');
          }

          await SchedulerBinding.instance.endOfFrame;
          navPush('/offer-detail', arguments: {
            'offer_id': offerId,
            if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
          });

          // ✅ 延长保护时间
          await Future.delayed(Duration(milliseconds: Platform.isIOS ? 1000 : 300));

          // ✅ [方案2] 标记已成功导航
          _hasNavigatedViaDeepLink = true;

          // ✅ [热启动修复] 释放 Guard 保护
          _guard.finishHandling();

          if (kDebugMode) {
            debugPrint('✅ Navigation completed');
            debugPrint('🔓 Guard 保护已释放');
            debugPrint('════════════════════════════════════════════════════════════');
            debugPrint('');
          }

          _completeInitialLink();
          return;
        }
      }

      // ============================================================
      // 3) 短链格式：/l/[id] → 商品详情页
      // ✅ 业务跳转，使用 navPush
      // ============================================================
      final isShortLinkPath = path.startsWith('/l/');
      if (isShortLinkPath) {
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length >= 2 && segments[0] == 'l') {
          final listingId = segments[1];
          if (listingId.isNotEmpty) {
            // ✅ [热启动修复] 启动 Guard 保护
            _guard.startHandling('/listing', arguments: {'id': listingId});

            if (kDebugMode) {
              debugPrint('🔗 Matched: Short Link (/l/...)');
              debugPrint('   listing_id: $listingId');
              debugPrint('🔒 Guard 保护已启动');
            }

            // ✅ [iOS 热启动修复] 区分冷热启动的等待时间
            Duration waitTime;
            if (Platform.isIOS) {
              waitTime = _isHotStart
                  ? const Duration(milliseconds: 1500)  // iOS 热启动：1500ms
                  : const Duration(milliseconds: 800);   // iOS 冷启动：800ms
            } else {
              waitTime = const Duration(milliseconds: 50);  // Android：50ms
            }

            if (kDebugMode) {
              debugPrint('⏳ 等待 ${waitTime.inMilliseconds}ms (${_isHotStart ? "热启动" : "冷启动"})...');
            }

            await Future.delayed(waitTime);

            if (kDebugMode) {
              debugPrint('🚀 Navigating to: /listing');
              debugPrint('');
            }

            await SchedulerBinding.instance.endOfFrame;
            navPush('/listing', arguments: {'id': listingId});

            // ✅ 延长保护时间
            await Future.delayed(Duration(milliseconds: Platform.isIOS ? 1000 : 300));

            // ✅ [方案2] 标记已成功导航
            _hasNavigatedViaDeepLink = true;

            // ✅ [热启动修复] 释放 Guard 保护
            _guard.finishHandling();

            if (kDebugMode) {
              debugPrint('✅ Navigation completed');
              debugPrint('🔓 Guard 保护已释放');
              debugPrint('════════════════════════════════════════════════════════════');
              debugPrint('');
            }

            _completeInitialLink();
            return;
          }
        }
      }

      // ============================================================
      // 4) Listing 深链
      // ✅ 业务跳转，使用 navPush
      // ============================================================
      final isListingByHost = host == 'listing';
      final isListingByPath = path.contains('/listing');
      if (isListingByHost || isListingByPath) {
        final listingId = uri.queryParameters['listing_id'] ?? uri.queryParameters['id'];
        if (listingId != null && listingId.isNotEmpty) {
          // ✅ [热启动修复] 启动 Guard 保护
          _guard.startHandling('/listing', arguments: {'id': listingId});

          if (kDebugMode) {
            debugPrint('📦 Matched: Listing Link');
            debugPrint('   listing_id: $listingId');
            debugPrint('🔒 Guard 保护已启动');
          }

          // ✅ [iOS 热启动修复] 区分冷热启动的等待时间
          Duration waitTime;
          if (Platform.isIOS) {
            waitTime = _isHotStart
                ? const Duration(milliseconds: 1500)  // iOS 热启动：1500ms
                : const Duration(milliseconds: 800);   // iOS 冷启动：800ms
          } else {
            waitTime = const Duration(milliseconds: 50);  // Android：50ms
          }

          if (kDebugMode) {
            debugPrint('⏳ 等待 ${waitTime.inMilliseconds}ms (${_isHotStart ? "热启动" : "冷启动"})...');
          }

          await Future.delayed(waitTime);

          if (kDebugMode) {
            debugPrint('🚀 Navigating to: /listing');
            debugPrint('');
          }

          await SchedulerBinding.instance.endOfFrame;
          navPush('/listing', arguments: {'id': listingId});

          // ✅ 延长保护时间
          await Future.delayed(Duration(milliseconds: Platform.isIOS ? 1000 : 300));

          // ✅ [方案2] 标记已成功导航
          _hasNavigatedViaDeepLink = true;

          // ✅ [热启动修复] 释放 Guard 保护
          _guard.finishHandling();

          if (kDebugMode) {
            debugPrint('✅ Navigation completed');
            debugPrint('🔓 Guard 保护已释放');
            debugPrint('════════════════════════════════════════════════════════════');
            debugPrint('');
          }

          _completeInitialLink();
          return;
        }
      }

      // ============================================================
      // 5) 默认：不匹配的链接
      // ============================================================
      if (kDebugMode) {
        debugPrint('❓ No matching route found');
        debugPrint('⏭️  Ignoring link: $uri');
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('');
      }
      _completeInitialLink();

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Route error: $e');
      }
      _guard.finishHandling();  // 确保异常时也释放 Guard
      _completeInitialLink();
    } finally {
      if (kDebugMode) {
        debugPrint('🚦 Business deep link handling: COMPLETED');
      }
    }
  }

  /// ✅ [方案1] 完成初始链接处理
  void _completeInitialLink() {
    if (_initialLinkCompleter != null && !_initialLinkCompleter!.isCompleted) {
      _initialLinkCompleter!.complete();

      if (kDebugMode) {
        debugPrint('[DeepLink] ✅ Initial link Completer completed');
      }
    }
  }
}
