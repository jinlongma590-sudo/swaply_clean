// lib/pages/seller_profile_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ← 新增：用来设置 SystemUiOverlayStyle
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/models/verification_types.dart' as vt;
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/widgets/verified_avatar.dart';

// 新增：改为通过 RPC 读取认证状态
import 'package:swaply/services/email_verification_service.dart';

class SellerProfileViewPage extends StatefulWidget {
  final String sellerId;
  final Map<String, dynamic>? initialSellerData;

  /// 可选：从上个页面传入的初始徽章（用于首屏先显示，随后以 RPC 结果覆盖）
  final vt.VerificationBadgeType verificationType;

  const SellerProfileViewPage({
    super.key,
    required this.sellerId,
    this.initialSellerData,
    this.verificationType = vt.VerificationBadgeType.none,
  });

  @override
  State<SellerProfileViewPage> createState() => _SellerProfileViewPageState();
}

class _SellerProfileViewPageState extends State<SellerProfileViewPage> {
  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);

  final _verifySvc = EmailVerificationService();

  bool _loading = true;
  Map<String, dynamic>? _fullSellerInfo;
  List<Map<String, dynamic>> _sellerListings = [];
  int _totalListings = 0;

  Map<String, dynamic>? _verifyRow;
  vt.VerificationBadgeType _sellerBadge = vt.VerificationBadgeType.none;

  @override
  void initState() {
    super.initState();

    _sellerBadge = widget.verificationType;

    if (widget.initialSellerData != null) {
      _fullSellerInfo = widget.initialSellerData;
    }

    _loadSellerData();

    // 首帧后拉取认证状态（公开 RPC）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSellerVerifyPublic();
    });
  }

  /// 仅负责拉取「认证展示字段」，并使用 VerificationBadgeUtil 解析
  Future<void> _loadSellerVerifyPublic() async {
    final sellerUserId = widget.sellerId;
    if (sellerUserId.isEmpty) return;

    try {
      final row = await _verifySvc.fetchPublicVerification(sellerUserId);
      // ignore: avoid_print
      print('[SellerProfile] public verify row = $row');

      final badge = vt.VerificationBadgeUtil.getVerificationTypeFromUser(row);

      if (!mounted) return;
      setState(() {
        _verifyRow = row;
        _sellerBadge = badge;
      });
    } catch (e) {
      if (kDebugMode) {
        print('[_loadSellerVerifyPublic] error: $e');
      }
    }
  }

  Future<void> _loadSellerData() async {
    try {
      setState(() => _loading = true);

      if (_fullSellerInfo == null) {
        final profileResponse = await Supabase.instance.client
            .from('public_profiles')
            .select('id, full_name, avatar_url, created_at')
            .eq('id', widget.sellerId)
            .maybeSingle();

        if (profileResponse != null) {
          _fullSellerInfo = Map<String, dynamic>.from(profileResponse);
        }
      }

      final listingsResponse = await Supabase.instance.client
          .from('listings')
          .select(
              'id, title, price, images, image_urls, city, created_at, views_count')
          .eq('user_id', widget.sellerId)
          .order('created_at', ascending: false)
          .limit(50);

      _sellerListings = List<Map<String, dynamic>>.from(
        listingsResponse.map((e) => Map<String, dynamic>.from(e)),
      );
      _totalListings = _sellerListings.length;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (kDebugMode) print('Error loading seller data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getMemberSince() {
    final createdAt = _fullSellerInfo?['created_at']?.toString();
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(createdAt);
      final difference = DateTime.now().difference(dateTime);
      if (difference.inDays > 365) {
        final years = (difference.inDays / 365).floor();
        return '$years year${years > 1 ? 's' : ''}';
      } else if (difference.inDays > 30) {
        final months = (difference.inDays / 30).floor();
        return '$months month${months > 1 ? 's' : ''}';
      } else {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''}';
      }
    } catch (_) {
      return '';
    }
  }

  Color _getVerificationColor(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.none:
        return Colors.grey;
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        return _successGreen;
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        return _primaryBlue;
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
      case vt.VerificationBadgeType.business:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getVerificationIcon(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        return Icons.verified_rounded;
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        return Icons.verified_user_rounded;
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
        return Icons.workspace_premium_rounded;
      case vt.VerificationBadgeType.business:
        return Icons.apartment_rounded;
      case vt.VerificationBadgeType.none:
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sellerName = _fullSellerInfo?['full_name'] ?? 'Seller';
    final avatarUrl = _fullSellerInfo?['avatar_url'];
    final memberSince = _getMemberSince();

    final badgeType = _sellerBadge;
    final bool isVerified = (badgeType != vt.VerificationBadgeType.none);

    // === 与 Wishlist 保持一致的头部高度策略 ===
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final double toolbarHeight = isIOS ? 44.0 : kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            // ↓↓↓ 仅为“高度与 Wishlist 一致”所做的最小改动 ↓↓↓
            toolbarHeight: toolbarHeight, // iOS 44 / Android 56
            collapsedHeight: toolbarHeight, // 折叠后同上
            systemOverlayStyle: SystemUiOverlayStyle.light,
            // ↑↑↑ 其余逻辑不动 ↑↑↑

            expandedHeight: 200.h,
            pinned: true,
            backgroundColor: _primaryBlue,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_primaryBlue, _primaryBlue.withOpacity(0.8)],
                  ),
                ),
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 28.h),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: VerifiedAvatar(
                              avatarUrl: avatarUrl,
                              radius: 40.r,
                              verificationType: badgeType,
                              defaultIcon: Icons.person,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          Text(
                            sellerName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          if (memberSince.isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Text(
                                'Member for $memberSince',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.sp,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 统计卡片
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.all(12.w),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8.r,
                    offset: Offset(0, 2.h),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Listings',
                    value: _totalListings.toString(),
                  ),
                  if (isVerified)
                    _buildStatItem(
                      icon: _getVerificationIcon(badgeType),
                      label: 'Status',
                      value: 'Verified',
                      color: _getVerificationColor(badgeType),
                    ),
                ],
              ),
            ),
          ),

          // 标题
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Text(
                'Seller\'s Listings ($_totalListings)',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),

          // 列表/网格
          if (_sellerListings.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200.h,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 48.sp, color: Colors.grey[400]),
                    SizedBox(height: 8.h),
                    Text('No listings yet',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 14.sp)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.all(12.w),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  // ✅ 轻调，卡片更协调
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.w,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final listing = _sellerListings[index];
                    return _buildListingCard(listing);
                  },
                  childCount: _sellerListings.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.grey[700], size: 24.sp),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.grey[800],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
      ],
    );
  }

  // ===================== 卡片（已修正“图片铺满 + 信息区紧凑”） =====================
  Widget _buildListingCard(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'] ?? [];
    final imageUrl =
        images is List && images.isNotEmpty ? images[0].toString() : '';

    return InkWell(
      onTap: () {
        SafeNavigator.push(
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              productId: listing['id'].toString(),
              productData: listing,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 顶部图片：等比铺满（cover），统一高度比例
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
              child: AspectRatio(
                aspectRatio: 1.25, // 宽:高 ≈ 1.25，更贴近 Jiji 卡片观感
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover, // ✅ 关键：铺满裁剪
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: Icon(Icons.image,
                              size: 32.sp, color: Colors.grey[400]),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.image,
                            size: 32.sp, color: Colors.grey[400]),
                      ),
              ),
            ),

            // ✅ 信息区：紧凑排列（去掉 spaceBetween 的大白空）
            Padding(
              padding: EdgeInsets.all(10.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // 只占需要的高度
                children: [
                  Text(
                    listing['title']?.toString() ?? 'Untitled',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    listing['price']?.toString() ?? r'$0',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: _successGreen,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 10.sp, color: Colors.grey[600]),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          listing['city']?.toString() ?? 'Unknown',
                          style: TextStyle(
                              fontSize: 10.sp, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
// =======================================================================
}
