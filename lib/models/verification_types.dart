// lib/models/verification_types.dart
//
// 本文件只负责 “徽章类型 ↔ DB 字符串” 的映射与展示用工具。
// ✅ 不在这里决定“是否已认证”；最终判定请使用
//    lib/utils/verification_utils.dart 的 computeIsVerified / computeBadgeType。
// ✅ 支持旧/新命名：verified/blue、official/government、premium/gold/business
// ✅ 兼容旧工具类 API：VerificationBadge.getVerificationTypeFromUser(...)
// ✅ 兼容历史方法名：fromString(raw) -> fromRaw(raw)

enum VerificationBadgeType {
  // 通用
  none,

  // —— 旧名字（向后兼容）
  verified, // ≈ blue/basic
  official, // ≈ government/官方
  premium, // ≈ gold/business/付费

  // —— 新名字（可在新代码里用）
  blue,
  gold,
  business,
  government,
}

class VerificationBadgeUtil {
  /// 将字符串（DB 的 verification_type）映射成枚举。
  /// - 大小写不敏感；
  /// - 未知/空/none -> VerificationBadgeType.none
  static VerificationBadgeType fromRaw(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
    // === 基础已验证 ===
      case 'verified':
      case 'blue':
      case 'basic':
      case 'blue_verified':
      case 'blue-check':
        return VerificationBadgeType.verified;

    // === 官方 ===
      case 'official':
      case 'government':
      case 'gov':
        return VerificationBadgeType.official;

    // === 付费 / 高级 ===
      case 'premium':
      case 'gold':
        return VerificationBadgeType.premium;

    // === 商业 ===
      case 'business':
      case 'biz':
      case 'pro':
      case 'enterprise':
        return VerificationBadgeType.business;

    // === 无 ===
      case 'none':
      case '':
      default:
        return VerificationBadgeType.none;
    }
  }

  /// 兼容历史命名
  static VerificationBadgeType fromString(String? raw) => fromRaw(raw);

  /// 将任意枚举转为**规范的 DB 值**（仅当需要写库时使用）
  /// 说明：
  /// - verified/blue/basic -> 'verified'
  /// - official/government  -> 'official'
  /// - premium/gold         -> 'premium'
  /// - business/biz/pro     -> 'business'
  /// - none                 -> 'none'
  static String toDbValue(VerificationBadgeType t) {
    switch (t) {
      case VerificationBadgeType.verified:
      case VerificationBadgeType.blue:
        return 'verified';
      case VerificationBadgeType.official:
      case VerificationBadgeType.government:
        return 'official';
      case VerificationBadgeType.premium:
      case VerificationBadgeType.gold:
        return 'premium';
      case VerificationBadgeType.business:
        return 'business';
      case VerificationBadgeType.none:
        return 'none';
    }
  }

  /// 从用户/资料 Map 中读取“徽章类型”。
  /// ✅ [MODIFIED] 优先级：
  ///    1. 检查 `verification_type` 字段。
  ///    2. 若无，回退检查 `is_official` (布尔)。
  ///    3. 若仍无，回退检查 `email/phone_verified_at` (基础认证)。
  /// ❌ 不在此处判定“是否已认证”（由 verification_utils 决定）。
  static VerificationBadgeType getVerificationTypeFromUser(
      Map<String, dynamic>? userOrProfile,
      ) {
    if (userOrProfile == null) return VerificationBadgeType.none;

    // 既支持直接传 profile，也兼容外层包了一层 { profile: {...} } 的结构
    final m = Map<String, dynamic>.from(userOrProfile);
    final profileVal = m['profile'];
    final Map<String, dynamic> p =
    (profileVal is Map) ? Map<String, dynamic>.from(profileVal) : m;

    // 1. 优先检查 'verification_type' 字段
    final raw = (p['verification_type'] ?? '').toString();
    final type = fromRaw(raw);
    if (type != VerificationBadgeType.none) return type;

    // 2. 其次，兜底检查 'is_official' (兼容旧数据)
    final isOfficial = p['is_official'] == true;
    if (isOfficial) return VerificationBadgeType.official;

    // 3. ✅ [ADDED] 再次，兜底检查 email/phone (用于公开RPC判断基础认证)
    if (p['email_verified_at'] != null || p['phone_verified_at'] != null) {
      return VerificationBadgeType.verified;
    }

    // 4. 均无，返回 none
    return VerificationBadgeType.none;
  }

  /// 把任意枚举规整到三档（旧名字），便于 UI 统一处理
  static VerificationBadgeType normalize(VerificationBadgeType t) {
    switch (t) {
      case VerificationBadgeType.official:
      case VerificationBadgeType.government:
        return VerificationBadgeType.official;
      case VerificationBadgeType.premium:
      case VerificationBadgeType.business:
      case VerificationBadgeType.gold:
        return VerificationBadgeType.premium;
      case VerificationBadgeType.verified:
      case VerificationBadgeType.blue:
        return VerificationBadgeType.verified;
      case VerificationBadgeType.none:
        return VerificationBadgeType.none;
    }
  }

  /// 是否将该“类型”视为“有徽章”（用于展示层，**不是最终认证判断**）
  static bool isVerifiedType(VerificationBadgeType t) =>
      t != VerificationBadgeType.none;

  /// 便捷标签（可选）
  static String label(VerificationBadgeType t) {
    switch (t) {
      case VerificationBadgeType.none:
        return 'Not verified';
      case VerificationBadgeType.verified:
      case VerificationBadgeType.blue:
        return 'Verified';
      case VerificationBadgeType.official:
      case VerificationBadgeType.government:
        return 'Official';
      case VerificationBadgeType.premium:
      case VerificationBadgeType.gold:
        return 'Premium';
      case VerificationBadgeType.business:
        return 'Business';
    }
  }
}

/// 兼容旧 API：vt.VerificationBadge.getVerificationTypeFromUser(...)
class VerificationBadge {
  static VerificationBadgeType getVerificationTypeFromUser(
      Map<String, dynamic>? userOrProfile,
      ) {
    return VerificationBadgeUtil.getVerificationTypeFromUser(userOrProfile);
  }
}

/// 便捷判断（可选，用 if/else 时更省事）
extension VerificationX on VerificationBadgeType {
  bool get isOfficial =>
      this == VerificationBadgeType.official ||
          this == VerificationBadgeType.government;

  bool get isPremium =>
      this == VerificationBadgeType.premium ||
          this == VerificationBadgeType.business ||
          this == VerificationBadgeType.gold;

  bool get isVerifiedBasic =>
      this == VerificationBadgeType.verified ||
          this == VerificationBadgeType.blue;

  /// “有徽章”即非 none —— 仅用于展示层
  bool get isAnyVerified => this != VerificationBadgeType.none;

  /// 转为规范 DB 值（写库时可用）
  String get dbValue => VerificationBadgeUtil.toDbValue(this);
}