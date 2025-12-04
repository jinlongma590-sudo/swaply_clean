// lib/services/auth_service.dart
// 登录/注册/OAuth 统一：回调 URI、最小权限、防重复确认；profile 创建与欢迎弹窗交给 ProfileService
// 2.1 前端不再直接写 profiles 的“验证相关”字段（email_verified / is_verified / verification_type 由 DB 负责）
// 2.2 onEmailCodeVerified 仅本地会话刷新，不写 DB
// 2.3 UI/模型以 auth 为准；profiles 做基础资料（见 verification_utils.dart）

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/config/auth_config.dart';
import 'package:swaply/services/profile_service.dart'; // 统一创建 profile / 欢迎弹窗
import 'package:swaply/services/oauth_entry.dart';     // OAuthEntry 封装
import 'package:swaply/services/auth_flow_observer.dart'; // ✅ 引入 Observer

// 统一移动端回调（已在 iOS Info.plist / Android Manifest 配好）
const String _kMobileRedirect = 'cc.swaply.app://login-callback';

class AuthService {
  SupabaseClient get supabase => Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // legacy: 邮箱验证状态交给 DB 与服务端判定，这里不再本地兜底
  bool get isEmailVerified => false;

  // ====== 会话手动刷新（保留接口，但默认不用，由 Supabase 自动刷新）======
  DateTime? _lastRefresh;

  Future<void> refreshSession({
    Duration minInterval = const Duration(seconds: 30),
  }) async {
    debugPrint('[AuthService] refreshSession() disabled. Using Supabase auto-refresh.');
    return;
  }
  // ============================================================================

  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Login failed');

      // 判断是否新用户（以 profiles 是否存在为准）
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // 交给 ProfileService：确保 profile 存在 + 欢迎弹窗
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'],
      );

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
        emailRedirectTo: kAuthRedirectUri, // 统一回调
      );

      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Registration failed');

      // 新注册用户：初始化 profile + 欢迎弹窗（验证字段仍由 DB 处理）
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: fullName,
        avatarUrl: user.userMetadata?['avatar_url'],
      );

      return true;
    } on AuthException catch (e) {
      throw Exception('Registration failed: ${e.message}');
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  // --- 直接使用 Supabase OAuth（iOS/Android/Web 统一回调）---

  Future<bool> signInWithGoogle() async {
    try {
      await OAuthEntry.signIn(
        OAuthProvider.google,
        queryParams: const {'prompt': 'select_account'},
      );

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

      return isNew;
    } catch (e) {
      throw Exception('Google login failed: $e');
    }
  }

  Future<bool> signInWithFacebook() async {
    try {
      await OAuthEntry.signIn(
        OAuthProvider.facebook,
        scopes: 'public_profile,email',
        // ✅ 仅 Web 传 popup；移动端不传，避免“双弹”
        queryParams: kIsWeb ? const {'display': 'popup'} : null,
      );

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
        fullName: user.userMetadata?['name'] ?? user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      return isNew;
    } on AuthException catch (e) {
      throw Exception('Facebook login failed: ${e.message}');
    } catch (e) {
      throw Exception('Facebook login failed: $e');
    }
  }

  // —— 可复用的 profile 写入工具（不写验证相关字段） —— //
  Future<void> _createOrUpdateUserProfileForNewUser({
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
        // ⚠️ 不写 email_verified / is_verified / verification_type
      };

      if (email?.isNotEmpty == true) {
        data['email'] = email!.trim().toLowerCase();
      }
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(
        data,
        onConflict: 'id',
      );

      if (kDebugMode) {
        print('[AuthService] New user profile created (verification fields by DB defaults)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to upsert user profile: $e');
      }
    }
  }

  Future<void> _createOrUpdateUserProfile({
    required String userId,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      // 先检查是否存在（可省略，但保留可读性）
      await supabase
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      final data = <String, dynamic>{
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        // ⚠️ 不写验证字段
      };

      if (email?.isNotEmpty == true) {
        data['email'] = email!.trim().toLowerCase();
      }
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(
        data,
        onConflict: 'id',
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to upsert user profile: $e');
      }
    }
  }

  // 局部更新（不改验证字段）
  Future<void> _upsertProfilePartial(Map<String, dynamic> patch) async {
    final u = currentUser;
    if (u == null) return;
    await supabase.from('profiles').upsert(
      {
        'id': u.id,
        'updated_at': DateTime.now().toIso8601String(),
        ...patch,
      },
      onConflict: 'id',
    );
  }

  /// 验证码验证后的回调：仅本地会话刷新，拉取最新 app_metadata，不写 DB
  Future<void> onEmailCodeVerified() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
  }

  /// 同步本地 session（NO-OP：不写 profiles 的 email_verified）
  Future<void> syncEmailVerificationStatus() async {
    try {
      await supabase.auth.refreshSession();
      await supabase.auth.getUser();
      if (kDebugMode) {
        debugPrint('[AuthService] session refreshed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('syncEmailVerificationStatus failed: $e');
      }
    }
  }

  Future<void> signInAnonymously() async {
    try {
      await supabase.auth.signInAnonymously();
      if (supabase.auth.currentUser == null) {
        throw Exception('Anonymous login failed');
      }
    } on AuthException catch (e) {
      throw Exception('Anonymous login failed: ${e.message}');
    }
  }

  // 统一回调 URI 的重置邮件
  Future<void> resetPassword(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? 'https://swaply.cc/auth/callback' : _kMobileRedirect,
      );
    } on AuthException catch (e) {
      throw Exception('Password reset failed: ${e.message}');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw Exception('Password update failed: ${e.message}');
    }
  }

  Future<void> updateUserData({
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final meta = <String, dynamic>{};
      if (fullName != null) meta['full_name'] = fullName;
      if (phone != null) meta['phone'] = phone;
      if (metadata != null) meta.addAll(metadata);

      if (meta.isNotEmpty || email != null) {
        await supabase.auth.updateUser(
          UserAttributes(
            email: email?.trim().toLowerCase(),
            data: meta.isEmpty ? null : meta,
          ),
          emailRedirectTo: kAuthRedirectUri, // 统一回调
        );
      }

      final user = currentUser;
      if (user != null) {
        final patch = <String, dynamic>{
          'id': user.id,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (email != null) {
          patch['email'] = email.trim().toLowerCase();
        }
        if (fullName != null) patch['full_name'] = fullName;
        if (phone != null) patch['phone'] = phone;
        if (avatarUrl != null) patch['avatar_url'] = avatarUrl;

        // 不修改验证状态
        await supabase.from('profiles').upsert(patch, onConflict: 'id');
      }
    } on AuthException catch (e) {
      throw Exception('User update failed: ${e.message}');
    } catch (e) {
      throw Exception('User update failed: $e');
    }
  }

  // ====== 防重登出 ======
  static bool _signingOut = false;

  /// 默认 LOCAL 登出，避免误伤其它设备会话；
  /// 仅在“设置→退出登录(所有设备)”等场景传 global=true。
  Future<void> signOut({bool global = false, String reason = ''}) async {
    AuthFlowObserver.I.markManualSignOut(); // ✅ 标记手动登出，触发快车道

    if (_signingOut) {
      debugPrint('[[SIGNOUT-TRACE]] AuthService.signOut skipped (inflight) reason=$reason');
      return;
    }

    debugPrint('[[SIGNOUT-TRACE]] AuthService.signOut scope=${global ? 'global' : 'local'} reason=$reason');
    debugPrint(StackTrace.current.toString()); // 打印调用栈

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
  // ======================

  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      await Future.wait<void>([
        supabase.from('profiles').delete().eq('id', user.id).then((_) {}),
        supabase.from('coupons').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_tasks').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('reward_logs').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_invitations').delete().eq('inviter_id', user.id).then((_) {}),
        supabase.from('pinned_ads').delete().eq('user_id', user.id).then((_) {}),
      ]);

      await signOut(); // 默认 local
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }

  // 对外使用 Supabase 的原生事件流（此处不自建监听）
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}