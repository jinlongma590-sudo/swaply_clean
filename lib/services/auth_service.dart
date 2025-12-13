// lib/services/auth_service.dart
// 登录/注册/OAuth 统一：
// - Apple：iOS 原生；Android 用系统浏览器
// - Google：原生 SDK（完全应用内）
// - Facebook：系统浏览器 OAuth（ASWebAuthenticationSession / Chrome Custom Tabs）✅ 修改完成
// 备注：为兼容你当前的 supabase_flutter 版本，移除了 flowType / OAuthFlowType

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:google_sign_in/google_sign_in.dart';
// ❌ 已删除：import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:swaply/services/apple_auth_service.dart';

import 'package:swaply/config/auth_config.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/services/notification_service.dart';

class AuthService {
  SupabaseClient get supabase => Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  bool get isEmailVerified => false;

  // ====== 应用内认证统一入口 ======
  Future<void> signInWithNativeProvider(OAuthProvider provider) async {
    switch (provider) {
      case OAuthProvider.apple:
        if (Platform.isIOS) {
          await _signInWithAppleNative();
        } else {
          // Android：使用系统浏览器（Chrome Custom Tabs）
          await Supabase.instance.client.auth.signInWithOAuth(
            OAuthProvider.apple,
            authScreenLaunchMode: LaunchMode.externalApplication,
            redirectTo: getAuthRedirectUri(),
            scopes: 'email name',
          );
        }
        break;

      case OAuthProvider.google:
        await _signInWithGoogleNative();
        break;

      case OAuthProvider.facebook:
        await _signInWithFacebookOAuth(); // ✅ 修改：使用 OAuth 系统浏览器方式
        break;

      default:
        throw Exception('Unsupported native provider: $provider');
    }
  }

  /// Apple 原生登录（仅 iOS）
  Future<void> _signInWithAppleNative() async {
    final success = await AppleAuthService().signIn();
    if (!success) {
      throw AuthException('Apple sign-in failed or was cancelled');
    }
  }

  /// Google 原生登录（iOS/Android）
  Future<void> _signInWithGoogleNative() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      // 如需强制账号选择器可先 signOut：await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('Google sign-in was cancelled');
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw AuthException('Google ID token is null');
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );
    } catch (e) {
      debugPrint('[AuthService] Google native sign-in error: $e');
      rethrow;
    }
  }

  /// ✅ Facebook OAuth 登录（系统浏览器）
  /// iOS: 自动使用 ASWebAuthenticationSession
  /// Android: 自动使用 Chrome Custom Tabs
  Future<void> _signInWithFacebookOAuth() async {
    try {
      debugPrint('[AuthService] 🔵 Starting Facebook OAuth sign-in...');

      // 使用 Supabase OAuth flow（系统浏览器）
      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: kIsWeb ? null : 'cc.swaply.app://login-callback',
        // ✅ 不指定 authScreenLaunchMode，让 SDK 自动选择最佳方式：
        // - iOS: ASWebAuthenticationSession（系统级安全登录页）
        // - Android: Chrome Custom Tabs（类似效果）
        //
        // 如果需要强制使用外部浏览器（不推荐），可以设置：
        // authScreenLaunchMode: LaunchMode.externalApplication,
      );

      debugPrint('[AuthService] ✅ Facebook OAuth initiated');
    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook OAuth error: $e\n$st');
      rethrow;
    }
  }

  // ====== 会话手动刷新（保留接口，但默认不用）======
  DateTime? _lastRefresh;
  Future<void> refreshSession({Duration minInterval = const Duration(seconds: 30)}) async {
    debugPrint('[AuthService] refreshSession() disabled. Using Supabase auto-refresh.');
    return;
  }

  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Login failed');

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'],
      );

      await NotificationService.initializeFCM();
      return isNew;
    } on AuthException catch (e) {
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<bool> signUpWithEmailPassword({
    required String email,
    required String password,
    String? fullName,
    String? phone,
  }) async {
    try {
      final meta = <String, dynamic>{};
      if (fullName?.isNotEmpty == true) meta['full_name'] = fullName;
      if (phone?.isNotEmpty == true) meta['phone'] = phone;

      await supabase.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: meta.isEmpty ? null : meta,
        emailRedirectTo: kAuthWebRedirectUri,
      );

      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Registration failed');

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: fullName,
        avatarUrl: user.userMetadata?['avatar_url'],
      );

      await NotificationService.initializeFCM();
      return true;
    } on AuthException catch (e) {
      throw Exception('Registration failed: ${e.message}');
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  // —— OAuth 便捷方法 —— //
  Future<bool> signInWithGoogle() async {
    try {
      await signInWithNativeProvider(OAuthProvider.google);

      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      await NotificationService.initializeFCM();
      return isNew;
    } catch (e) {
      throw Exception('Google login failed: $e');
    }
  }

  Future<bool> signInWithFacebook() async {
    try {
      await signInWithNativeProvider(OAuthProvider.facebook);

      // ✅ 注意：OAuth flow 后，session 由 Supabase 的 deep link 处理自动建立
      // AuthFlowObserver 会处理导航到 /home

      // 等待 session 建立（最多 5 秒）
      final user = await supabase.auth.onAuthStateChange
          .map((e) => e.session?.user)
          .firstWhere((u) => u != null, orElse: () => null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (user == null) {
        throw AuthException('Facebook login session timeout');
      }

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['name'] ?? user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      await NotificationService.initializeFCM();
      return isNew;
    } on AuthException catch (e) {
      throw Exception('Facebook login failed: ${e.message}');
    } catch (e) {
      throw Exception('Facebook login failed: $e');
    }
  }

  // —— 可复用的 profile 写入工具（保留以备后用） —— //
  Future<void> _createOrUpdateUserProfile({
    required String userId,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (email?.isNotEmpty == true) data['email'] = email!.trim().toLowerCase();
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(data, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) {
        print('Failed to upsert user profile: $e');
      }
    }
  }

  Future<void> _upsertProfilePartial(Map<String, dynamic> patch) async {
    final u = currentUser;
    if (u == null) return;
    await supabase.from('profiles').upsert({
      'id': u.id,
      'updated_at': DateTime.now().toIso8601String(),
      ...patch,
    }, onConflict: 'id');
  }

  Future<void> onEmailCodeVerified() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
  }

  Future<void> syncEmailVerificationStatus() async {
    try {
      await supabase.auth.refreshSession();
      await supabase.auth.getUser();
      if (kDebugMode) debugPrint('[AuthService] session refreshed');
    } catch (e) {
      if (kDebugMode) print('syncEmailVerificationStatus failed: $e');
    }
  }

  // ====== 登出 ======
  static bool _signingOut = false;
  Future<void> signOut({bool global = false, String reason = ''}) async {
    AuthFlowObserver.I.markManualSignOut();

    if (_signingOut) {
      debugPrint('[[SIGNOUT-TRACE]] skip (inflight) reason=$reason');
      return;
    }

    debugPrint('[[SIGNOUT-TRACE]] scope=${global ? 'global' : 'local'} reason=$reason');
    debugPrint(StackTrace.current.toString());

    _signingOut = true;
    try {
      await Supabase.instance.client.auth
          .signOut(scope: global ? SignOutScope.global : SignOutScope.local);
    } catch (e, st) {
      debugPrint('[[SIGNOUT-TRACE]] error: $e\n$st');
      rethrow;
    } finally {
      _signingOut = false;
    }
  }

  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user signed in');

      await Future.wait<void>([
        supabase.from('profiles').delete().eq('id', user.id).then((_) {}),
        supabase.from('coupons').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_tasks').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('reward_logs').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_invitations').delete().eq('inviter_id', user.id).then((_) {}),
        supabase.from('pinned_ads').delete().eq('user_id', user.id).then((_) {}),
      ]);

      await signOut();
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }

  // 原生事件流
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}