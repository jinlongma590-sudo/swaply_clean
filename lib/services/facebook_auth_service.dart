import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class FacebookAuthService {
  static final FacebookAuthService instance = FacebookAuthService._internal();
  factory FacebookAuthService() => instance;
  FacebookAuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _edgeFunctionUrl =
      'https://rhckybselarzglkmlyqs.supabase.co/functions/v1/facebook-auth';
  // 注意：生产环境建议将 Key 放入环境变量或混淆处理
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DnNwqtzjBjEl1OqoSA2SGhv_f_2XqH2RrOCjxo';

  Future<bool> signIn() async {
    debugPrint('[FacebookAuth] 🔵 Starting Facebook native login...');
    debugPrint('[FacebookAuth] 📱 Platform: ${Platform.isIOS ? "iOS" : "Android"}');

    try {
      // 1. 发起登录
      // 使用 nativeWithFallback 兼顾原生体验和兼容性
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
        loginBehavior: Platform.isIOS
            ? LoginBehavior.nativeWithFallback
            : LoginBehavior.nativeWithFallback,
      );

      debugPrint('[FacebookAuth] Login status: ${result.status}');
      if (result.message != null) {
        debugPrint('[FacebookAuth] Login message: ${result.message}');
      }

      if (result.status != LoginStatus.success) {
        debugPrint('[FacebookAuth] ❌ Facebook login failed: ${result.status}');
        return false;
      }

      // ============================================================
      // ✅ 适配 7.1.1 版本：使用 tokenString
      // ============================================================
      String tokenToSend = '';

      // 在 7.1.1 中，Access Token 和 OIDC Token (Limited Login)
      // 通常都通过 accessToken.tokenString 返回。
      // 后端 Edge Function 会自动通过双通道验证来识别它。
      final AccessToken? accessTokenObj = result.accessToken;

      if (accessTokenObj != null) {
        // 核心修复：旧版本字段名为 tokenString，而不是 token
        tokenToSend = accessTokenObj.tokenString;
      } else {
        debugPrint('[FacebookAuth] ❌ No access token found in result');
        return false;
      }

      debugPrint('[FacebookAuth] 🔑 Token length: ${tokenToSend.length}');
      debugPrint('[FacebookAuth] 🔑 Token preview: ${tokenToSend.substring(0, min(30, tokenToSend.length))}...');

      debugPrint('[FacebookAuth] 🔄 Calling Edge Function...');

      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
          'apikey': _anonKey,
        },
        body: json.encode({
          'accessToken': tokenToSend, // 发送获取到的 Token 字符串
        }),
      );

      debugPrint('[FacebookAuth] Edge Function response: ${response.statusCode}');

      if (response.statusCode != 200) {
        // 尝试解析错误信息
        try {
          final error = json.decode(response.body);
          debugPrint('[FacebookAuth] ❌ Edge Function error (${response.statusCode}): $error');
        } catch (_) {
          debugPrint('[FacebookAuth] ❌ Edge Function error raw: ${response.body}');
        }
        return false;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('[FacebookAuth] ✅ Edge Function returned success');

      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || password == null) {
        debugPrint('[FacebookAuth] ❌ Critical: Email or Password missing in response');
        return false;
      }

      debugPrint('[FacebookAuth] 🔑 Got credentials for: $email');
      debugPrint('[FacebookAuth] 🔐 Signing in with Supabase...');

      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (authResponse.session == null) {
        debugPrint('[FacebookAuth] ❌ Failed to create session');
        return false;
      }

      debugPrint('[FacebookAuth] ✅ Supabase session created successfully');
      debugPrint('[FacebookAuth] User: ${authResponse.user?.id}');

      return true;

    } catch (e, stackTrace) {
      debugPrint('[FacebookAuth] ❌ Error: $e');
      debugPrint('[FacebookAuth] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await FacebookAuth.instance.logOut();
      await _supabase.auth.signOut();
      debugPrint('[FacebookAuth] ✅ Signed out successfully');
    } catch (e) {
      debugPrint('[FacebookAuth] ❌ Sign out error: $e');
      rethrow;
    }
  }
}