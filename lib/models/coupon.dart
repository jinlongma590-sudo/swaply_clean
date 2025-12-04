// lib/models/coupon.dart - Complete English version with full compatibility + Welcome Type + New Fields
import 'package:flutter/foundation.dart';

/// Coupon Type Enum - Compatible version with core types + legacy aliases + welcome
enum CouponType {
  // === Core Coupon Types (New) ===
  trending('trending', 'Trending (Homepage)',
      'Trending (Homepage)'), // Homepage trending section
  category('category', 'Category Pin',
      'Category Pin'), // Category page pinned display
  featured('featured', 'Search/Popular Pin',
      'Search/Popular Pin'), // Search top & appear in Popular

  // === Legacy Types for Compatibility (Deprecated / Aliases) ===
  @Deprecated('Use trending instead')
  trendingPin('trending', 'Trending (Homepage)',
      'Trending (Homepage)'), // Maps to trending
  @Deprecated('Use category instead')
  pinned('category', 'Category Pin', 'Category Pin'), // Maps to category
  @Deprecated('Use featured instead')
  premium('category', 'Category Pin', 'Category Pin'), // Maps to category
  @Deprecated('Use featured instead')
  boost('boost', 'Search/Popular Pin',
      'Search/Popular Pin'), // Alias; actual -> featured

  // === Reward Source Identifiers (actual grant is one of core types) ===
  registerBonus('register_bonus', 'Welcome Bonus', 'Welcome Bonus'),
  activityBonus('activity_bonus', 'Activity Bonus', 'Activity Bonus'),
  referralBonus('referral_bonus', 'Referral Bonus', 'Referral Bonus'),

  // === Welcome Type ===
  welcome('welcome', 'Welcome Coupon', 'Welcome Coupon'); // welcome coupon

  const CouponType(this.value, this.displayNameEn, this.displayNameZh);

  final String value;
  final String displayNameEn;
  final String displayNameZh;

  // Compatible conversion from old types
  static CouponType fromString(String? value) {
    if (value == null || value.isEmpty) {
      return CouponType.category;
    }

    try {
      // Direct match for known values
      for (final type in CouponType.values) {
        if (type.value == value) {
          return type;
        }
      }

      // Compatibility mapping for old/alias values
      switch (value.toLowerCase()) {
        case 'trending_pin':
        case 'trending':
          return CouponType.trending;

        case 'pinned':
        case 'premium':
        case 'category':
          return CouponType.category;

        case 'featured':
          return CouponType.featured;

        case 'boost': // legacy alias we still accept
          return CouponType.boost;

        case 'welcome':
          return CouponType.welcome;

        // Reward identifiers
        case 'register_bonus':
          return CouponType.registerBonus;
        case 'activity_bonus':
          return CouponType.activityBonus;
        case 'referral_bonus':
          return CouponType.referralBonus;

        default:
          return CouponType.category;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[CouponType] Conversion error: $e, input value: $value');
      }
      return CouponType.category;
    }
  }

  /// Whether this is a free reward coupon (identifies source, not actual coupon type)
  bool get isFreeReward {
    return [
      CouponType.registerBonus,
      CouponType.activityBonus,
      CouponType.referralBonus,
      CouponType.welcome,
    ].contains(this);
  }

  /// Whether this is an actual usable coupon type (core types + legacy alias)
  bool get isActualCouponType {
    return [
      CouponType.trending,
      CouponType.category,
      CouponType.featured,
      CouponType.boost, // alias kept for compatibility
    ].contains(this);
  }

  /// Whether this is a deprecated legacy type (maps to core types)
  bool get isDeprecatedType {
    return [
      CouponType.trendingPin,
      CouponType.pinned,
      CouponType.premium,
      CouponType.boost,
    ].contains(this);
  }

  /// Get the actual core coupon type (maps legacy/alias types to new types)
  CouponType get actualCouponType {
    switch (this) {
      case CouponType.trendingPin:
        return CouponType.trending;
      case CouponType.pinned:
      case CouponType.premium:
        return CouponType.category;
      case CouponType.boost:
        return CouponType.featured;
      case CouponType.trending:
      case CouponType.category:
      case CouponType.featured:
        return this; // Already core type
      case CouponType.welcome:
        return CouponType
            .category; // Welcome behaves like category pin by default
      case CouponType.registerBonus:
      case CouponType.activityBonus:
      case CouponType.referralBonus:
        return CouponType
            .category; // rewards map by business logic when granted
    }
  }

  /// Get coupon color theme
  int get colorValue {
    switch (this) {
      // Core types
      case CouponType.trending:
        return 0xFFFF6B35; // Orange-red - Trending
      case CouponType.category:
        return 0xFF2196F3; // Blue - Pinned
      case CouponType.featured:
        return 0xFF9C27B0; // Purple - Search/Popular

      // Legacy types (mapped to core type colors)
      case CouponType.trendingPin:
        return 0xFFFF6B35;
      case CouponType.pinned:
      case CouponType.premium:
        return 0xFF2196F3;
      case CouponType.boost:
        return 0xFF9C27B0;

      // Reward identifiers
      case CouponType.registerBonus:
        return 0xFF4CAF50; // Green
      case CouponType.activityBonus:
        return 0xFFFF9800; // Orange
      case CouponType.referralBonus:
        return 0xFFE91E63; // Pink
      case CouponType.welcome:
        return 0xFF4CAF50; // Green
    }
  }

  /// Get coupon icon name
  String get iconName {
    switch (this) {
      // Core types
      case CouponType.trending:
        return 'local_fire_department';
      case CouponType.category:
        return 'push_pin';
      case CouponType.featured:
        return 'rocket_launch';

      // Legacy types
      case CouponType.trendingPin:
        return 'local_fire_department';
      case CouponType.pinned:
      case CouponType.premium:
        return 'push_pin';
      case CouponType.boost:
        return 'rocket_launch';

      // Reward identifiers
      case CouponType.registerBonus:
        return 'card_giftcard';
      case CouponType.activityBonus:
        return 'task_alt';
      case CouponType.referralBonus:
        return 'group_add';
      case CouponType.welcome:
        return 'card_giftcard';
    }
  }

  /// Get coupon function description
  String get functionDescription {
    switch (this) {
      // Core types
      case CouponType.trending:
        return 'Pinned on the homepage Trending section';
      case CouponType.category:
        return 'Pinned at the top of a category page';
      case CouponType.featured:
        return 'Top in search results and appear in Popular';

      // Legacy types (mapped)
      case CouponType.trendingPin:
        return 'Pinned on the homepage Trending section';
      case CouponType.pinned:
      case CouponType.premium:
        return 'Pinned at the top of a category page';
      case CouponType.boost:
        return 'Top in search results and appear in Popular';

      // Reward identifiers
      case CouponType.registerBonus:
        return 'New user exclusive reward';
      case CouponType.activityBonus:
        return 'Active user reward';
      case CouponType.referralBonus:
        return 'Friend referral reward';
      case CouponType.welcome:
        return 'Welcome bonus for new users';
    }
  }

  /// Whether daily quota check is needed
  bool get needsQuotaCheck {
    switch (this) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return true;
      case CouponType.category:
      case CouponType.featured:
      case CouponType.boost:
      case CouponType.pinned:
      case CouponType.premium:
      case CouponType.registerBonus:
      case CouponType.activityBonus:
      case CouponType.referralBonus:
      case CouponType.welcome:
        return false;
    }
  }

  /// Get display location description
  String get displayLocation {
    switch (this) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return 'Homepage Trending';
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.premium:
        return 'Category Page Top';
      case CouponType.featured:
      case CouponType.boost:
        return 'Search Results & Popular';
      case CouponType.registerBonus:
      case CouponType.activityBonus:
      case CouponType.referralBonus:
      case CouponType.welcome:
        return 'Reward Identifier';
    }
  }
}

/// Coupon Status Enum
enum CouponStatus {
  active('active', 'Active', 'Active'),
  used('used', 'Used', 'Used'),
  expired('expired', 'Expired', 'Expired'),
  revoked('revoked', 'Revoked', 'Revoked');

  const CouponStatus(this.value, this.displayNameEn, this.displayNameZh);

  final String value;
  final String displayNameEn;
  final String displayNameZh;

  static CouponStatus fromString(String? value) {
    if (value == null || value.isEmpty) {
      return CouponStatus.active;
    }

    try {
      for (final status in CouponStatus.values) {
        if (status.value == value) {
          return status;
        }
      }
      return CouponStatus.active;
    } catch (e) {
      if (kDebugMode) {
        print('[CouponStatus] Conversion error: $e, input value: $value');
      }
      return CouponStatus.active;
    }
  }
}

/// Coupon Model Class - with new fields
class CouponModel {
  final String id;
  final String code;
  final String userId;
  final CouponType type;
  final CouponStatus status;
  final String title;
  final String description;
  final int durationDays;
  final int maxUses;
  final int usedCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final String? listingId;
  final Map<String, dynamic>? metadata;

  // New fields
  final String? category; // 'reward', 'pinning', 'boost', etc.
  final String? source; // 'signup', 'purchase', 'task', etc.
  final int? pinDays; // pin days
  final String? pinScope; // 'category', 'home', 'search', etc.

  CouponModel({
    required this.id,
    required this.code,
    required this.userId,
    required this.type,
    required this.status,
    required this.title,
    required this.description,
    required this.durationDays,
    this.maxUses = 1,
    this.usedCount = 0,
    required this.createdAt,
    required this.expiresAt,
    this.usedAt,
    this.listingId,
    this.metadata,
    // new fields
    this.category,
    this.source,
    this.pinDays,
    this.pinScope,
  });

  /// Create CouponModel from Map
  factory CouponModel.fromMap(Map<String, dynamic> map) {
    try {
      int safeInt(dynamic value, int defaultValue) {
        if (value == null) return defaultValue;
        if (value is int) return value;
        if (value is double) return value.toInt();
        if (value is String) {
          return int.tryParse(value) ?? defaultValue;
        }
        return defaultValue;
      }

      DateTime safeDateTime(dynamic value, DateTime defaultValue) {
        if (value == null) return defaultValue;
        if (value is DateTime) return value;
        if (value is String && value.isNotEmpty) {
          return DateTime.tryParse(value) ?? defaultValue;
        }
        return defaultValue;
      }

      DateTime? safeNullableDateTime(dynamic value) {
        if (value == null) return null;
        if (value is DateTime) return value;
        if (value is String && value.isNotEmpty) {
          return DateTime.tryParse(value);
        }
        return null;
      }

      String? safeString(dynamic value) {
        if (value == null) return null;
        return value.toString();
      }

      final now = DateTime.now();

      return CouponModel(
        id: map['id']?.toString() ?? '',
        code: map['code']?.toString() ?? '',
        userId: map['user_id']?.toString() ?? '',
        type: CouponType.fromString(map['type']?.toString()),
        status: CouponStatus.fromString(map['status']?.toString()),
        title: map['title']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        durationDays: safeInt(map['duration_days'], 7),
        maxUses: safeInt(map['max_uses'], 1),
        usedCount: safeInt(map['used_count'], 0),
        createdAt: safeDateTime(map['created_at'], now),
        expiresAt:
            safeDateTime(map['expires_at'], now.add(const Duration(days: 7))),
        usedAt: safeNullableDateTime(map['used_at']),
        listingId: map['listing_id']?.toString(),
        metadata: map['metadata'] as Map<String, dynamic>?,
        // new fields
        category: safeString(map['category']),
        source: safeString(map['source']),
        pinDays: safeInt(map['pin_days'], 0) == 0
            ? null
            : safeInt(map['pin_days'], 0),
        pinScope: safeString(map['pin_scope']),
      );
    } catch (e) {
      if (kDebugMode) {
        print('[CouponModel] Parse error: $e');
        print('[CouponModel] Data: $map');
      }

      // Fallback safe model
      final now = DateTime.now();
      return CouponModel(
        id: map['id']?.toString() ?? 'error_${now.millisecondsSinceEpoch}',
        code: map['code']?.toString() ?? 'ERROR',
        userId: map['user_id']?.toString() ?? '',
        type: CouponType.category, // Safe default
        status: CouponStatus.active,
        title: 'Parse Error',
        description: 'Coupon data parse error',
        durationDays: 7,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );
    }
  }

  /// Convert to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'user_id': userId,
      'type': type.value,
      'status': status.value,
      'title': title,
      'description': description,
      'duration_days': durationDays,
      'max_uses': maxUses,
      'used_count': usedCount,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'used_at': usedAt?.toIso8601String(),
      'listing_id': listingId,
      'metadata': metadata,
      // new fields
      'category': category,
      'source': source,
      'pin_days': pinDays,
      'pin_scope': pinScope,
    };
  }

  /// Create copy
  CouponModel copyWith({
    String? id,
    String? code,
    String? userId,
    CouponType? type,
    CouponStatus? status,
    String? title,
    String? description,
    int? durationDays,
    int? maxUses,
    int? usedCount,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? usedAt,
    String? listingId,
    Map<String, dynamic>? metadata,
    String? category,
    String? source,
    int? pinDays,
    String? pinScope,
  }) {
    return CouponModel(
      id: id ?? this.id,
      code: code ?? this.code,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      status: status ?? this.status,
      title: title ?? this.title,
      description: description ?? this.description,
      durationDays: durationDays ?? this.durationDays,
      maxUses: maxUses ?? this.maxUses,
      usedCount: usedCount ?? this.usedCount,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      usedAt: usedAt ?? this.usedAt,
      listingId: listingId ?? this.listingId,
      metadata: metadata ?? this.metadata,
      // new fields
      category: category ?? this.category,
      source: source ?? this.source,
      pinDays: pinDays ?? this.pinDays,
      pinScope: pinScope ?? this.pinScope,
    );
  }

  // ========== Convenient getters ==========

  bool get isUsable =>
      status == CouponStatus.active && !isExpired && usedCount < maxUses;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isUsedUp => usedCount >= maxUses;

  int get remainingUses => (maxUses - usedCount).clamp(0, maxUses);

  String get formattedExpiryDate =>
      '${expiresAt.day.toString().padLeft(2, '0')}/${expiresAt.month.toString().padLeft(2, '0')}/${expiresAt.year}';

  int get daysUntilExpiry {
    if (isExpired) return 0;
    return expiresAt.difference(DateTime.now()).inDays;
  }

  String get statusDescription {
    if (isExpired) return 'Expired';
    if (isUsedUp) return 'Used Up';
    if (status == CouponStatus.used) return 'Used';
    if (status == CouponStatus.revoked) return 'Revoked';
    return 'Usable';
  }

  int get statusColor {
    if (isExpired || status == CouponStatus.expired) return 0xFF9E9E9E;
    if (isUsedUp || status == CouponStatus.used) return 0xFF4CAF50;
    if (status == CouponStatus.revoked) return 0xFFF44336;
    if (daysUntilExpiry <= 1) return 0xFFFF9800;
    return type.colorValue;
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return formattedExpiryDate;
    }
  }

  String get expiryStatusText {
    if (isExpired) return 'Expired';
    if (daysUntilExpiry == 0) return 'Expires today';
    if (daysUntilExpiry == 1) return 'Expires tomorrow';
    if (daysUntilExpiry <= 3) return 'Expires in ${daysUntilExpiry}d';
    if (daysUntilExpiry <= 7) return 'Expires in 1w';
    if (daysUntilExpiry <= 30) {
      return 'Expires in ${(daysUntilExpiry / 7).ceil()}w';
    }
    return 'Expires in ${(daysUntilExpiry / 30).ceil()}mo';
  }

  String get usageProgressText {
    if (maxUses == 1) return usedCount > 0 ? 'Used' : 'Unused';
    return '$usedCount/$maxUses used';
  }

  bool get isRewardCoupon => type.isFreeReward;

  bool get isWelcome => type == CouponType.welcome;

  bool get canPin {
    return type == CouponType.welcome ||
        type == CouponType.trending ||
        type == CouponType.category ||
        type == CouponType.trendingPin ||
        type == CouponType.pinned ||
        type == CouponType.featured ||
        type == CouponType.premium ||
        type == CouponType.boost;
  }

  int get effectivePinDays {
    if (pinDays != null && pinDays! > 0) return pinDays!;
    if (type == CouponType.welcome) return 3;
    return 7;
  }

  bool get isRewardLike => type == CouponType.welcome || type.isFreeReward;

  int get priority {
    if (!isUsable) return 0;

    switch (type) {
      // Core type priority
      case CouponType.trending:
      case CouponType.trendingPin:
        return 100; // Highest
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.premium:
        return 80;
      case CouponType.featured:
      case CouponType.boost:
        return 70;

      // Reward identifiers
      case CouponType.registerBonus:
        return 50;
      case CouponType.activityBonus:
        return 40;
      case CouponType.referralBonus:
        return 30;
      case CouponType.welcome:
        return 55;
    }
  }

  String get scopeDescription => type.functionDescription;

  @override
  String toString() =>
      'CouponModel(id: $id, code: $code, type: ${type.value}, status: ${status.value}, title: $title)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CouponModel &&
        other.id == id &&
        other.code == code &&
        other.userId == userId &&
        other.type == type &&
        other.status == status;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      code.hashCode ^
      userId.hashCode ^
      type.hashCode ^
      status.hashCode;
}

// Keep original other class definitions to ensure interface compatibility
class PinnedAdConfig {
  final int maxPinnedPerCategory;
  final int maxTrendingPerDay;
  final int defaultDurationDays;
  final Map<String, int> categoryLimits;

  const PinnedAdConfig({
    this.maxPinnedPerCategory = 5,
    this.maxTrendingPerDay = 20,
    this.defaultDurationDays = 7,
    this.categoryLimits = const {},
  });

  int getLimitForCategory(String category) {
    return categoryLimits[category] ?? maxPinnedPerCategory;
  }
}

class CouponUsageResult {
  final bool success;
  final String message;
  final String? errorCode;
  final CouponModel? updatedCoupon;
  final Map<String, dynamic>? extraData;

  const CouponUsageResult({
    required this.success,
    required this.message,
    this.errorCode,
    this.updatedCoupon,
    this.extraData,
  });

  factory CouponUsageResult.success({
    String? message,
    CouponModel? updatedCoupon,
    Map<String, dynamic>? extraData,
  }) {
    return CouponUsageResult(
      success: true,
      message: message ?? 'Operation successful',
      updatedCoupon: updatedCoupon,
      extraData: extraData,
    );
  }

  factory CouponUsageResult.failure({
    required String message,
    String? errorCode,
    Map<String, dynamic>? extraData,
  }) {
    return CouponUsageResult(
      success: false,
      message: message,
      errorCode: errorCode,
      extraData: extraData,
    );
  }
}

class CouponStats {
  final int totalCoupons;
  final int activeCoupons;
  final int usedCoupons;
  final int expiredCoupons;
  final int revokedCoupons;
  final Map<CouponType, int> couponsByType;
  final double usageRate;

  const CouponStats({
    required this.totalCoupons,
    required this.activeCoupons,
    required this.usedCoupons,
    required this.expiredCoupons,
    required this.revokedCoupons,
    required this.couponsByType,
    required this.usageRate,
  });

  factory CouponStats.fromCoupons(List<CouponModel> coupons) {
    final byType = <CouponType, int>{};
    int active = 0, used = 0, expired = 0, revoked = 0;

    for (final coupon in coupons) {
      byType[coupon.type] = (byType[coupon.type] ?? 0) + 1;

      switch (coupon.status) {
        case CouponStatus.active:
          if (coupon.isExpired) {
            expired++;
          } else {
            active++;
          }
          break;
        case CouponStatus.used:
          used++;
          break;
        case CouponStatus.expired:
          expired++;
          break;
        case CouponStatus.revoked:
          revoked++;
          break;
      }
    }

    final usageRate = coupons.isEmpty ? 0.0 : used / coupons.length;

    return CouponStats(
      totalCoupons: coupons.length,
      activeCoupons: active,
      usedCoupons: used,
      expiredCoupons: expired,
      revokedCoupons: revoked,
      couponsByType: byType,
      usageRate: usageRate,
    );
  }
}
