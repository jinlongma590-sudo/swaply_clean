// lib/widgets/welcome_coupon_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swaply/router/root_nav.dart';
class WelcomeCouponDialog extends StatefulWidget {
  final Map<String, dynamic> couponData;

  const WelcomeCouponDialog({
    super.key,
    required this.couponData,
  });

  @override
  State<WelcomeCouponDialog> createState() => _WelcomeCouponDialogState();
}

class _WelcomeCouponDialogState extends State<WelcomeCouponDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 360))
    ..forward();
  late final Animation<double> _fade =
  CurvedAnimation(parent: _ac, curve: Curves.easeIn);
  late final Animation<double> _scale =
  CurvedAnimation(parent: _ac, curve: Curves.decelerate);

  // CP1252 → 原字节反向映射（修乱码）
  static const Map<int, int> _cp1252Reverse = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
    0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
    0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
    0x017E: 0x9E, 0x0178: 0x9F,
  };

  String _fixUtf8Mojibake(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;
    final hasEmoji = s.runes.any((r) => (r >= 0x1F300 && r <= 0x1FAFF));
    if (hasEmoji) return s;
    final looksBroken = s.contains('ð') ||
        s.contains('Ã') ||
        s.contains('Â') ||
        s.contains('â') ||
        s.contains('�') ||
        s.contains(RegExp(r'[€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'));
    if (!looksBroken) return s;
    try {
      final bytes = <int>[];
      for (final r in s.runes) {
        final m = _cp1252Reverse[r];
        if (m != null) {
          bytes.add(m);
        } else if (r <= 0xFF) {
          bytes.add(r & 0xFF);
        } else {
          bytes.add(0x3F);
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return utf8.decode(latin1.encode(s), allowMalformed: true);
      } catch (_) {
        return s;
      }
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    final shortest = sz.shortestSide;
    final bool isTablet = shortest >= 600;

    // —— 更紧凑的尺寸策略 —— //
    final double maxWidth =
    (isTablet ? 360.0 : 320.0).w.clamp(260.0, sz.width - 32.0);
    final double maxHeight = sz.height * 0.52; // 总高 ≤ 52% 屏高（明显更小）

    final String code = (widget.couponData['code']?.toString() ?? '').toUpperCase();
    final String title = _fixUtf8Mojibake(
      widget.couponData['title'] ?? 'Welcome gift 🎉',
    );
    final String desc = _fixUtf8Mojibake(
      widget.couponData['description'] ??
          'Welcome to Swaply! Pin your item for 3 days.',
    );

    String expiryText = '';
    final expiresRaw = widget.couponData['expires_at'];
    if (expiresRaw != null) {
      try {
        final d = DateTime.parse(expiresRaw.toString());
        final days = d.difference(DateTime.now()).inDays;
        expiryText = days > 0 ? 'Valid for $days days' : 'Expiring soon';
      } catch (_) {}
    }

    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(14.w, 20.h, 14.w, 16.h),
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: Material(
              color: Colors.white,
              elevation: 0,
              borderRadius: BorderRadius.circular(14.r),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.r),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顶部 4px 渐变条（极简）
                    Container(
                      height: 4.h,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1877F2), Color(0xFF7B61FF)],
                        ),
                      ),
                    ),

                    // 内容：不使用 Expanded，避免被拉高；仅在溢出时滚动
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 图标（更小）
                            Container(
                              width: 52.w,
                              height: 52.w,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF5D9CFF), Color(0xFFB46BFF)],
                                ),
                              ),
                              child: Icon(Icons.card_giftcard,
                                  color: Colors.white, size: 26.sp),
                            ),
                            SizedBox(height: 10.h),

                            // 标题（18sp）
                            Text(
                              title.isEmpty ? 'Welcome gift 🎉' : title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF222222),
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 6.h),

                            // “Coupon Code”
                            Text(
                              'Coupon Code:',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 6.h),

                            // 券码条（紧凑、含复制按钮）
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10.r),
                                gradient: LinearGradient(
                                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                                ),
                                border: Border.all(color: const Color(0x141877F2)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      code,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.3,
                                        color: const Color(0xFF1877F2),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      await Clipboard.setData(ClipboardData(text: code));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('Copied coupon code'),
                                          duration: const Duration(milliseconds: 1000),
                                          behavior: SnackBarBehavior.floating,
                                          margin: EdgeInsets.all(10.w),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10.r),
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(4.w),
                                      child: const Icon(Icons.copy_rounded,
                                          color: Color(0xFF1877F2)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (expiryText.isNotEmpty) ...[
                              SizedBox(height: 6.h),
                              Text(
                                expiryText,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],

                            SizedBox(height: 8.h),

                            // 描述（更短行高）
                            Text(
                              desc,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5.sp,
                                height: 1.28,
                                color: Colors.grey[700],
                              ),
                            ),

                            SizedBox(height: 8.h),

                            // “Free Category Pinning” 小芯片（紧凑）
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.green.shade100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle,
                                      size: 14, color: Colors.green),
                                  SizedBox(width: 6.w),
                                  Text(
                                    'Free Category Pinning',
                                    style: TextStyle(
                                      fontSize: 11.5.sp,
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 紧凑按钮区（紧贴内容，无多余大白边）
                    Padding(
                      padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 42.h,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1877F2), Color(0xFF7B61FF)],
                                ),
                                borderRadius: BorderRadius.circular(10.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1877F2).withOpacity(0.22),
                                    blurRadius: 8.r,
                                    offset: Offset(0, 3.h),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  navMaybePop();
                                  navPush('/coupons');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                ),
                                child: Text(
                                  'View My Coupons',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 6.h),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              minimumSize: Size.fromHeight(34.h),
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Later',
                              style: TextStyle(
                                fontSize: 12.5.sp,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
