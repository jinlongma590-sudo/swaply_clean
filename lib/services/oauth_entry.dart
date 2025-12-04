// lib/services/oauth_entry.dart
//
// ✅ [P0 修复] 增加 ValueNotifier 通知机制，解决按钮锁死问题
// 统一的 OAuth 入口与"全局唯一开关"防重入实现：
// - 调用前立即上锁（_inFlight=true），杜绝并发重复触发导致的"双弹窗"
// - 使用 _epoch（ticket）避免"过期计时器/回调"误清锁
// - 成功后不立刻解锁：等 deep link / onAuthStateChange 确认后再解锁
// - finish() / clearGuardIfSignedIn() 两种安全收尾
// - 按 provider 自动选择正确 scopes，避免 Google 的 invalid_scope
// - ✅ 状态持久化，解决进程重启后 inFlight 丢失问题
// - ✅ 智能状态恢复 + cancelIfInFlight 主动清理
// - ✅ [NEW] ValueNotifier 通知 UI 更新，解决按钮锁死问题
//
// 建议用法：
// 1) 启动时：await OAuthEntry.restoreState(); // 恢复持久化状态
// 2) 触发：await OAuthEntry.signIn(OAuthProvider.facebook, ...);
// 3) 在 login-callback 深链成功分支：OAuthEntry.finish();
// 4) 或在全局 onAuthStateChange 里：OAuthEntry.clearGuardIfSignedIn(state);
// 5) 页面 dispose 时：OAuthEntry.cancelIfInFlight();
// 6) 页面监听状态：ValueListenableBuilder(valueListenable: OAuthEntry.inFlightNotifier, ...)

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OAuthEntry {
  OAuthEntry._();

  static bool _inFlight = false;
  static bool get inFlight => _inFlight;

  // ✅ [NEW] ValueNotifier 用于通知 UI 更新
  // 页面可以用 ValueListenableBuilder 监听此 notifier
  static final ValueNotifier<bool> inFlightNotifier = ValueNotifier<bool>(false);

  // ✅ 持久化 key 和过期时间
  static const String _kOAuthInFlightKey = 'oauth_in_flight_timestamp';
  static const String _kOAuthProviderKey = 'oauth_provider';
  static const int _kOAuthTimeoutSeconds = 10;  // ✅ 改为10秒，更快响应用户取消

  static int _epoch = 0;
  static Timer? _resetTimer;

  static const String _mobileRedirect = 'cc.swaply.app://login-callback';
  static const String _webRedirect = 'https://swaply.cc/auth/callback';

  static DateTime? _lastTriggerTime;
  static String? _lastProvider;

  // ========== ✅ 智能状态恢复 ==========
  /// 在 App 启动时调用，恢复因进程重启而丢失的 OAuth inFlight 状态
  ///
  /// ✅ 分三级策略
  /// - < 5秒：正常OAuth回调，完整恢复
  /// - 5-15秒：可能是用户中断，短超时恢复
  /// - > 15秒：清理过期状态
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

      // ✅ 策略1：< 5秒 = 正常OAuth回调流程，完整恢复
      if (elapsedSeconds < 5) {
        _setInFlight(true);  // ✅ 使用新方法，会同时更新 notifier
        _lastProvider = provider;
        debugPrint('[OAuthEntry] Restored inFlight=true (${elapsedSeconds.toStringAsFixed(1)}s ago, provider=$provider)');

        final remaining = (_kOAuthTimeoutSeconds * 1000) - elapsed;
        _armReset(++_epoch, Duration(milliseconds: remaining.toInt()));
        return;
      }

      // ✅ 策略2：5-15秒 = 可能是用户中断后快速重启，保守恢复
      if (elapsedSeconds < 15) {
        _setInFlight(true);
        _lastProvider = provider;
        debugPrint('[OAuthEntry] Restored inFlight=true with SHORT timeout (${elapsedSeconds.toStringAsFixed(1)}s ago)');

        // 只给5秒窗口，快速超时
        _armReset(++_epoch, const Duration(seconds: 5));
        return;
      }

      // ✅ 策略3：> 15秒 = 用户早已离开，清理过期状态
      debugPrint('[OAuthEntry] Clearing expired state (${elapsedSeconds.toStringAsFixed(1)}s ago)');
      await prefs.remove(_kOAuthInFlightKey);
      await prefs.remove(_kOAuthProviderKey);

    } catch (e) {
      debugPrint('[OAuthEntry] restoreState error: $e');
    }
  }

  // ✅ [NEW] 统一的 _inFlight 设置方法，同时更新 ValueNotifier
  static void _setInFlight(bool value) {
    _inFlight = value;
    inFlightNotifier.value = value;
  }

  // ✅ 持久化状态时同时保存provider
  static Future<void> _persistInFlight(bool value, {String? provider}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setInt(_kOAuthInFlightKey, DateTime.now().millisecondsSinceEpoch);
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

  /// 若仍有进行中的 OAuth 交互，则暂不允许再次发起
  static bool mayStartInteractive() {
    return !inFlight;
  }

  // ========== ✅ 强制取消当前OAuth流程 ==========
  /// 供登录/注册页面 dispose 时调用
  /// 用户离开页面时主动清理OAuth状态，防止按钮永久锁死
  static void cancelIfInFlight() {
    if (!_inFlight) return;

    debugPrint('[OAuthEntry] cancelIfInFlight called (user left login screen)');
    _clear(_epoch, reason: 'user_cancelled');
  }

  /// 立即结束当前 OAuth 尝试（比如用户从浏览器返回，只想重试）
  static void forceCancel() {
    try {
      finish();
    } catch (_) {}
  }

  /// ✅ 检查 URI 是否是 OAuth 回调（供冷启动判断用）
  /// 解决冷启动时 _inFlight 被重置为 false 的问题
  static bool isOAuthCallback(Uri? uri) {
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    // 1) 自定义 scheme：cc.swaply.app://login-callback
    if (scheme == 'cc.swaply.app' && host == 'login-callback') {
      return true;
    }

    // 2) HTTPS 回调：https://swaply.cc/auth/callback
    if (scheme == 'https' &&
        (host == 'swaply.cc' || host == 'www.swaply.cc' || host == 'cc.swaply.app')) {
      final segments = uri.pathSegments;
      // auth/callback
      if (segments.length >= 2 &&
          segments[0] == 'auth' &&
          segments[1] == 'callback') {
        return true;
      }
      // 兜底：login-callback
      if (segments.isNotEmpty && segments[0] == 'login-callback') {
        return true;
      }
    }

    return false;
  }

  /// ✅ 为指定 ticket 启动兜底定时器（避免用户关闭外部页后 UI 永久锁死）
  static void _armReset(int ticket, [Duration d = const Duration(seconds: 10)]) {
    _resetTimer?.cancel();
    _resetTimer = Timer(d, () {
      _clear(ticket, reason: 'timeout');
    });
  }

  /// 带 ticket 的安全清锁：旧的 timer/回调不会清掉新一轮的锁
  static void _clear(int ticket, {String reason = 'finish'}) {
    if (ticket != _epoch) {
      debugPrint('[OAuthEntry] skip clear (stale ticket=$ticket < current=$_epoch), reason=$reason');
      return;
    }

    // ✅ 使用新方法，会同时更新 notifier
    _setInFlight(false);

    _resetTimer?.cancel();
    _resetTimer = null;
    _lastTriggerTime = null;
    _lastProvider = null;

    // ✅ 清除持久化状态
    _persistInFlight(false);

    debugPrint('[OAuthEntry] cleared (reason=$reason), inFlight=false, epoch=$_epoch');
  }

  /// ✅ 使用"外部浏览器 / App-to-App"发起 OAuth 登录（最终版，带 auto-scope）
  static Future<void> signIn(
      OAuthProvider provider, {
        String? scopes,
        Map<String, String>? queryParams,
      }) async {
    if (_inFlight) {
      debugPrint(
        '[OAuthEntry] duplicate signIn ignored: provider=$provider (inFlight=true, epoch=$_epoch)',
      );
      return;
    }

    // 调用前立即上锁，并生成本次请求的 ticket
    final int ticket = ++_epoch;
    _setInFlight(true);  // ✅ 使用新方法，会同时更新 notifier
    _lastTriggerTime = DateTime.now();
    _lastProvider = provider.name;

    // ✅ 持久化状态（包含provider信息）
    await _persistInFlight(true, provider: provider.name);

    debugPrint('[OAuthEntry] signIn begin: provider=$provider, epoch=$ticket');
    _armReset(ticket);

    // ① 根据 provider 自动选择正确的 scopes（页面不要再自行传）
    String resolvedScopes = (scopes ?? '').trim();
    if (resolvedScopes.isEmpty) {
      switch (provider) {
        case OAuthProvider.google:
        // Google 标准：OpenID Connect
          resolvedScopes = 'openid email profile';
          break;
        case OAuthProvider.facebook:
        // Facebook 标准
          resolvedScopes = 'public_profile,email';
          break;
        case OAuthProvider.apple:
        // Apple 可选
          resolvedScopes = 'email name';
          break;
        default:
          resolvedScopes = ''; // 其余保持默认
      }
    }

    // ② 平台差异化的 query 参数
    //    - Facebook 在外部浏览器里用 display=page 体验更稳
    final Map<String, String> qp = {
      if (provider == OAuthProvider.facebook) 'display': 'page',
      if (queryParams != null) ...queryParams,
    };

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? _webRedirect : _mobileRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication, // ★ 外部浏览器/APP
        scopes: resolvedScopes.isEmpty ? null : resolvedScopes,
        queryParams: qp.isEmpty ? null : qp,
      );
      // 成功登录的情况：由 deep link / onAuthStateChange 去 clear（幂等）
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

  /// ✅ 兼容旧调用：OAuthEntry.start(...)
  /// 让 login_screen.dart / register_screen.dart 里旧代码无需改动
  static Future<void> start({
    required OAuthProvider provider,
    String? scopes,
    Map<String, dynamic>? queryParams,
  }) {
    // 动态参数 Map<String, dynamic> -> Map<String, String>
    final qp = queryParams == null
        ? null
        : queryParams.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return signIn(
      provider,
      scopes: scopes, // 允许传，但建议页面端不传，让这里自动判
      queryParams: qp,
    );
  }

  /// 手动完成（推荐在深链 login-callback 处理成功后调用）
  static void finish() {
    _clear(_epoch, reason: 'finish()');
  }

  /// 在全局 onAuthStateChange 里调用：收到已登录则清锁
  static void clearGuardIfSignedIn(AuthState state) {
    final ok = state.event == AuthChangeEvent.signedIn || state.session?.user != null;
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