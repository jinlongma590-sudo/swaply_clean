// lib/services/deep_link_service.dart
// ✅ [iOS 竞态修复] 增加协调标志避免与 AuthFlowObserver 竞争
// 完全符合 Swaply 架构：
//    1. 只负责提取参数并传递，不做会话解析
//    2. reset-password 使用 navReplaceAll（全局跳转）
//    3. 不触碰任何 AuthFlowObserver 的职责
//    4. 提供协调标志，让 AuthFlowObserver 知道业务深链正在处理

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

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

  // ✅ [协调机制] 标志：是否正在处理业务深链（listing/offer）
  // 用于与 AuthFlowObserver 协调，避免导航冲突
  static bool _handlingBusinessDeepLink = false;

  // ✅ [协调机制] Public getter，供 AuthFlowObserver 查询
  static bool get isHandlingBusinessDeepLink => _handlingBusinessDeepLink;

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

  /// 初始化
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
        if (kDebugMode) {
          debugPrint('[DeepLink] 🚀 getInitialLink -> $initial (deferred)');
        }
        await SchedulerBinding.instance.endOfFrame;

        // ✅ [iOS 竞态修复] 减少延迟到 50ms
        // 目标：比 AuthFlowObserver.initialSession 更早执行
        // AuthFlowObserver 会检查我们的标志并等待
        await Future.delayed(const Duration(milliseconds: 50));

        _handle(initial, isInitial: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] ❌ initial link error: $e');
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
  void _handle(Uri uri, {bool isInitial = false}) {
    if (_pending.length >= _maxPendingSize) {
      debugPrint('[DeepLink] ⚠️ pending queue full, dropping oldest');
      _pending.removeAt(0);
    }
    _pending.add(uri);
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

    // ============================================================
    // ✅ 架构符合性：忽略 Supabase OAuth 回调
    // 让 Supabase SDK 和 AuthFlowObserver 处理
    // ============================================================
    if (scheme == 'cc.swaply.app' && host == 'login-callback') {
      if (kDebugMode) debugPrint('[DeepLink] ⏭️ skip supabase login-callback (let AuthFlowObserver handle)');
      return;
    }

    // ============================================================
    // 1) Reset Password 深链
    // ✅ 符合架构：只提取参数，不做验证，使用 navReplaceAll
    // ⚠️ 不设置协调标志，因为这是全局跳转，不需要协调
    // ============================================================
    final isResetByHost = host == 'reset-password';
    final isResetByPath = path.contains('reset-password');

    if (isResetByHost || isResetByPath) {
      if (kDebugMode) debugPrint('[DeepLink] 🔐 Processing reset-password link');

      final qp = uri.queryParameters;
      final fp = _parseFragmentParams(uri.fragment);

      // 提取错误参数
      final err = qp['error'] ?? fp['error'];
      final errCode = qp['error_code'] ?? fp['error_code'];
      final errDesc = qp['error_description'] ?? fp['error_description'];

      if (kDebugMode) {
        debugPrint('[DeepLink] 🔍 Query params: $qp');
        debugPrint('[DeepLink] 🔍 Fragment params: $fp');
      }

      // ✅ 提取所有可能的 token 参数
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

      // ✅ 构造参数 Map（只传递，不验证）
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

      // 传递错误信息
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

      // ✅ 架构符合：使用 navReplaceAll（reset-password 是全局跳转）
      Future.delayed(Duration.zero, () {
        navReplaceAll('/reset-password', arguments: args);
      });
      return;
    }

    // ============================================================
    // ✅ [协调机制] 开始处理业务深链，设置标志
    // 让 AuthFlowObserver 知道有业务深链正在处理
    // ============================================================
    _handlingBusinessDeepLink = true;
    if (kDebugMode) {
      debugPrint('[DeepLink] 🚦 Business deep link handling started (flag=true)');
    }

    try {
      // ============================================================
      // 2) Offer 深链
      // ✅ 架构符合：业务跳转使用 navPush
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
          Future.delayed(Duration.zero, () {
            navPush('/offer-detail', arguments: {
              'offer_id': offerId,
              if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
            });
          });

          // 等待导航完成
          await Future.delayed(const Duration(milliseconds: 150));
          return;
        }
      }

      // ============================================================
      // 3) 短链格式：/l/[id] → 商品详情页
      // ✅ 架构符合：业务跳转使用 navPush
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
            Future.delayed(Duration.zero, () {
              navPush('/listing', arguments: {'id': listingId});
            });

            // 等待导航完成
            await Future.delayed(const Duration(milliseconds: 150));
            return;
          }
        }
      }

      // ============================================================
      // 4) Listing 深链
      // ✅ 架构符合：业务跳转使用 navPush
      // ============================================================
      final isListingByHost = host == 'listing';
      final isListingByPath = path.contains('/listing');
      if (isListingByHost || isListingByPath) {
        final listingId = uri.queryParameters['listing_id'] ?? uri.queryParameters['id'];
        if (listingId != null && listingId.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[DeepLink] 📦 → ProductDetailPage: $listingId');
          }
          Future.delayed(Duration.zero, () {
            navPush('/listing', arguments: {'id': listingId});
          });

          // 等待导航完成
          await Future.delayed(const Duration(milliseconds: 150));
          return;
        }
      }

      // ============================================================
      // 5) 默认：不匹配的链接
      // ============================================================
      if (kDebugMode) debugPrint('[DeepLink] ❓ unmatched -> ignore: $uri');

    } finally {
      // ============================================================
      // ✅ [协调机制] 业务深链处理完成，清除标志
      // 延迟 200ms 清除，确保 AuthFlowObserver 能看到这个标志
      // ============================================================
      Future.delayed(const Duration(milliseconds: 200), () {
        _handlingBusinessDeepLink = false;
        if (kDebugMode) {
          debugPrint('[DeepLink] 🚦 Business deep link handling completed (flag=false)');
        }
      });
    }
  }
}