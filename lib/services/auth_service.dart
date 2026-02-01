// lib/services/auth_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:swaply/services/apple_auth_service.dart';
import 'package:swaply/services/facebook_auth_service.dart';

import 'package:swaply/config/auth_config.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/services/notification_service.dart';

class AuthService {
  SupabaseClient get supabase => Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  bool get isEmailVerified => false;

  // ====== Nonce 工具函数 ======
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ====== 应用内认证统一入口 ======
  Future<void> signInWithNativeProvider(OAuthProvider provider) async {
    switch (provider) {
      case OAuthProvider.apple:
        if (Platform.isIOS) {
          await _signInWithAppleNative();
        } else {
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
        await _signInWithFacebookNative();
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

  /// ✅ Google 原生登录（完美修复 iOS 报错，Android 兼容）
  Future<void> _signInWithGoogleNative() async {
    try {
      debugPrint('[AuthService] 🔵 Starting Google native login...');

      // ✅ 使用 Web Client ID (来自 Google Cloud Console "Swaply OAuth")
      // 这会让 iOS SDK 生成 Supabase 后端可验证的 OIDC Token，绕过 Nonce 校验死锁
      const webClientId = '947323234114-g5sd06ljn4n68dsq4o95khogm1tc48pq.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        // 关键点：传入 serverClientId
        serverClientId: webClientId,
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google sign-in was cancelled');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 使用 serverClientId 后，idToken 依然存在且有效
      if (googleAuth.idToken == null) {
        throw const AuthException('Google ID token is null');
      }

      debugPrint('[AuthService] ✅ Got Google ID token');

      // 将 Token 发送给 Supabase 进行验证和登录
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      debugPrint('[AuthService] ✅ Google login successful');

    } catch (e, st) {
      debugPrint('[AuthService] ❌ Google native sign-in error: $e\n$st');
      rethrow;
    }
  }

  /// ✅ Facebook 原生登录
  Future<void> _signInWithFacebookNative() async {
    try {
      debugPrint('[AuthService] 🔵 Starting Facebook native login...');

      final success = await FacebookAuthService.instance.signIn();

      if (!success) {
        throw AuthException('Facebook sign-in failed or was cancelled');
      }

      debugPrint('[AuthService] ✅ Facebook native login successful');

    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook native login error: $e\n$st');
      rethrow;
    }
  }

  // ====== 会话手动刷新（保留接口，但默认不用）======
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
      debugPrint('[AuthService] 🔵 Facebook login starting...');

      await signInWithNativeProvider(OAuthProvider.facebook);

      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('[AuthService] ⚠️ User is null after Facebook login');
        return false;
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
        fullName: user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      await NotificationService.initializeFCM();

      debugPrint('[AuthService] ✅ Facebook login successful, isNew=$isNew');
      return isNew;

    } catch (e, st) {
      debugPrint('[AuthService] ❌ Facebook login error: $e\n$st');
      rethrow;
    }
  }

  // —— 可复用的 profile 写入工具 —— //
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

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}