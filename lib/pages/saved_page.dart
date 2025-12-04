// lib/pages/saved_page.dart
import 'dart:async'; // Timer, StreamSubscription
import 'package:flutter/foundation.dart'; // ✅ 修改：引入完整 foundation 以使用 defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/core/l10n/app_localizations.dart';

// === 项目内服务 ===
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/favorites_update_service.dart';

// === 全局常量 ===
import 'package:swaply/theme/constants.dart'; // kPrimaryBlue

class SavedPage extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;
  const SavedPage({Key? key, this.isGuest = false, this.onNavigateToHome})
      : super(key: key);

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _favoriteItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  StreamSubscription<dynamic>? _favoritesSubscription;

  // ❌ 已删除 _headerBarHeight 方法
  // ❌ 已删除 _buildCustomHeader 方法

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (!widget.isGuest) {
      _loadFavorites();
      _startAutoRefresh();
      _setupFavoritesListener();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _favoritesSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isGuest) {
      _loadFavorites();
    }
  }

  // ========== 订阅收藏变更 ==========
  void _setupFavoritesListener() {
    _favoritesSubscription =
        FavoritesUpdateService().favoritesStream.listen((event) {
          if (!mounted || widget.isGuest) return;

          try {
            final isAdded = (event as dynamic).isAdded == true;
            final listingId = (event as dynamic).listingId?.toString();
            final data = (event as dynamic).listingData as Map<String, dynamic>?;

            if (isAdded && data != null) {
              _addToLocalFavorites(data);
            } else if (!isAdded && listingId != null) {
              _removeFromLocalFavorites(listingId);
            }
          } catch (e) {
            if (kDebugMode) debugPrint('favoritesStream parse error: $e');
          }
        }, onError: (error) {
          if (kDebugMode) debugPrint('Error in favorites stream: $error');
        });
  }

  void _addToLocalFavorites(Map<String, dynamic> listingData) {
    try {
      final listingId = listingData['id']?.toString();
      if (listingId == null) return;

      final exists = _favoriteItems.any((item) =>
      item['listing_id']?.toString() == listingId ||
          item['listing']?['id']?.toString() == listingId);

      if (!exists) {
        final favoriteItem = {
          'listing_id': listingId,
          'listing': _safeMapConvert(listingData),
          'created_at': DateTime.now().toIso8601String(),
        };

        setState(() {
          _favoriteItems.insert(0, favoriteItem);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error adding to local favorites: $e');
    }
  }

  void _removeFromLocalFavorites(String listingId) {
    try {
      setState(() {
        _favoriteItems.removeWhere((item) =>
        item['listing_id']?.toString() == listingId ||
            item['listing']?['id']?.toString() == listingId);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error removing from local favorites: $e');
    }
  }

  // ========== 周期刷新 ==========
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!widget.isGuest && mounted && !_isRefreshing) {
        _loadFavorites();
      }
    });
  }

  // ========== 工具函数 ==========
  Map<String, dynamic> _safeMapConvert(dynamic input) {
    if (input == null) return <String, dynamic>{};
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      try {
        return Map<String, dynamic>.from(input);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  String _safeGetString(Map<String, dynamic> map, String key,
      {String defaultValue = ''}) {
    try {
      return map[key]?.toString() ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  String _getListingImage(Map<String, dynamic> listing) {
    try {
      final images = listing['images'] ?? listing['image_urls'];
      if (images is List && images.isNotEmpty) {
        return images.first.toString();
      }
    } catch (_) {}
    return 'assets/images/placeholder.jpg';
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Price not available';
    try {
      final priceStr = price.toString();
      if (priceStr.startsWith('\$')) return priceStr;
      final numPrice = double.tryParse(priceStr);
      if (numPrice != null) return '\$${numPrice.toStringAsFixed(0)}';
      return priceStr.isNotEmpty ? priceStr : 'Price not available';
    } catch (_) {
      return 'Price not available';
    }
  }

  // ========== 数据加载 ==========
  Future<void> _loadFavorites() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _errorMessage = 'User not logged in');
        return;
      }

      // 与 Wishlist 对齐：拉取 wishlist 源
      final results = await DualFavoritesService.getUserWishlist(
        userId: user.id,
        limit: 100,
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _favoriteItems = results;
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

  Future<void> _refreshFavorites() async {
    setState(() => _isRefreshing = true);
    await _loadFavorites();
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _removeFromFavorites(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _favoriteItems.removeAt(index);
        });

        FavoritesUpdateService().notifyFavoriteChanged(
          listingId: listingId,
          isAdded: false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('Removed from favorites and wishlist'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from favorites');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Remove favorite error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }

  Future<void> _clearAllFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final currentItems = List<Map<String, dynamic>>.from(_favoriteItems);
      final success =
      await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _favoriteItems.clear();
        });

        for (final item in currentItems) {
          final listingId = item['listing_id']?.toString();
          if (listingId != null) {
            FavoritesUpdateService().notifyFavoriteChanged(
              listingId: listingId,
              isAdded: false,
            );
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('All favorites and wishlist cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to clear favorites');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Clear all error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to clear favorites. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }

  // 🗑️ 清空确认弹窗
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Clear All'),
        content: const Text('Are you sure you want to clear all favorites?'),
        actions: [
          TextButton(
            onPressed: () => navPop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              navPop();
              await _clearAllFavorites();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ========== 空态 / 错态 ==========
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kPrimaryBlue.withOpacity(0.1),
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(40.w),
                border: Border.all(
                  color: kPrimaryBlue.withOpacity(0.2),
                  width: 1.w,
                ),
              ),
              child: Icon(
                Icons.bookmark_outline_rounded,
                size: 40.w,
                color: kPrimaryBlue,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'No Favorites Yet',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                'Start adding items you like to your favorites by tapping the bookmark icon on any listing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(8.w),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryBlue.withOpacity(0.3),
                    blurRadius: 8.w,
                    offset: Offset(0, 3.h),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  if (widget.onNavigateToHome != null) {
                    widget.onNavigateToHome!();
                  } else {
                    navReplaceAll('/welcome');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon:
                Icon(Icons.explore_rounded, size: 12.w, color: Colors.white),
                label: Text(
                  'Browse Items',
                  style: TextStyle(
                    fontSize: 11.sp,
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
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70.w,
              height: 70.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(35.w),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 35.w,
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              _errorMessage ?? 'Failed to load your favorites.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey[600],
                height: 1.3,
              ),
            ),
            SizedBox(height: 16.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                ),
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: ElevatedButton.icon(
                onPressed: _loadFavorites,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 12.w),
                label: Text(
                  'Try Again',
                  style:
                  TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== 单卡片 ==========
  Widget _buildFavoriteCard(Map<String, dynamic> item, int index) {
    try {
      final safeListing = _safeMapConvert(item['listing'] ?? {});
      final safeItem = _safeMapConvert(item);

      final listingId = _safeGetString(safeItem, 'listing_id');
      if (listingId.isEmpty) return const SizedBox.shrink();

      final title =
      _safeGetString(safeListing, 'title', defaultValue: 'Unknown Item');
      final price = _formatPrice(safeListing['price']);
      final city = _safeGetString(safeListing, 'city');
      final imageUrl = _getListingImage(safeListing);
      final createdAt = _safeGetString(safeItem, 'created_at');

      final timeAdded = DualFavoritesService.formatSavedTime(createdAt);

      return Card(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
        color: Colors.white,
        child: InkWell(
          onTap: () async {
            if (listingId.isEmpty) return;
            await navPush('/listing', arguments: listingId);
            _loadFavorites(); // 返回后刷新
          },
          borderRadius: BorderRadius.circular(8.w),
          child: Padding(
            padding: EdgeInsets.all(8.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.w),
                  child: Container(
                    width: 50.w,
                    height: 50.w,
                    color: Colors.grey[100],
                    child: imageUrl.startsWith('http')
                        ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, prog) {
                        if (prog == null) return child;
                        return Center(
                          child: SizedBox(
                            width: 12.w,
                            height: 12.w,
                            child: CircularProgressIndicator(
                              value: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                  prog.expectedTotalBytes!
                                  : null,
                              strokeWidth: 1.w,
                              valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  kPrimaryBlue),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.image_not_supported_rounded,
                        color: Colors.grey[400],
                        size: 18.w,
                      ),
                    )
                        : Icon(
                      Icons.image_not_supported_rounded,
                      color: Colors.grey[400],
                      size: 18.w,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),

                // 文本
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Container(
                        padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                        decoration: BoxDecoration(
                          color: kPrimaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4.w),
                        ),
                        child: Text(
                          price,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryBlue,
                          ),
                        ),
                      ),
                      SizedBox(height: 3.h),
                      if (city.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded,
                                size: 8.w, color: Colors.grey[500]),
                            SizedBox(width: 2.w),
                            Expanded(
                              child: Text(
                                city,
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 8.w, color: Colors.grey[400]),
                          SizedBox(width: 2.w),
                          Text(
                            'Saved $timeAdded',
                            style: TextStyle(
                              fontSize: 8.sp,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 右侧收藏按钮
                Container(
                  margin: EdgeInsets.only(left: 4.w),
                  decoration: BoxDecoration(
                    color: kPrimaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6.w),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showRemoveDialog(listingId, title, index),
                      borderRadius: BorderRadius.circular(6.w),
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(Icons.bookmark_rounded,
                            color: kPrimaryBlue, size: 14.w),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Favorite card error: $e\n$st');
      }
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8.w),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 20.w),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Error loading item',
                style: TextStyle(fontSize: 11.sp, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4.w),
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 14.w),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Remove from Favorites',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "$title" from your favorites and wishlist?',
          style: TextStyle(fontSize: 11.sp, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => navPop(),
            child: Text('Cancel',
                style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4.w),
            ),
            child: TextButton(
              onPressed: () {
                navPop();
                _removeFromFavorites(listingId, index);
              },
              child: Text(
                'Remove',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.maybeOf(context);
    // ✅ 统一与 NotificationPage 一致的顶部逻辑
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: kPrimaryBlue,
          // ✅ 统一高度
          toolbarHeight: isIOS ? 44 : null,
          title: Text(
            l10n?.myFavorites ?? 'My Favorites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp, // ✅ 统一字体大小
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: 0,
          automaticallyImplyLeading: false, // ❌ 无返回按钮
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(40.w),
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 40.w, color: Colors.grey[500]),
              ),
              SizedBox(height: 16.h),
              Text(
                l10n?.loginRequired ?? 'Login Required',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Text(
                  l10n?.loginToSaveFavorites ??
                      'Please login to view and save your favorite items.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11.sp,
                    height: 1.3,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryBlue, const Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(8.w),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryBlue.withOpacity(0.3),
                      blurRadius: 8.w,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await navReplaceAll('/welcome'); // 统一全局导航
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.w),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded,
                      size: 12.w, color: Colors.white),
                  label: Text(
                    l10n?.loginNow ?? 'Login Now',
                    style: TextStyle(
                      fontSize: 11.sp,
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ 使用标准 AppBar，移除 PreferredSize 自定义 Header
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        toolbarHeight: isIOS ? 44 : null, // ✅ 统一高度
        elevation: 0,
        automaticallyImplyLeading: false, // ❌ 无返回按钮
        title: Text(
          'My Favorites (${_favoriteItems.length})',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp, // ✅ 统一字体大小
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_favoriteItems.isNotEmpty && !_isLoading)
            Padding(
              padding: EdgeInsets.only(right: 6.w),
              child: PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded,
                    color: Colors.white, size: 20.r),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                elevation: 6,
                onSelected: (value) {
                  if (value == 'clear_all') _showClearAllDialog();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'clear_all',
                    height: 36.h,
                    child: Row(
                      children: [
                        Icon(Icons.clear_all_rounded,
                            color: Colors.red, size: 16.r),
                        SizedBox(width: 8.w),
                        Text('Clear All',
                            style: TextStyle(fontSize: 12.sp)),
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
              width: 24.w,
              height: 24.w,
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(
                    kPrimaryBlue),
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Loading favorites...',
              style:
              TextStyle(color: Colors.grey[600], fontSize: 11.sp),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? _buildErrorState()
          : _favoriteItems.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _refreshFavorites,
        color: kPrimaryBlue,
        backgroundColor: Colors.white,
        strokeWidth: 2,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 6.h),
          itemCount: _favoriteItems.length,
          itemBuilder: (context, index) =>
              _buildFavoriteCard(_favoriteItems[index], index),
        ),
      ),
    );
  }
}