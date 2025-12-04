// lib/services/oauth_service.dart
//
// 轻量封装：三方登录统一从 OAuthEntry 走；
// - Google：带 prompt=select_account，便于切换账号
// - Facebook：仅 Web 传 display=popup，移动端一律不传（避免“双弹窗”）
// - Apple：默认 scopes 走系统流程

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sf;
import 'package:swaply/services/oauth_entry.dart';

class OAuthService {
  OAuthService._();

  static Future<void> signInWithGoogle() async {
    await OAuthEntry.signIn(
      sf.OAuthProvider.google,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  static Future<void> signInWithFacebook() async {
    await OAuthEntry.signIn(
      sf.OAuthProvider.facebook,
      scopes: 'public_profile,email',
      // ✅ 仅 Web 才传 popup。移动端不传，底层也会再次净化。
      queryParams: kIsWeb ? const {'display': 'popup'} : null,
    );
  }

  static Future<void> signInWithApple() async {
    await OAuthEntry.signIn(sf.OAuthProvider.apple);
  }
}
