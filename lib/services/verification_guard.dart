// lib/services/verification_guard.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/root_nav.dart'; // ✅ 使用统一导航
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;
import 'package:swaply/pages/verification_page.dart';

/// Features to protect with verification
enum AppFeature {
  postListing,
  makeOffer,
  sendMessage,
  callSeller,
  openWhatsapp,
}

class VerificationGuard {
  VerificationGuard._();

  // ===== 全局认证变化广播 =====
  static final StreamController<bool> _verifiedCtrl =
  StreamController<bool>.broadcast();
  static Stream<bool> get stream => _verifiedCtrl.stream;

  static void notifyVerifiedChanged([bool ok = true]) {
    try {
      _verifiedCtrl.add(ok);
    } catch (_) {}
  }

  static final _sb = Supabase.instance.client;
  static final EmailVerificationService _verifySvc =
  EmailVerificationService();

  static bool _isPrompting = false;

  // tiny cache to reduce DB reads (per-user, 30s)
  static DateTime? _cachedAt;
  static String? _cachedUserId;
  static bool? _cachedOk;

  static bool _isLoggedIn() => _sb.auth.currentUser != null;

  static Future<bool> _fetchAndCompute() async {
    final user = _sb.auth.currentUser;
    if (user == null) return false;

    final row = await _verifySvc.fetchVerificationRow();
    final ok = vutils.computeIsVerified(verificationRow: row, user: user);

    if (kDebugMode) {
      print('[VerificationGuard] row=$row -> verified=$ok');
    }
    return ok;
  }

  static Future<bool> isVerified() async {
    final u = _sb.auth.currentUser;
    if (u == null) return false;

    final cacheValid = _cachedAt != null &&
        _cachedOk != null &&
        _cachedUserId == u.id &&
        DateTime.now().difference(_cachedAt!).inSeconds < 30;

    if (cacheValid) {
      if (kDebugMode) print('[VerificationGuard] cache hit -> ${_cachedOk!}');
      return _cachedOk!;
    }

    final ok = await _fetchAndCompute();
    _cachedAt = DateTime.now();
    _cachedUserId = u.id;
    _cachedOk = ok;
    return ok;
  }

  static void invalidateCache() {
    _cachedAt = null;
    _cachedOk = null;
    _cachedUserId = null;
  }

  static bool _isZh(BuildContext context) {
    try {
      final code =
      Localizations.localeOf(context).languageCode.toLowerCase();
      return code.startsWith('zh');
    } catch (_) {
      return false;
    }
  }

  static String _t(BuildContext context, String en, String zh) {
    return _isZh(context) ? zh : en;
  }

  static String _featureName(Object? f) {
    if (f is AppFeature) {
      switch (f) {
        case AppFeature.postListing:
          return 'post a listing';
        case AppFeature.makeOffer:
          return 'make an offer';
        case AppFeature.sendMessage:
          return 'send messages';
        case AppFeature.callSeller:
          return 'call the seller';
        case AppFeature.openWhatsapp:
          return 'contact the seller via WhatsApp';
      }
    }
    if (f is String) {
      final s = f.trim();
      final l = s.toLowerCase();
      if (l.contains('offer')) return 'make an offer';
      if (l.contains('whats')) return 'contact the seller via WhatsApp';
      if (l.contains('call')) return 'call the seller';
      if (l.contains('messag')) return 'send messages';
      if (l.contains('post') || l.contains('advert')) return 'post a listing';
      return s;
    }
    return 'this action';
  }

  /// ✅ 符合架构：根据登录状态跳转不同页面
  static Future<bool> ensureVerifiedOrPrompt(
      BuildContext context, {
        Object? feature,
      }) async {
    final loggedIn = _isLoggedIn();
    final verified = await isVerified();

    if (loggedIn && verified) return true;

    if (_isPrompting) return false;
    _isPrompting = true;

    try {
      final actionName = _featureName(feature);

      final title = loggedIn
          ? _t(context, 'Complete verification first', '请先完成验证')
          : _t(context, 'Sign in & verify first', '请先登录并完成验证');

      final content = loggedIn
          ? _t(
        context,
        'For account security, please complete email verification before you can $actionName.',
        '为了账号安全，需要先完成邮箱验证后才能$actionName。',
      )
          : _t(
        context,
        'For account security, please sign in and complete email verification before you can $actionName.',
        '为了账号安全，需要先登录并完成邮箱验证后才能$actionName。',
      );

      final laterText = _t(context, 'Later', '稍后');
      final goText = loggedIn
          ? _t(context, 'Verify now', '去验证')
          : _t(context, 'Sign in & verify', '去登录/验证');

      await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            title: Text(title),
            content: Text(content),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(laterText),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop(false);
                  await Future.delayed(Duration.zero);

                  // ✅ 架构符合性修复：根据登录状态跳转不同页面
                  if (loggedIn) {
                    // 已登录但未验证 → 跳转到验证页面
                    if (kDebugMode) {
                      debugPrint(
                          '[VerificationGuard] ✅ User logged in, navigating to verification page');
                    }

                    final changed = await SafeNavigator.push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const VerificationPage(),
                        settings:
                        const RouteSettings(name: '/verification'),
                      ),
                    ) ??
                        false;

                    invalidateCache();
                    if (changed == true) {
                      notifyVerifiedChanged(true);
                      await isVerified();
                    }
                  } else {
                    // ✅ 未登录 → 使用 navReplaceAll 跳转到欢迎页面
                    // 让 AuthFlowObserver 接管后续流程
                    if (kDebugMode) {
                      debugPrint(
                          '[VerificationGuard] ✅ User not logged in, navigating to /welcome');
                    }

                    // ✅ 符合架构：使用 navReplaceAll，不直接操作 Navigator
                    await navReplaceAll('/welcome');
                  }
                },
                child: Text(goText),
              ),
            ],
          );
        },
      );

      return false;
    } finally {
      _isPrompting = false;
    }
  }
}