// lib/widgets/verified_avatar.dart
import 'package:flutter/material.dart';
import 'package:swaply/models/verification_types.dart' as vt;
import 'package:swaply/widgets/verification_badge.dart' as vb;

/// 带认证角标的头像组件
class VerifiedAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final vt.VerificationBadgeType verificationType;
  final VoidCallback? onTap;
  final IconData defaultIcon;

  /// 是否在右下角绘制徽章（用于避免某些页面再次叠加导致"双徽章"）
  final bool showBadge;

  /// 徽章是否带白色描边/阴影容器
  final bool badgeHasBorder;

  /// 自定义徽章大小（默认 radius 的一半）
  final double? badgeSize;

  const VerifiedAvatar({
    super.key,
    required this.avatarUrl,
    required this.radius,
    required this.verificationType,
    this.onTap,
    this.defaultIcon = Icons.person,
    this.showBadge = true,
    this.badgeHasBorder = true,
    this.badgeSize,
  });

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(child: _buildAvatarImage());

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: image,
        ),
        if (showBadge && verificationType != vt.VerificationBadgeType.none)
          Positioned(
            right: -2,
            bottom: -2,
            child: vb.VerificationBadge(
              type: verificationType,
              size: badgeSize ?? radius * 0.5,
              showBorder: badgeHasBorder,
            ),
          ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: stack,
    );
  }

  Widget _buildAvatarImage() {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Image.network(
        avatarUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: radius * 2,
        height: radius * 2,
        color: const Color(0xFFE5E7EB),
        child: Icon(
          defaultIcon,
          size: radius * 1.2,
          color: const Color(0xFF6B7280),
        ),
      );
}
