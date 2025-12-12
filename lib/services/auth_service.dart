// lib/services/auth_service.dart
// 登录/注册/OAuth 统一：
// - Apple：iOS 原生；Android 用系统浏览器
// - Google：原生 SDK（完全应用内）
// - Facebook：原生 SDK（完全应用内）✅ 修改
// 备注：为兼容你当前的 supabase_flutter 版本，移除了 flowType / OAuthFlowType

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
// LaunchMode 由 supabase_flutter 间接提供；如仍有提示，可改为：import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart'; // ✅ 新增
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
        await _signInWithFacebookNative(); // ✅ 修改：使用原生登录
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

  /// ✅ Facebook 原生登录（iOS/Android）- 新增方法
  Future<void> _signInWithFacebookNative() async {
    try {
      debugPrint('[AuthService] 🔵 Starting Facebook native sign-in...');

      // 1. 使用 Facebook SDK 登录
      final result = await FacebookAuth.instance.login(
        permissions: ['public_profile', 'email'],
      );

      debugPrint('[AuthService] Facebook login status: ${result.status}');

      // 2. 检查登录状态
      if (result.status != LoginStatus.success) {
        if (result.status == LoginStatus.cancelled) {
          throw AuthException('Facebook login was cancelled');
        } else {
          throw AuthException('Facebook login failed: ${result.status}');
        }
      }

      // 3. 获取 Access Token
      final accessToken = result.accessToken;
      if (accessToken == null) {
        throw AuthException('Facebook access token is null');
      }

      debugPrint('[AuthService] Facebook access token obtained');

      // 4. 使用 Facebook Access Token 登录 Supabase
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.facebook,
        idToken: accessToken.token,
      );

      debugPrint('[AuthService] ✅ Facebook native sign-in successful');
    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook native sign-in error: $e\n$st');
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

      // ✅ 等待 Supabase session 建立
      final ok = await supabase.auth.onAuthStateChange
          .map((e) => e.session?.user != null)
          .firstWhere((v) => v, orElse: () => false)
          .timeout(const Duration(seconds: 30), onTimeout: () => false);

      if (!ok) {
        throw AuthException('Facebook login session timeout');
      }

      final user = supabase.auth.currentUser!;
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
