// lib/config/auth_config.dart

/// ✅ 统一使用同一个回调：cc.swaply.app://login-callback
///   - Android: AndroidManifest.xml 里必须有
///       <data android:scheme="cc.swaply.app" android:host="login-callback" />
///   - iOS: Info.plist -> CFBundleURLTypes 的 URLSchemes 里包含 "cc.swaply.app"
///   - Supabase Dashboard -> Authentication -> URL Configuration
///       Redirect URLs 需包含本 Scheme（以及 HTTPS 回调）
///
/// Web/通用链接回调保持 https:
const String kAuthRedirectUri = 'cc.swaply.app://login-callback';
const String kAuthWebRedirectUri = 'https://swaply.cc/auth/callback';
