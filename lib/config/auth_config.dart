// lib/config/auth_config.dart

import 'package:flutter/foundation.dart' show kIsWeb;

/// ✅ 移动端使用自定义 URL Scheme（ASWebAuthenticationSession + Chrome Custom Tabs）
/// ✅ Web 端使用 HTTPS 回调
///
/// 配置提示：
///   • Supabase Dashboard → Authentication → URL Configuration:
///     - 添加: swaply://login-callback （移动端 OAuth）
///     - 添加: https://swaply.cc/auth/callback （Web OAuth）
///     - 添加: https://swaply.cc/reset-password （密码重置）
///   • iOS: Info.plist 已配置 swaply scheme
///   • Android: AndroidManifest.xml 需要添加 intent-filter（待配置）

/// ✅ OAuth 回调（移动端）
const String kAuthMobileRedirectUri = 'swaply://login-callback';

/// ✅ OAuth 回调（Web 端）
const String kAuthWebRedirectUri = 'https://swaply.cc/auth/callback';

/// ✅ 向后兼容：统一的 OAuth 回调 URL（优先使用移动端配置）
/// 注意：这是为了兼容旧代码，新代码应该使用 getAuthRedirectUri()
const String kAuthRedirectUri = kAuthMobileRedirectUri;

/// ✅ 密码重置回调（继续使用 HTTPS，因为是邮件链接）
const String kResetPasswordRedirectUri = 'https://swaply.cc/reset-password';
const String kResetPasswordWebRedirectUri = 'https://swaply.cc/reset-password';

/// ✅ 动态获取当前平台的 OAuth 回调
String getAuthRedirectUri() {
  return kIsWeb ? kAuthWebRedirectUri : kAuthMobileRedirectUri;
}

/// ✅ 动态获取当前平台的密码重置回调
String getResetPasswordRedirectUri() {
  return kIsWeb ? kResetPasswordWebRedirectUri : kResetPasswordRedirectUri;
}