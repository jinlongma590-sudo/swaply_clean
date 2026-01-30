// lib/config/auth_config.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// ✅ OAuth 回调配置
///
/// 配置说明：
/// - 移动端（iOS/Android）：使用自定义 URL Scheme
/// - Web 端：使用 HTTPS 回调
/// - Facebook：使用原生 SDK，不需要 OAuth Deep Link 回调
///
/// Supabase Dashboard 配置：
///   • Authentication → URL Configuration → Redirect URLs:
///     - https://rhckybselarzglkmlyqs.supabase.co/auth/v1/callback
///     - https://swaply.cc/auth/callback
///     - https://swaply.cc/login-callback
///     - https://swaply.cc/reset-password

/// ✅ OAuth 回调（Web 端）
const String kAuthWebRedirectUri = 'https://swaply.cc/auth/callback';

/// ✅ OAuth 回调（移动端 - 通用）
/// 用于需要 Deep Link 回调的 OAuth 提供商（如 Apple）
const String kAuthMobileRedirectUri = 'cc.swaply.app://login-callback';

/// ✅ 向后兼容
const String kAuthRedirectUri = kAuthMobileRedirectUri;

/// ✅ 密码重置回调（继续使用 HTTPS，因为是邮件链接）
const String kResetPasswordRedirectUri = 'https://swaply.cc/reset-password';
const String kResetPasswordWebRedirectUri = 'https://swaply.cc/reset-password';

/// ✅ 动态获取当前平台的 OAuth 回调
/// 用于：Apple、Google 等 OAuth 提供商
/// 注意：Facebook 使用原生 SDK，不需要这个回调
String getAuthRedirectUri() {
  return kIsWeb ? kAuthWebRedirectUri : kAuthMobileRedirectUri;
}

/// ✅ 动态获取当前平台的密码重置回调
String getResetPasswordRedirectUri() {
  return kIsWeb ? kResetPasswordWebRedirectUri : kResetPasswordRedirectUri;
}