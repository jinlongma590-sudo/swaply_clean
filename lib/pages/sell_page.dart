// lib/pages/sell_page.dart
import 'package:flutter/foundation.dart'; // ✅ 新增：用于判断平台
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/theme/constants.dart';

class SellPage extends StatefulWidget {
  final bool isGuest;
  const SellPage({super.key, this.isGuest = false});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // ✅ 统一顶部逻辑：与 SavedPage / NotificationPage 完全一致
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (widget.isGuest) {
      return _buildGuestView(l10n, isIOS);
    }

    // 目前无数据，保留结构
    final List<Map<String, dynamic>> myListings =
        const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ 修改点：使用标准 AppBar 替代 SliverAppBar，确保高度和标题位置绝对对齐
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        toolbarHeight: isIOS ? 44 : null, // ✅ 核心：iOS 高度修正
        elevation: 0,
        automaticallyImplyLeading: false, // ✅ 核心：移除返回/菜单按钮占位
        centerTitle: true, // ✅ [NEW] 强制标题居中
        title: Text(
          l10n.sellItem,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp, // ✅ 核心：字体大小统一为 16.sp
            fontWeight: FontWeight.w600, // ✅ 核心：字重统一为 w600
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => navPush('/sell-form'),
            icon: Icon(Icons.add_rounded, color: Colors.white, size: 28.r),
            tooltip: 'Add New Listing',
          ),
          SizedBox(width: 8.w),
        ],
      ),
      // ✅ Body 依然使用 CustomScrollView 以支持 SliverFillRemaining (空态)
      body: CustomScrollView(
        slivers: [
          // ❌ 已移除 _buildFixedHeader，由 Scaffold AppBar 接管
          if (myListings.isEmpty)
            _buildEmptyState(l10n)
          else
            _buildListingsContent(myListings, l10n),
        ],
      ),
    );
  }

  // ===================== Guest View =====================
  Widget _buildGuestView(AppLocalizations l10n, bool isIOS) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        elevation: 0,
        toolbarHeight: isIOS ? 44 : null, // ✅ 同步 Guest 页面高度
        automaticallyImplyLeading: false, // ✅ 同步移除 Leading
        centerTitle: true, // ✅ [NEW] 强制标题居中
        title: Text(
          l10n.sellItem,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp, // ✅ 同步字体
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => navReplaceAll('/welcome'),
            icon: Icon(Icons.login_rounded, color: Colors.white, size: 24.r),
            tooltip: l10n.loginNow,
          ),
          SizedBox(width: 8.w),
        ],
      ),
      body: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 22.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 108.w,
                    height: 108.w,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.grey.shade200, Colors.grey.shade100],
                      ),
                      borderRadius: BorderRadius.circular(54.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16.r,
                          offset: Offset(0, 6.h),
                        )
                      ],
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 52.r,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    l10n.loginRequired,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      letterSpacing: -0.4,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    l10n.loginToPost,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14.sp,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: 28.h),
                  Container(
                    width: double.infinity,
                    height: 50.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kPrimaryBlue, Color(0xFF1E88E5)],
                      ),
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryBlue.withOpacity(0.35),
                          blurRadius: 12.r,
                          offset: Offset(0, 6.h),
                        )
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => navReplaceAll('/welcome'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      icon: Icon(Icons.login_rounded,
                          size: 18.r, color: Colors.white),
                      label: Text(
                        l10n.loginNow,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===================== 空态 =====================
  Widget _buildEmptyState(AppLocalizations l10n) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120.w,
                    height: 120.w,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          kPrimaryBlue.withOpacity(0.18),
                          const Color(0xFF1E88E5).withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(60.r),
                      border: Border.all(
                          color: kPrimaryBlue.withOpacity(0.28), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryBlue.withOpacity(0.18),
                          blurRadius: 20.r,
                          offset: Offset(0, 10.h),
                        )
                      ],
                    ),
                    child: Icon(Icons.add_a_photo_rounded,
                        size: 60.r, color: kPrimaryBlue),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    l10n.sellYourItems,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.takePhotoAndSell,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14.sp,
                        height: 1.5),
                  ),
                  SizedBox(height: 18.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: kPrimaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: kPrimaryBlue.withOpacity(0.18)),
                    ),
                    child: Column(
                      children: [
                        _hintRow(
                            Icons.camera_alt_rounded, 'Take quality photos'),
                        SizedBox(height: 6.h),
                        _hintRow(
                            Icons.edit_rounded, 'Write detailed description'),
                        SizedBox(height: 6.h),
                        _hintRow(Icons.monetization_on_rounded,
                            'Set competitive price'),
                      ],
                    ),
                  ),
                  SizedBox(height: 28.h),
                  Container(
                    width: double.infinity,
                    height: 50.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [kPrimaryBlue, Color(0xFF1E88E5)]),
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryBlue.withOpacity(0.28),
                          blurRadius: 14.r,
                          offset: Offset(0, 7.h),
                        )
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      onPressed: () => navPush('/sell-form'),
                      icon: Icon(Icons.add_rounded,
                          color: Colors.white, size: 20.r),
                      label: Text(
                        l10n.postNewAd,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Row _hintRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: kPrimaryBlue, size: 18.r),
        SizedBox(width: 6.w),
        Expanded(
            child: Text(text,
                style:
                    TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
      ],
    );
  }

  // ===================== 列表内容 =====================
  Widget _buildListingsContent(
      List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) return _buildStatsHeader(myListings, l10n);
          final listingIndex = index - 1;
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 280 + (listingIndex * 90)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 18 * (1 - value)),
                child: Opacity(
                    opacity: value,
                    child: _buildListingCard(myListings[listingIndex], l10n)),
              );
            },
          );
        },
        childCount: myListings.length + 1,
      ),
    );
  }

  Widget _buildStatsHeader(
      List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    final totalViews = myListings.fold<int>(0, (sum, item) => sum + 234);
    final totalLikes = myListings.fold<int>(0, (sum, item) => sum + 12);

    return Container(
      margin: EdgeInsets.all(14.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF8F9FA)],
        ),
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14.r,
              offset: Offset(0, 4.h))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.myListings,
                  style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87)),
              SizedBox(height: 2.h),
              Text('${myListings.length} active items',
                  style:
                      TextStyle(fontSize: 12.sp, color: Colors.grey.shade600)),
            ]),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [kPrimaryBlue, Color(0xFF1E88E5)]),
                borderRadius: BorderRadius.circular(10.r),
                boxShadow: [
                  BoxShadow(
                      color: kPrimaryBlue.withOpacity(0.28),
                      blurRadius: 8.r,
                      offset: Offset(0, 4.h))
                ],
              ),
              child: GestureDetector(
                onTap: () => navPush('/sell-form'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 16.r, color: Colors.white),
                  SizedBox(width: 6.w),
                  Text(l10n.newAd,
                      style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
              ),
            ),
          ]),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(Icons.visibility_rounded,
                      totalViews.toString(), 'Total Views', kPrimaryBlue)),
              SizedBox(width: 10.w),
              Expanded(
                  child: _buildStatCard(
                      Icons.favorite_rounded,
                      totalLikes.toString(),
                      'Total Likes',
                      Colors.red.shade400)),
              SizedBox(width: 10.w),
              Expanded(
                  child: _buildStatCard(
                      Icons.trending_up_rounded,
                      '${(totalViews * 0.15).toInt()}',
                      'Engagement',
                      Colors.green.shade400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20.r),
          SizedBox(height: 6.h),
          Text(value,
              style: TextStyle(
                  fontSize: 16.sp, fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 2.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 9.sp,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> item, AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12.r,
              offset: Offset(0, 4.h))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18.r),
        child: InkWell(
          onTap: () => navPush('/listing',
              arguments: {'id': item['id'], 'prefetch': item}),
          borderRadius: BorderRadius.circular(18.r),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 74.w,
                  height: 74.w,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.r),
                    gradient: LinearGradient(
                        colors: [Colors.grey.shade100, Colors.grey.shade50]),
                  ),
                  child: Icon(Icons.image_rounded,
                      color: Colors.grey.shade400, size: 28.r),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] ?? l10n.noTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kPrimaryBlue.withOpacity(0.15),
                              kPrimaryBlue.withOpacity(0.08)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: kPrimaryBlue.withOpacity(0.2)),
                        ),
                        child: Text(
                          (item['price'] ?? l10n.noPrice).toString(),
                          style: TextStyle(
                              color: kPrimaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          _buildEnhancedStatItem(Icons.visibility_rounded,
                              '234', Colors.blue.shade400),
                          SizedBox(width: 14.w),
                          _buildEnhancedStatItem(Icons.favorite_rounded, '12',
                              Colors.red.shade400),
                          SizedBox(width: 14.w),
                          _buildEnhancedStatItem(Icons.chat_bubble_rounded, '3',
                              Colors.green.shade400),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18.r, color: Colors.grey.shade600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r)),
                    onSelected: (value) => _handleMenuAction(value, item, l10n),
                    itemBuilder: (BuildContext context) => [
                      _buildMenuItem('view', Icons.visibility_rounded, 'View',
                          Colors.blue.shade600),
                      _buildMenuItem('edit', Icons.edit_rounded, 'Edit',
                          Colors.orange.shade600),
                      _buildMenuItem('delete', Icons.delete_outline_rounded,
                          'Delete', Colors.red.shade600),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
      String value, IconData icon, String text, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.r),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r)),
            child: Icon(icon, size: 14.r, color: color),
          ),
          SizedBox(width: 10.w),
          Text(text,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatItem(IconData icon, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(4.r),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6.r)),
          child: Icon(icon, size: 12.r, color: color),
        ),
        SizedBox(width: 4.w),
        Text(count,
            style: TextStyle(
                color: color, fontSize: 11.sp, fontWeight: FontWeight.w700)),
      ],
    );
  }

  void _handleMenuAction(
      String action, Map<String, dynamic> item, AppLocalizations l10n) async {
    switch (action) {
      case 'view':
        navPush('/listing', arguments: {'id': item['id'], 'prefetch': item});
        break;
      case 'edit':
        navPush('/sell-form', arguments: {'id': item['id']});
        break;
      case 'delete':
        _showDeleteDialog(item, l10n);
        break;
    }
  }

  void _showDeleteDialog(Map<String, dynamic> item, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r)),
              child: Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 22.r),
            ),
            SizedBox(width: 10.w),
            Expanded(
                child: Text(l10n.delete,
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700))),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item['title'] ?? 'this listing'}"? This action cannot be undone.',
          style: TextStyle(fontSize: 13.sp, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style:
                      TextStyle(fontSize: 13.sp, color: Colors.grey.shade600))),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade600]),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteListing(item, l10n);
              },
              child: Text('Delete',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteListing(Map<String, dynamic> item, AppLocalizations l10n) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 16.r),
          SizedBox(width: 6.w),
          Text(l10n.listingDeleted),
        ]),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(14.w),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
