// lib/pages/wishlist_page.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/root_nav.dart';
// ✅ 顶部 import 修正
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/favorites_update_service.dart';

// === 全局路由 & 常量 & API ===
import 'package:swaply/router/root_nav.dart'; // navPush / navReplaceAll
import 'package:swaply/theme/constants.dart'; // kPrimaryBlue / kCustomHeaderHeight
import 'package:swaply/listing_api.dart'; // 保留用于其他可能的引用，主要逻辑已切回 DualFavoritesService

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  List<Map<String, dynamic>> _wishlistItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // ✅ 新增：收藏变更订阅（与 SavedPage 对齐）
  StreamSubscription<dynamic>? _favSub;

  @override
  void initState() {
    super.initState();
    _setupFavoritesListener();
    _loadWishlist();
  }

  @override
  void dispose() {
    _favSub?.cancel();
    super.dispose();
  }

  // ✅ 新增：实时监听收藏变化（详情页操作后本地同步）
  void _setupFavoritesListener() {
    _favSub = FavoritesUpdateService().favoritesStream.listen((event) async {
      if (!mounted) return;
      try {
        final id = (event as dynamic).listingId?.toString();
        final isAdd = (event as dynamic).isAdded == true;
        if (isAdd) {
          // 详情页添加 → 直接整体刷新（保持与服务端一致）
          await _loadWishlist();
        } else {
          // 详情页取消 → 本地移除
          if (id != null) {
            setState(() {
              _wishlistItems.removeWhere((x) =>
                  x['listing_id']?.toString() == id ||
                  x['listing']?['id']?.toString() == id);
            });
          }
        }
      } catch (_) {
        // 静默忽略解析异常
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint('favoritesStream error: $e');
    });
  }

  /// 加载心愿单数据
  // ✅ 按照要求完全替换逻辑
  Future<void> _loadWishlist() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // 保持统一的游客跳转逻辑
        await navReplaceAll('/welcome');
        return;
      }

      // ⚠️ 用真正的“心愿单” API
      final results = await DualFavoritesService.getUserWishlist(
        userId: user.id,
        limit: 100,
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _wishlistItems = results; // 直接用它，里面的 listing 已经是 Map
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshWishlist() async {
    setState(() => _isRefreshing = true);
    await _loadWishlist();
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _removeFromWishlist(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _wishlistItems.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('Removed from wishlist and favorites'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from wishlist');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }

  String _getListingImage(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'];
    if (images is List && images.isNotEmpty) {
      return images.first.toString();
    }
    return 'assets/images/placeholder.jpg';
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Price not available';
    final priceStr = price.toString();
    if (priceStr.startsWith('\$')) return priceStr;
    final numPrice = double.tryParse(priceStr);
    if (numPrice != null) {
      return '\$${numPrice.toStringAsFixed(0)}';
    }
    return priceStr;
  }

  Widget _buildWishlistCard(Map<String, dynamic> item, int index) {
    // 数据解析兼容处理
    final listing = (item['listing'] ?? {}) as Map<String, dynamic>;
    final listingId =
        item['listing_id']?.toString() ?? listing['id']?.toString() ?? '';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final price = _formatPrice(listing['price']);
    final city = listing['city']?.toString() ?? '';
    final imageUrl = _getListingImage(listing);
    final createdAt = item['created_at']?.toString() ?? '';
    final timeAdded = DualFavoritesService.formatSavedTime(createdAt);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      color: Colors.white,
      child: InkWell(
        onTap: () async {
          if (listingId.isEmpty) return;
          // ✅ 统一全局命名路由；返回后刷新
          await navPush('/listing', arguments: listingId);
          await _loadWishlist();
        },
        borderRadius: BorderRadius.circular(12.w),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.w),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6.w,
                offset: Offset(0, 1.h),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // ✅ 修改：垂直居中对齐
              children: [
                // 缩略图
                Hero(
                  tag: 'wishlist_image_$listingId',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.w),
                    child: Container(
                      width: 65.w,
                      height: 65.w,
                      decoration: BoxDecoration(
                        color: kPrimaryBlue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8.w),
                      ),
                      child: imageUrl.startsWith('http')
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 15.w,
                                    height: 15.w,
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                              : null,
                                      strokeWidth: 1.5.w,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          kPrimaryBlue),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: kPrimaryBlue.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8.w),
                                  ),
                                  child: Icon(
                                    Icons.image_not_supported_rounded,
                                    color: kPrimaryBlue.withOpacity(0.5),
                                    size: 24.w,
                                  ),
                                );
                              },
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: kPrimaryBlue.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(8.w),
                              ),
                              child: Icon(
                                Icons.image_not_supported_rounded,
                                color: kPrimaryBlue.withOpacity(0.5),
                                size: 24.w,
                              ),
                            ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),

                // 文本
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: kPrimaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6.w),
                        ),
                        child: Text(
                          price,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryBlue,
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      if (city.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 11.w,
                              color: Colors.grey[500],
                            ),
                            SizedBox(width: 3.w),
                            Expanded(
                              child: Text(
                                city,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 3.h),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 10.w,
                            color: Colors.grey[400],
                          ),
                          SizedBox(width: 3.w),
                          Text(
                            'Added $timeAdded',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 移除按钮 (已修改为红色)
                Container(
                  margin: EdgeInsets.only(left: 6.w),
                  decoration: BoxDecoration(
                    color: Colors.red
                        .withOpacity(0.1), // ❌ 原: kPrimaryBlue.withOpacity(0.1)
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showRemoveDialog(listingId, title, index),
                      borderRadius: BorderRadius.circular(8.w),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.red, // ❌ 原: kPrimaryBlue
                          size: 18.w,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Remove from Wishlist',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "$title" from your wishlist and favorites?',
            style: TextStyle(fontSize: 13.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => navPop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  navPop();
                  _removeFromWishlist(listingId, index);
                },
                child: Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100.w,
              height: 100.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kPrimaryBlue.withOpacity(0.10),
                    const Color(0xFF1E88E5).withOpacity(0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(50.w),
                border: Border.all(
                  color: kPrimaryBlue.withOpacity(0.2),
                  width: 1.5.w,
                ),
              ),
              child: Icon(
                Icons.favorite_outline_rounded,
                size: 50.w,
                color: kPrimaryBlue,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'No Wishlist Items Yet',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                'Start adding items you like to your wishlist by tapping the bookmark icon on any listing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(height: 30.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12.w),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryBlue.withOpacity(0.25),
                    blurRadius: 10.w,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => navReplaceAll('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                ),
                icon: Icon(Icons.explore_rounded,
                    size: 16.w, color: Colors.white),
                label: Text(
                  'Browse Items',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90.w,
              height: 90.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(45.w),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 45.w,
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _errorMessage ?? 'Failed to load your wishlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            SizedBox(height: 24.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                ),
                borderRadius: BorderRadius.circular(10.w),
              ),
              child: ElevatedButton.icon(
                onPressed: _loadWishlist,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 16.w),
                label: Text(
                  'Try Again',
                  style:
                      TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 与邀请好友页对齐的头部高度策略
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        // ✅ Android：使用默认高度；iOS：44（再叠加状态栏高度）——与邀请好友页一致
        toolbarHeight: isIOS ? 44 : null,
        title: Text(
          'My Wishlist (${_wishlistItems.length})',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          if (_wishlistItems.isNotEmpty && !_isLoading)
            Padding(
              padding: EdgeInsets.only(right: 6.w), // ✅ 轻微右边距，居中对齐
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: Colors.white, size: 20.r),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.w)),
                onSelected: (value) {
                  if (value == 'clear_all') {
                    _showClearAllDialog();
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem(
                    value: 'clear_all',
                    child: Row(
                      children: [
                        Icon(Icons.clear_all_rounded,
                            color: Colors.red, size: 16.w),
                        SizedBox(width: 10.w),
                        Text('Clear All', style: TextStyle(fontSize: 13.sp)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 30.w,
                    height: 30.w,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kPrimaryBlue),
                      strokeWidth: 2.5.w,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'Loading wishlist...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : _wishlistItems.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _refreshWishlist,
                      color: kPrimaryBlue,
                      backgroundColor: Colors.white,
                      strokeWidth: 2.w,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        itemCount: _wishlistItems.length,
                        itemBuilder: (context, index) {
                          return _buildWishlistCard(
                              _wishlistItems[index], index);
                        },
                      ),
                    ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child:
                    Icon(Icons.warning_outlined, color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Clear All Wishlist',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove all items from your wishlist and favorites? This action cannot be undone.',
            style: TextStyle(fontSize: 13.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => navPop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  navPop();
                  _clearAllWishlist();
                },
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearAllWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final success =
          await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _wishlistItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('All wishlist and favorites cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to clear wishlist');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to clear wishlist. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }
}
