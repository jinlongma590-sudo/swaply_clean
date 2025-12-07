// lib/services/deep_link_service.dart
// ✅ [架构简化] 移除复杂的标志延迟清除逻辑
// ✅ [协调优化] AuthFlowObserver 现在检查路由状态，不依赖标志时序
// ✅ [通知处理] 支持 Firebase 通知点击跳转
// ✅ [Completer 机制] 确保 bootstrap() 等待初始链接处理完成
// 完全符合 Swaply 架构：
//    1. 只负责业务跳转，不碰鉴权流程
//    2. reset-password 使用 navReplaceAll（全局跳转）
//    3. 其他业务页面使用 navPush（业务跳转）
//    4. 提供协调标志，但不再依赖复杂的时序控制

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:swaply/router/root_nav.dart';

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

  // ✅ [协调机制] 标志：是否正在处理业务深链
  static bool _handlingBusinessDeepLink = false;

  // ✅ [Completer 机制] 等待初始链接处理完成
  Completer<void>? _initialLinkCompleter;

  // ✅ Public getter，供 AuthFlowObserver 查询
  static bool get isHandlingBusinessDeepLink => _handlingBusinessDeepLink;

  /// ✅ [通知处理] 在 MainNavigationPage 首帧稳定后调用
  void markAppReady() {
    _appReady = true;
    _flushNotificationQueue();
    if (kDebugMode) {
      debugPrint('[DeepLink] ✅ App ready, flushing notification queue');
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
      _handle(uri);
    }, onError: (err) {
      if (kDebugMode) debugPrint('[DeepLink] ❌ stream error: $err');
    });

    // 冷启动深链
    try {
      final initial = await _appLinks.getInitialLink();

      if (initial != null && !_initialHandled) {
        _initialHandled = true;

        // ✅ 创建 Completer，等待处理完成
        _initialLinkCompleter = Completer<void>();

        if (kDebugMode) {
          debugPrint('[DeepLink] 🚀 getInitialLink -> $initial');
          debugPrint('[DeepLink] 🚦 Creating Completer, will wait for completion');
        }

        await SchedulerBinding.instance.endOfFrame;

        // ✅ 减少延迟到 50ms（比 AuthFlowObserver 更早执行）
        await Future.delayed(const Duration(milliseconds: 50));

        _handle(initial, isInitial: true);

        // ✅ 等待初始链接处理完成（带超时保护）
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
  }

  /// ✅ [通知处理] 处理通知点击
  void _handleNotification(RemoteMessage message, {required String source}) {
    if (kDebugMode) {
      debugPrint('[DeepLink] 🔔 Notification clicked ($source)');
      debugPrint('[DeepLink] 📋 Data: ${message.data}');
    }

    final link = message.data['link'] ?? message.data['deeplink'];

    if (link == null || link.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DeepLink] ⚠️ Notification has no link, ignoring');
      }
      return;
    }

    if (!_appReady) {
      _notificationQueue.add(link);
      if (kDebugMode) {
        debugPrint('[DeepLink] 📥 App not ready, queued notification link: $link');
        debugPrint('[DeepLink] 📊 Queue size: ${_notificationQueue.length}');
      }
      return;
    }

    _processNotificationLink(link);
  }

  /// ✅ [通知处理] 处理通知链接
  void _processNotificationLink(String link) {
    try {
      final uri = Uri.parse(link);

      if (kDebugMode) {
        debugPrint('[DeepLink] 🔗 Processing notification link: $link');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handle(uri, isFromNotification: true);
        flushQueue();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeepLink] ❌ Failed to parse notification link: $e');
      }
    }
  }

  /// ✅ [通知处理] 刷新通知队列
  void _flushNotificationQueue() {
    if (_notificationQueue.isEmpty) return;

    if (kDebugMode) {
      debugPrint('[DeepLink] 🚀 Flushing ${_notificationQueue.length} queued notification(s)');
    }

    final link = _notificationQueue.removeAt(0);
    _processNotificationLink(link);

    if (_notificationQueue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _flushNotificationQueue();
      });
    }
  }

  /// 对外统一入口
  void handle(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final uri = Uri.parse(payload.trim());
      if (kDebugMode) debugPrint('[DeepLink] 📱 handle(payload) -> $uri');
      _handle(uri);
      flushQueue();
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] ❌ handle(payload) parse error: $e');
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
      debugPrint('[DeepLink] 🎯 route -> scheme=$scheme host=$host path=$path');
      debugPrint('[DeepLink] 📋 full URI: $uri');
    }

    try {
      // ============================================================
      // ✅ 忽略 Supabase OAuth 回调
      // ============================================================
      if (scheme == 'cc.swaply.app' && host == 'login-callback') {
        if (kDebugMode) debugPrint('[DeepLink] ⏭️ skip supabase login-callback');
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
        if (kDebugMode) debugPrint('[DeepLink] 🔐 Processing reset-password link');

        final qp = uri.queryParameters;
        final fp = _parseFragmentParams(uri.fragment);

        final err = qp['error'] ?? fp['error'];
        final errCode = qp['error_code'] ?? fp['error_code'];
        final errDesc = qp['error_description'] ?? fp['error_description'];

        if (kDebugMode) {
          debugPrint('[DeepLink] 🔍 Query params: $qp');
          debugPrint('[DeepLink] 🔍 Fragment params: $fp');
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
          debugPrint('[DeepLink] 🔑 Extracted parameters:');
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
          debugPrint('[DeepLink] 📦 Passing to ResetPasswordPage: ${args.keys.toList()}');
        }

        await SchedulerBinding.instance.endOfFrame;
        navReplaceAll('/reset-password', arguments: args);

        _completeInitialLink();
        return;
      }

      // ============================================================
      // ✅ [协调机制] 开始处理业务深链
      // ============================================================
      _handlingBusinessDeepLink = true;
      if (kDebugMode) {
        debugPrint('[DeepLink] 🚦 Business deep link handling started (flag=true)');
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
          if (kDebugMode) {
            debugPrint('[DeepLink] 💼 → OfferDetailPage: offer_id=$offerId');
          }

          await SchedulerBinding.instance.endOfFrame;
          navPush('/offer-detail', arguments: {
            'offer_id': offerId,
            if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
          });

          await Future.delayed(const Duration(milliseconds: 150));
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
            if (kDebugMode) {
              debugPrint('[DeepLink] 🔗 → ProductDetailPage (short link): $listingId');
            }

            await SchedulerBinding.instance.endOfFrame;
            navPush('/listing', arguments: {'id': listingId});

            await Future.delayed(const Duration(milliseconds: 150));
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
          if (kDebugMode) {
            debugPrint('[DeepLink] 📦 → ProductDetailPage: $listingId');
          }

          await SchedulerBinding.instance.endOfFrame;
          navPush('/listing', arguments: {'id': listingId});

          await Future.delayed(const Duration(milliseconds: 150));
          _completeInitialLink();
          return;
        }
      }

      // ============================================================
      // 5) 默认：不匹配的链接
      // ============================================================
      if (kDebugMode) debugPrint('[DeepLink] ❓ unmatched -> ignore: $uri');
      _completeInitialLink();

    } finally {
      // ============================================================
      // ✅ [架构简化] 立即清除标志
      // AuthFlowObserver 现在检查路由状态，不依赖标志时序
      // ============================================================
      _handlingBusinessDeepLink = false;

      if (kDebugMode) {
        debugPrint('[DeepLink] 🚦 Business deep link handling completed (flag=false)');
      }

      // ✅ 保险：确保 Completer 完成
      _completeInitialLink();
    }
  }

  /// ✅ 完成初始链接处理
  void _completeInitialLink() {
    if (_initialLinkCompleter != null && !_initialLinkCompleter!.isCompleted) {
      _initialLinkCompleter!.complete();

      if (kDebugMode) {
        debugPrint('[DeepLink] ✅ Initial link Completer completed');
      }
    }
  }
}