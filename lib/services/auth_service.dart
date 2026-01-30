// lib/services/auth_service.dart
// 登录/注册/OAuth 统一：
// - Apple：iOS 原生；Android 用系统浏览器
// - Google：原生 SDK（完全应用内）✅
// - Facebook：原生 SDK（完全应用内）✅ 可直接拉起 Facebook App
//
// ⚠️ 架构原则（Swaply 架构铁律）：
// - AuthFlowObserver 是唯一鉴权仲裁者
// - 本服务只负责启动认证流程，不处理导航
// - 所有登录后的导航、Profile创建、FCM初始化由 AuthFlowObserver 统一处理

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:swaply/services/apple_auth_service.dart';
import 'package:swaply/services/facebook_auth_service.dart'; // ✅ 新增

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
        await _signInWithFacebookNative(); // ✅ 改用原生 SDK
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

  /// ✅ Facebook 原生登录（NEW - 可直接拉起 Facebook App）
  ///
  /// 流程：
  /// 1. 使用 flutter_facebook_auth 调起 Facebook App（如已安装）
  /// 2. 用户在 Facebook App 中授权
  /// 3. 获取 Facebook Access Token
  /// 4. 使用 Supabase signInWithIdToken() 创建 session
  /// 5. AuthFlowObserver 自动处理后续流程
  ///
  /// 优势：
  /// - ✅ 可以直接拉起 Facebook App（无需浏览器）
  /// - ✅ 用户体验更好（类似 Google 登录）
  /// - ✅ 不需要配置复杂的 Deep Link 回调
  /// - ✅ 符合 Swaply 架构原则
  Future<void> _signInWithFacebookNative() async {
    try {
      debugPrint('[AuthService] 🔵 Starting Facebook native login...');

      final success = await FacebookAuthService.instance.signIn();

      if (!success) {
        throw AuthException('Facebook sign-in failed or was cancelled');
      }

      debugPrint('[AuthService] ✅ Facebook native login successful');
      // AuthFlowObserver 会自动处理后续流程

    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook native login error: $e\n$st');
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

  /// ✅ Facebook 登录（NEW - 使用原生 SDK）
  ///
  /// 架构说明：
  /// - 使用 flutter_facebook_auth 原生 SDK
  /// - 可以直接拉起 Facebook App 授权
  /// - AuthFlowObserver 会自动处理后续流程（导航、Profile、FCM）
  /// - 符合 Swaply 架构原则
  ///
  /// 返回值：
  /// - true: 新用户（需要显示欢迎页面）
  /// - false: 老用户或用户取消
  Future<bool> signInWithFacebook() async {
    try {
      debugPrint('[AuthService] 🔵 Facebook login starting...');

      await signInWithNativeProvider(OAuthProvider.facebook);

      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('[AuthService] ⚠️ User is null after Facebook login');
        return false;
      }

      // 检查是否为新用户
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // 创建或更新 Profile
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      // 初始化 FCM
      await NotificationService.initializeFCM();

      debugPrint('[AuthService] ✅ Facebook login successful, isNew=$isNew');
      return isNew;

    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook login error: $e\n$st');
      rethrow;
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
      // ✅ 同时登出 Facebook SDK（如果使用了 Facebook 登录）
      await FacebookAuthService.instance.signOut();

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