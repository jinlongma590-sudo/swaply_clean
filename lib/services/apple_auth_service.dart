// lib/services/apple_auth_service.dart
// Sign in with Apple → Supabase（iOS 专用）
// 逻辑要点：
// 1) 生成 raw nonce，并将其 sha256 作为 nonce 传给 Apple
// 2) 用 Apple 返回的 identityToken + raw nonce 调 Supabase 的 signInWithIdToken
// 3) 首登时可把姓名/邮箱写入 profiles（忽略失败）

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppleAuthService {
  AppleAuthService._();
  static final AppleAuthService _instance = AppleAuthService._();
  factory AppleAuthService() => _instance;

  final SupabaseClient _sb = Supabase.instance.client;

  /// 生成安全随机 nonce
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// 对字符串做 sha256（16 进制小写）
  String _sha256Of(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 发起 Apple 登录并写入 Supabase
  ///
  /// 返回 true 表示登录成功；用户取消或失败返回 false；会抛出极端错误（可在上层捕获）。
  Future<bool> signIn() async {
    if (!Platform.isIOS) {
      debugPrint('[AppleAuth] 非 iOS 平台，跳过');
      return false;
    }

    // 1) 准备 nonce
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256Of(rawNonce);

    try {
      // 2) 走 Apple 授权
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.fullName,
          AppleIDAuthorizationScopes.email,
        ],
        nonce: hashedNonce, // 注意：传给 Apple 是 sha256 后的
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[AppleAuth] identityToken 为空');
        return false;
      }

      // 3) 用 Apple 的 idToken + 原始 rawNonce 登录 Supabase
      final resp = await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce, // 注意：传给 Supabase 是原始 nonce
      );

      final user = resp.user ?? _sb.auth.currentUser;
      if (user == null) {
        debugPrint('[AppleAuth] Supabase 登录后 user 为空');
        return false;
      }

      // 4) 可选：首登补全 profile（失败忽略）
      final given = (credential.givenName ?? '').trim();
      final family = (credential.familyName ?? '').trim();
      final fullName =
          ([given, family]..removeWhere((e) => e.isEmpty)).join(' ');
      final email = (credential.email ?? '').trim();

      if (fullName.isNotEmpty || email.isNotEmpty) {
        try {
          // ✅ [P1 修复] 先检查是否已有 profile
          final existing = await _sb
              .from('profiles')
              .select('id, full_name, verification_type, is_verified')
              .eq('id', user.id)
              .maybeSingle();

          if (existing == null) {
            // ✅ 新用户：可以写入 full_name
            await _sb.from('profiles').insert({
              'id': user.id,
              if (fullName.isNotEmpty) 'full_name': fullName,
              if (email.isNotEmpty) 'email': email,
              'verification_type': 'verified',
              'is_verified': true,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            debugPrint('[AppleAuth] 新用户 profile 已创建（自动认证已设置）');
          } else {
            // ✅ 已有用户：更新 email、时间戳和验证状态（只在当前状态为 none 时更新），不覆盖 full_name
            final currentType = existing['verification_type'] as String?;
            final currentVerified = existing['is_verified'] as bool?;
            final shouldUpdate = currentType == null || currentType == 'none' || currentVerified != true;
            
            final updateData = <String, dynamic>{
              if (email.isNotEmpty) 'email': email,
              'updated_at': DateTime.now().toIso8601String(),
            };
            
            if (shouldUpdate) {
              updateData['verification_type'] = 'verified';
              updateData['is_verified'] = true;
            }
            
            await _sb.from('profiles').update(updateData).eq('id', user.id);
            
            if (shouldUpdate) {
              debugPrint('[AppleAuth] 已有用户 profile 已更新（自动认证已设置，从 $currentType 升级）');
            } else {
              debugPrint('[AppleAuth] ℹ️ 用户已认证: verification_type="$currentType"，跳过自动认证');
            }
          }
        } catch (e) {
          debugPrint('[AppleAuth] profile update error: $e');
        }
      }

      return true;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        debugPrint('[AppleAuth] 用户取消 Apple 登录');
        return false;
      }
      debugPrint('[AppleAuth] 授权异常: $e');
      return false;
    } catch (e, st) {
      debugPrint('[AppleAuth] 未知异常: $e\n$st');
      rethrow; // 如果你不想抛出，也可以 return false;
    }
  }
}
