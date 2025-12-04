// lib/widgets/verification_badge.dart
import 'package:flutter/material.dart';
import 'package:swaply/models/verification_types.dart'
    as vt; // 只 import，不 export

/// 认证徽标（叠在头像右下角的小圆图标）
/// - 官方：蓝标（verified_rounded）
/// - 基础：绿标（verified_user_rounded）
/// - 其它：保持原有颜色语义
class VerificationBadge extends StatelessWidget {
  final vt.VerificationBadgeType type;
  final double size;
  final bool showBorder;

  const VerificationBadge({
    super.key,
    required this.type,
    this.size = 18,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    if (type == vt.VerificationBadgeType.none) {
      return const SizedBox.shrink();
    }

    // 圆形彩色底 + 白色图标
    final badge = _buildFilledBadge(type, size);

    if (!showBorder) return badge;

    // 外圈白边 + 轻阴影（不改变对外 API）
    return Container(
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: size * 0.6,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: badge,
    );
  }

  // ====== 对外静态工具（保持名字不变，避免其它文件报错） ======

  static IconData iconOf(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.none:
        return Icons.circle_outlined;

      // 官方/政府（老：official，新：government）
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        return Icons.verified_rounded; // ✅ 官方：蓝标图标

      // 基础蓝勾（老：verified，新：blue）
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        return Icons.verified_user_rounded; // ✅ 基础：绿标图标

      // 付费/金标/商家（老：premium，新：gold/business）
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
        return Icons.workspace_premium_rounded;

      case vt.VerificationBadgeType.business:
        return Icons.apartment_rounded;

      default:
        // 理论到不了这里，但为压分析器，兜底按未认证处理
        return Icons.circle_outlined;
    }
  }

  /// 单色主色（给 Chip、文字等用）。内部取渐变的第一色，保持兼容。
  static Color colorOf(vt.VerificationBadgeType type) {
    return _paletteOf(type).first;
  }

  static String labelOf(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.none:
        return 'Unverified';

      // 官方/政府（老：official，新：government）
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        return 'Official';

      // 基础蓝勾（老：verified，新：blue）
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        return 'Verified';

      // 付费/金标（老：premium，新：gold）
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
        return 'Premium';

      // 商家
      case vt.VerificationBadgeType.business:
        return 'Business';

      default:
        // 理论到不了这里，但为压分析器，兜底按未认证处理
        return 'Unverified';
    }
  }

  /// 从 user / profiles 风格结构推断认证类型
  /// ✅ 直接调用 VerificationBadgeUtil，不做任何本地判断
  static vt.VerificationBadgeType getVerificationTypeFromUser(dynamic user) {
    // 将输入转换为 Map<String, dynamic> 格式
    Map<String, dynamic>? userOrProfileMap;

    if (user is Map<String, dynamic>) {
      // 如果已经是 Map，直接使用
      userOrProfileMap = user;

      // 如果有 user_metadata 或 app_metadata，将其内容合并到顶层
      if (user['user_metadata'] is Map<String, dynamic>) {
        userOrProfileMap = {
          ...user,
          ...(user['user_metadata'] as Map<String, dynamic>),
        };
      } else if (user['app_metadata'] is Map<String, dynamic>) {
        userOrProfileMap = {
          ...user,
          ...(user['app_metadata'] as Map<String, dynamic>),
        };
      }
    } else {
      // 尝试从对象中提取属性
      try {
        userOrProfileMap = {};

        // 尝试读取 metadata
        final um = user?.userMetadata;
        if (um is Map<String, dynamic>) {
          userOrProfileMap.addAll(um);
        }

        final am = user?.appMetadata;
        if (am is Map<String, dynamic>) {
          userOrProfileMap.addAll(am);
        }

        // 尝试直接读取 verification_type（这才是关键字段）
        try {
          if (user?.verification_type != null) {
            userOrProfileMap['verification_type'] = user.verification_type;
          }
        } catch (_) {
          // 忽略属性不存在的错误
        }

        // ✅ 注意：不再读取 email_verified 或 is_verified
        // 这些字段不应该影响徽章显示
      } catch (_) {
        // 如果所有尝试都失败，使用空 Map
        userOrProfileMap = {};
      }
    }

    // ✅ 直接调用统一的工具函数进行判断
    // 只根据 verification_type 字段决定徽章类型
    return vt.VerificationBadgeUtil.getVerificationTypeFromUser(
        userOrProfileMap);
  }

  // ====== 内部实现 ======

  /// 返回各类型的主配色（两色用于圆形渐变）
  static List<Color> _paletteOf(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.none:
        return const [Color(0xFF9E9E9E), Color(0xFF9E9E9E)];

      // 官方/政府（老：official，新：government）
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        // ✅ 官方：蓝
        return const [Color(0xFF2D7CFF), Color(0xFF2979FF)];

      // 基础蓝勾（老：verified，新：blue）
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        // ✅ 基础：绿
        return const [Color(0xFF28A745), Color(0xFF34C759)];

      // 付费/金标（老：premium，新：gold）
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
        return const [Color(0xFFFFB300), Color(0xFFF59E0B)]; // Amber

      // 商家
      case vt.VerificationBadgeType.business:
        return const [Color(0xFF7C4DFF), Color(0xFF6366F1)]; // Indigo

      default:
        // 理论到不了这里，但为压分析器，兜底按未认证处理
        return const [Color(0xFF9E9E9E), Color(0xFF9E9E9E)];
    }
  }

  /// 圆形彩底 + 白色图标（用于头像角标）
  Widget _buildFilledBadge(vt.VerificationBadgeType type, double size) {
    final colors = _paletteOf(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors),
      ),
      child: Center(
        child: Icon(
          iconOf(type),
          size: size * 0.62,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 状态 Chip（兼容 showIcon 参数）
class VerificationStatusChip extends StatelessWidget {
  final vt.VerificationBadgeType type;
  final bool dense;
  final bool showIcon;

  const VerificationStatusChip({
    super.key,
    required this.type,
    this.dense = false,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = VerificationBadge.colorOf(type);
    final text = VerificationBadge.labelOf(type);

    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon)
            Icon(
              VerificationBadge.iconOf(type),
              size: dense ? 14 : 16,
              color: color,
            ),
          if (showIcon) SizedBox(width: dense ? 4 : 6),
          Text(
            text,
            style: TextStyle(
              fontSize: dense ? 12 : 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 兼容老调用方式
vt.VerificationBadgeType getVerificationTypeFromUser(dynamic user) =>
    VerificationBadge.getVerificationTypeFromUser(user);
