// lib/config.dart
// ✅ Swaply完整配置文件 - 2025版本

/// ======================================================================
/// 数据源配置
/// ======================================================================

/// 是否使用远程数据（生产环境设置为true）
const bool kUseRemoteData = true;

/// 是否上传到远程服务器（生产环境设置为true）
const bool kUploadToRemote = true;

/// ======================================================================
/// Supabase配置
/// ======================================================================

class SupabaseConfig {
  /// Supabase项目URL
  static const String url = 'https://rhckybselarzglkmlyqs.supabase.co';

  /// Supabase匿名密钥
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU';
}

/// ======================================================================
/// 应用配置
/// ======================================================================

class AppConfig {
  /// 应用名称
  static const String appName = 'Swaply';

  /// 应用版本
  static const String version = '1.0.0';

  /// 包名（仅用于显示，实际值在各平台配置文件中）
  static const String packageName = 'com.swaply.app';

  // ═════════════════════════════════════════════════════════════════
  // OAuth / Deep Link 配置（关键配置！）
  // ═════════════════════════════════════════════════════════════════

  /// ✅ OAuth登录回调URL
  /// - 用于Google、Apple等第三方登录
  /// - 必须与以下配置保持一致：
  ///   * iOS Info.plist CFBundleURLSchemes
  ///   * Android AndroidManifest.xml Intent Filter
  ///   * Supabase Dashboard Redirect URLs
  static const String authRedirectUri = 'cc.swaply.app://login-callback';

  /// ✅ 密码重置回调URL（重要！必须正确配置）
  /// - 用于密码重置流程
  /// - 用户点击邮件链接后会先打开这个网页
  /// - 网页会提取token并唤起App
  /// - 必须与Supabase Email Template中的Redirect URL一致
  static const String resetPasswordRedirectUrl = 'https://swaply.cc/reset-password';

  /// 兼容旧字段（保持与authRedirectUri一致）
  static const String oauthRedirectUrl = authRedirectUri;

  // ═════════════════════════════════════════════════════════════════
  // Deep Link Schemes（用于App内导航）
  // ═════════════════════════════════════════════════════════════════

  /// Deep Link基础scheme
  static const String deepLinkScheme = 'cc.swaply.app';

  /// 完整的Deep Link格式示例：
  /// - 密码重置: cc.swaply.app://reset-password?token=xxx
  /// - OAuth回调: cc.swaply.app://login-callback
  /// - 商品详情: cc.swaply.app://listing?id=xxx
  /// - 报价详情: cc.swaply.app://offer?id=xxx

  // ═════════════════════════════════════════════════════════════════
  // Web URLs（用于网页跳转）
  // ═════════════════════════════════════════════════════════════════

  /// 主网站URL
  static const String websiteUrl = 'https://swaply.cc';

  /// API基础URL（如果有单独的API服务器）
  static const String apiBaseUrl = SupabaseConfig.url;
}

/// ======================================================================
/// 上传配置
/// ======================================================================

class UploadConfig {
  /// 单张图片最大大小（5MB）
  static const int maxImageSize = 5 * 1024 * 1024;

  /// 每个商品最多上传图片数
  static const int maxImagesPerListing = 10;

  /// 允许的图片类型
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'webp'];

  /// 图片压缩质量（0-100）
  static const int imageQuality = 80;

  /// 图片最大宽度（压缩后）
  static const int maxImageWidth = 1920;

  /// 图片最大高度（压缩后）
  static const int maxImageHeight = 1920;
}

/// ======================================================================
/// 分页配置
/// ======================================================================

class PaginationConfig {
  /// 默认每页数量
  static const int defaultPageSize = 20;

  /// 最大每页数量
  static const int maxPageSize = 100;

  /// 初始加载数量（首屏）
  static const int initialPageSize = 15;
}

/// ======================================================================
/// 缓存配置
/// ======================================================================

class CacheConfig {
  /// 默认缓存时长
  static const Duration defaultCacheDuration = Duration(minutes: 15);

  /// 商品列表缓存时长
  static const Duration listingsCacheDuration = Duration(minutes: 10);

  /// 用户资料缓存时长
  static const Duration profileCacheDuration = Duration(hours: 1);

  /// 分类数据缓存时长
  static const Duration categoriesCacheDuration = Duration(hours: 24);

  /// 图片缓存最大大小（100MB）
  static const int maxImageCacheSize = 100 * 1024 * 1024;
}

/// ======================================================================
/// Supabase表名
/// ======================================================================

class ApiEndpoints {
  /// 商品表
  static const String listings = 'listings';

  /// 用户资料表
  static const String userProfiles = 'user_profiles';

  /// 收藏表
  static const String favorites = 'favorites';

  /// 购买记录表
  static const String purchases = 'purchases';

  /// 商品浏览记录表
  static const String listingViews = 'listing_views';

  /// 报价表
  static const String offers = 'offers';

  /// 聊天消息表
  static const String messages = 'messages';

  /// 通知表
  static const String notifications = 'notifications';
}

/// ======================================================================
/// Supabase存储桶
/// ======================================================================

class StorageBuckets {
  /// 商品图片
  static const String listingImages = 'listing-images';

  /// 用户头像
  static const String avatars = 'avatars';

  /// 聊天图片
  static const String chatImages = 'chat-images';
}

/// ======================================================================
/// 主题配置
/// ======================================================================

class ThemeConfig {
  /// 主色调（Material Blue）
  static const int primaryColorValue = 0xFF2196F3;

  /// 次要色调（Darker Blue）
  static const int secondaryColorValue = 0xFF1E88E5;

  /// 圆角半径
  static const double borderRadius = 12.0;

  /// 卡片阴影
  static const double cardElevation = 2.0;

  /// 按钮圆角
  static const double buttonBorderRadius = 12.0;

  /// 输入框圆角
  static const double inputBorderRadius = 12.0;
}

/// ======================================================================
/// 环境配置
/// ======================================================================

class Environment {
  /// 是否为生产环境
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');

  /// 是否为开发环境
  static const bool isDevelopment = !isProduction;

  /// 是否启用调试模式
  static const bool isDebugMode = !isProduction;
}

/// ======================================================================
/// 调试配置
/// ======================================================================

class DebugConfig {
  /// 是否启用日志
  static const bool enableLogging = Environment.isDevelopment;

  /// 是否启用网络请求日志
  static const bool enableNetworkLogging = Environment.isDevelopment;

  /// 是否启用错误报告
  static const bool enableErrorReporting = Environment.isProduction;

  /// 是否显示性能监控
  static const bool enablePerformanceMonitoring = Environment.isDevelopment;
}

/// ======================================================================
/// 业务配置
/// ======================================================================

class BusinessConfig {
  /// 密码最小长度
  static const int minPasswordLength = 6;

  /// 用户名最小长度
  static const int minUsernameLength = 3;

  /// 用户名最大长度
  static const int maxUsernameLength = 30;

  /// 商品标题最大长度
  static const int maxListingTitleLength = 100;

  /// 商品描述最大长度
  static const int maxListingDescriptionLength = 1000;

  /// 搜索关键词最小长度
  static const int minSearchKeywordLength = 2;

  /// Token过期时间（秒）- Supabase默认为3600秒（1小时）
  static const int tokenExpirySeconds = 3600;

  /// Refresh Token过期时间（秒）- Supabase默认为604800秒（7天）
  static const int refreshTokenExpirySeconds = 604800;
}

/// ======================================================================
/// 功能开关（Feature Flags）
/// ======================================================================

class FeatureFlags {
  /// 是否启用Google登录
  static const bool enableGoogleLogin = true;

  /// 是否启用Apple登录
  static const bool enableAppleLogin = true;

  /// 是否启用聊天功能
  static const bool enableChat = true;

  /// 是否启用推送通知
  static const bool enablePushNotifications = true;

  /// 是否启用商品收藏
  static const bool enableFavorites = true;

  /// 是否启用报价功能
  static const bool enableOffers = true;

  /// 是否启用搜索功能
  static const bool enableSearch = true;
}

// ═════════════════════════════════════════════════════════════════
// ✅ 配置验证（用于启动时检查）
// ═════════════════════════════════════════════════════════════════

/// 验证所有关键配置是否正确
bool validateConfig() {
  bool isValid = true;

  // 检查Supabase配置
  if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) {
    print('❌ Supabase配置无效');
    isValid = false;
  }

  // 检查重定向URL配置
  if (AppConfig.authRedirectUri.isEmpty) {
    print('❌ OAuth重定向URL未配置');
    isValid = false;
  }

  if (AppConfig.resetPasswordRedirectUrl.isEmpty) {
    print('❌ 密码重置重定向URL未配置');
    isValid = false;
  }

  // 检查Deep Link scheme格式
  if (!AppConfig.authRedirectUri.startsWith(AppConfig.deepLinkScheme)) {
    print('⚠️ OAuth重定向URL与Deep Link scheme不一致');
    print('   OAuth: ${AppConfig.authRedirectUri}');
    print('   Scheme: ${AppConfig.deepLinkScheme}');
  }

  if (isValid) {
    print('✅ 所有配置验证通过');
  }

  return isValid;
}

/// 打印当前配置（调试用）
void printCurrentConfig() {
  print('═══════════════════════════════════════');
  print('🔧 Swaply 配置信息');
  print('═══════════════════════════════════════');
  print('环境: ${Environment.isProduction ? "生产" : "开发"}');
  print('应用名称: ${AppConfig.appName}');
  print('版本: ${AppConfig.version}');
  print('包名: ${AppConfig.packageName}');
  print('───────────────────────────────────────');
  print('Supabase URL: ${SupabaseConfig.url}');
  print('OAuth回调: ${AppConfig.authRedirectUri}');
  print('密码重置: ${AppConfig.resetPasswordRedirectUrl}');
  print('Deep Link: ${AppConfig.deepLinkScheme}');
  print('网站URL: ${AppConfig.websiteUrl}');
  print('═══════════════════════════════════════');
}

