// widgets/modern_ui.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// ======= 共享：现代头部 / 卡片 / 徽章 / 剪裁工具 =======

// 顶部小号渐变头（与 Profile 一致）
class ModernSliverHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double height;
  final List<Widget>? actions;
  const ModernSliverHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.height = 120,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: height.h,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: ClipRRect(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(18.r),
            bottomRight: Radius.circular(18.r),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2563EB),
                  Color(0xFF3B82F6),
                  Color(0xFF60A5FA)
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(title,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      SizedBox(height: 4.h),
                      Text(subtitle!,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 11.5.sp)),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: actions,
    );
  }
}

// 通用现代卡片
class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  const ModernCard({super.key, required this.child, this.padding, this.margin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: padding ?? EdgeInsets.all(12.w),
          child: child,
        ),
      ),
    );
  }
}

// 头部裁剪（直接裁圆角，彻底消除“台阶/锯齿”）
class _HeaderClipper extends CustomClipper<Path> {
  final double radius;
  _HeaderClipper({required this.radius});
  @override
  Path getClip(Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ));
  }

  @override
  bool shouldReclip(covariant _HeaderClipper oldClipper) =>
      oldClipper.radius != radius;
}

// 徽章类型：绿色=用户认证；蓝色=邮箱官方认证
enum ModernBadgeType { userVerified, emailVerified }

// 现代徽章（渐变+光晕+可选白环）
class ModernBadge extends StatelessWidget {
  final ModernBadgeType type;
  final double size;
  final bool withRing;
  const ModernBadge({
    super.key,
    required this.type,
    this.size = 20,
    this.withRing = false,
  });

  @override
  Widget build(BuildContext context) {
    late List<Color> colors;
    late IconData icon;
    switch (type) {
      case ModernBadgeType.userVerified: // 绿色（用户认证）
        colors = [const Color(0xFF22C55E), const Color(0xFF16A34A)];
        icon = Icons.verified_rounded;
        break;
      case ModernBadgeType.emailVerified: // 蓝色（邮箱官方认证）
        colors = [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
        icon = Icons.mark_email_read_rounded;
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.35),
            blurRadius: 8.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (withRing)
            Center(
              child: Container(
                width: size * 0.86,
                height: size * 0.86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: size * 0.12),
                ),
              ),
            ),
          Center(child: Icon(icon, color: Colors.white, size: size * 0.56)),
        ],
      ),
    );
  }
}

// 小型“邮箱认证”Chip
class EmailVerifiedChip extends StatelessWidget {
  final double size;
  const EmailVerifiedChip({super.key, this.size = 12});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF2563EB).withOpacity(0.25),
              blurRadius: 6.r,
              offset: Offset(0, 2.h)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_read_rounded, size: size, color: Colors.white),
          SizedBox(width: 4.w),
          Text('Email OK',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5.sp,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
