// lib/services/oauth_entry.dart
//
// ✅ [P0 修复] 增加 ValueNotifier 通知机制，解决按钮锁死问题
// ✅ [应用内认证] 三方登录统一调用 AuthService().signInWithNativeProvider(...)
// ✅ [系统浏览器] Facebook/Apple 使用 ASWebAuthenticationSession / Chrome Custom Tabs
// ✅ [回调 URL] 移动端使用自定义 URL Scheme，Web 端使用 HTTPS
//
// 建议用法：
// 1) 启动时：await OAuthEntry.restoreState(); // 恢复持久化状态
// 2) 触发：await OAuthEntry.signIn(OAuthProvider.facebook, ...);
// 3) 在回调命中时：OAuthEntry.finish();
// 4) 或在全局 onAuthStateChange 里：OAuthEntry.clearGuardIfSignedIn(state);
// 5) 页面 dispose 时：OAuthEntry.cancelIfInFlight();
// 6) 页面监听状态：ValueListenableBuilder(valueListenable: OAuthEntry.inFlightNotifier, ...)

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ 统一回调配置（移动端/Web 端分离）
import 'package:swaply/config/auth_config.dart';

// ✅ 应用内认证统一入口
import 'package:swaply/services/auth_service.dart';

class OAuthEntry {
  OAuthEntry._();

  static bool _inFlight = false;
  static bool get inFlight => _inFlight;

  // ✅ UI 通知
  static final ValueNotifier<bool> inFlightNotifier =
      ValueNotifier<bool>(false);

  // ✅ 持久化 key 与超时
  static const String _kOAuthInFlightKey = 'oauth_in_flight_timestamp';
  static const String _kOAuthProviderKey = 'oauth_provider';
  static const int _kOAuthTimeoutSeconds = 10;

  static int _epoch = 0;
  static Timer? _resetTimer;

  static DateTime? _lastTriggerTime;
  static String? _lastProvider;

  // ========== ✅ 智能状态恢复 ==========
  static Future<void> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_kOAuthInFlightKey);
      final provider = prefs.getString(_kOAuthProviderKey);

      if (timestamp == null) {
        debugPrint('[OAuthEntry] No saved state');
        return;
      }

      final elapsed = DateTime.now().millisecondsSinceEpoch - timestamp;
      final elapsedSeconds = elapsed / 1000;

      if (elapsedSeconds < 5) {
        _setInFlight(true);
        _lastProvider = provider;
        debugPrint(
            '[OAuthEntry] Restored inFlight=true (${elapsedSeconds.toStringAsFixed(1)}s ago, provider=$provider)');
        final remaining = (_kOAuthTimeoutSeconds * 1000) - elapsed;
        _armReset(++_epoch, Duration(milliseconds: remaining.toInt()));
        return;
      }

      if (elapsedSeconds < 15) {
        _setInFlight(true);
        _lastProvider = provider;
        debugPrint(
            '[OAuthEntry] Restored inFlight=true with SHORT timeout (${elapsedSeconds.toStringAsFixed(1)}s ago)');
        _armReset(++_epoch, const Duration(seconds: 5));
        return;
      }

      debugPrint(
          '[OAuthEntry] Clearing expired state (${elapsedSeconds.toStringAsFixed(1)}s ago)');
      await prefs.remove(_kOAuthInFlightKey);
      await prefs.remove(_kOAuthProviderKey);
    } catch (e) {
      debugPrint('[OAuthEntry] restoreState error: $e');
    }
  }

  // ✅ 统一设置 inFlight
  static void _setInFlight(bool value) {
    _inFlight = value;
    inFlightNotifier.value = value;
  }

  // ✅ 持久化 inFlight + provider
  static Future<void> _persistInFlight(bool value, {String? provider}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setInt(
            _kOAuthInFlightKey, DateTime.now().millisecondsSinceEpoch);
        if (provider != null) {
          await prefs.setString(_kOAuthProviderKey, provider);
        }
      } else {
        await prefs.remove(_kOAuthInFlightKey);
        await prefs.remove(_kOAuthProviderKey);
      }
    } catch (e) {
      debugPrint('[OAuthEntry] _persistInFlight error: $e');
    }
  }

  static bool mayStartInteractive() => !inFlight;

  // ========== ✅ 强制取消（页面离开时调用） ==========
  static void cancelIfInFlight() {
    if (!_inFlight) return;
    debugPrint('[OAuthEntry] cancelIfInFlight called (user left login screen)');
    _clear(_epoch, reason: 'user_cancelled');
  }

  static void forceCancel() {
    try {
      finish();
    } catch (_) {}
  }

  /// ✅ 识别 OAuth 回调（支持自定义 URL Scheme + HTTPS）
  /// 移动端:
  ///   - swaply://login-callback
  /// Web 端:
  ///   - https://swaply.cc/auth/callback
  ///   - https://swaply.cc/login-callback（兼容）
  static bool isOAuthCallback(Uri? uri) {
    if (uri == null) return false;

    // ✅ 自定义 URL Scheme 回调（移动端）
    if (uri.scheme == 'swaply' && uri.host == 'login-callback') {
      return true;
    }

    // ✅ HTTPS 回调（Web 端 + 兼容旧配置）
    if (uri.scheme == 'https') {
      final h = uri.host.toLowerCase();
      if (h == 'swaply.cc' || h == 'www.swaply.cc') {
        final seg = uri.pathSegments;
        final isAuthCallback =
            (seg.length >= 2 && seg[0] == 'auth' && seg[1] == 'callback');
        final isLoginCallback = (seg.isNotEmpty && seg[0] == 'login-callback');
        return isAuthCallback || isLoginCallback;
      }
    }

    return false;
  }

  // ✅ 兜底定时器，避免 UI 永久锁死
  static void _armReset(int ticket,
      [Duration d = const Duration(seconds: 10)]) {
    _resetTimer?.cancel();
    _resetTimer = Timer(d, () {
      _clear(ticket, reason: 'timeout');
    });
  }

  static void _clear(int ticket, {String reason = 'finish'}) {
    if (ticket != _epoch) {
      debugPrint(
          '[OAuthEntry] skip clear (stale ticket=$ticket < current=$_epoch), reason=$reason');
      return;
    }

    _setInFlight(false);
    _resetTimer?.cancel();
    _resetTimer = null;
    _lastTriggerTime = null;
    _lastProvider = null;
    _persistInFlight(false);

    debugPrint(
        '[OAuthEntry] cleared (reason=$reason), inFlight=false, epoch=$_epoch');
  }

  /// ✅ 统一入口：三方登录完全内置
  /// Google / Facebook / Apple → 交给 AuthService().signInWithNativeProvider(provider)
  /// 其它供应商（若未来新增）才走内置 WebView
  static Future<void> signIn(
    OAuthProvider provider, {
    String? scopes,
    Map<String, String>? queryParams,
  }) async {
    if (_inFlight) {
      debugPrint(
          '[OAuthEntry] duplicate signIn ignored: provider=$provider (inFlight=true, epoch=$_epoch)');
      return;
    }

    final int ticket = ++_epoch;
    _setInFlight(true);
    _lastTriggerTime = DateTime.now();
    _lastProvider = provider.name;
    await _persistInFlight(true, provider: provider.name);

    debugPrint('[OAuthEntry] signIn begin: provider=$provider, epoch=$ticket');
    _armReset(ticket);

    // ① 自动 scopes（备用，仅当走 WebView 分支时使用）
    String resolvedScopes = (scopes ?? '').trim();
    if (resolvedScopes.isEmpty) {
      switch (provider) {
        case OAuthProvider.google:
          resolvedScopes = 'openid email profile';
          break;
        case OAuthProvider.facebook:
          resolvedScopes = 'public_profile,email';
          break;
        case OAuthProvider.apple:
          resolvedScopes = 'email name';
          break;
        default:
          resolvedScopes = '';
      }
    }

    final Map<String, String> qp = {if (queryParams != null) ...queryParams};

    try {
      switch (provider) {
        case OAuthProvider.google:
        case OAuthProvider.facebook:
        case OAuthProvider.apple:
          // ✅ 三种都走原生/系统浏览器方案（由 AuthService 内部决定）
          await AuthService().signInWithNativeProvider(provider);
          break;

        default:
          // ✅ 其它供应商（未来新增）才走内置 WebView
          await Supabase.instance.client.auth.signInWithOAuth(
            provider,
            redirectTo: getAuthRedirectUri(),
            authScreenLaunchMode: LaunchMode.inAppWebView,
            scopes: resolvedScopes.isEmpty ? null : resolvedScopes,
            queryParams: qp.isEmpty ? null : qp,
          );
      }
      // 成功后由 onAuthStateChange / deeplink 去 clear（幂等）
    } on AuthException catch (e, st) {
      debugPrint('[OAuthEntry] signIn error(AuthException): $e\n$st');
      _clear(ticket, reason: 'error');
      rethrow;
    } catch (e, st) {
      debugPrint('[OAuthEntry] signIn error: $e\n$st');
      _clear(ticket, reason: 'error');
      rethrow;
    }
  }

  // 兼容旧入口
  static Future<void> start({
    required OAuthProvider provider,
    String? scopes,
    Map<String, dynamic>? queryParams,
  }) {
    final qp = queryParams?.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return signIn(provider, scopes: scopes, queryParams: qp);
  }

  static void finish() {
    _clear(_epoch, reason: 'finish()');
  }

  static void clearGuardIfSignedIn(AuthState state) {
    final ok =
        state.event == AuthChangeEvent.signedIn || state.session?.user != null;
    if (ok) {
      _clear(_epoch, reason: 'onAuthStateChange:signedIn');
    } else if (state.event == AuthChangeEvent.userUpdated ||
        state.event == AuthChangeEvent.initialSession) {
      if (state.session?.user != null) {
        _clear(_epoch, reason: 'onAuthStateChange:userUpdated/initialSession');
      }
    }
  }
}
