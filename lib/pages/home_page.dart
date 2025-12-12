// lib/pages/home_page.dart
// ✅ [Gold Standard] SWR + HybridGrid + 稳定 key + 首次锁滚动
// ✅ [核心优势] 旧数据先显示，后台刷新无闪烁，滚动位置完美保持
// ✅ [性能优化] 单一 SliverGrid，高度恒定，无跳动
// ✅ [搜索优化] 独立搜索输入页面，避免主页卡顿

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/pages/category_products_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/search_results_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/listing_api.dart';
import 'dart:async';
import 'package:swaply/services/listing_events_bus.dart';
import 'package:swaply/services/welcome_dialog_service.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const int _featuredAdsLimit = 10;
  static const int _popularItemsLimit = 100;
  static const int _minFeaturedPlaceholder = 2;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _trendingKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedLocation = 'All Zimbabwe';

  List<Map<String, dynamic>> _trendingRemote = [];
  bool _isFirstLoad = true;
  bool _isBackgroundRefreshing = false;
  StreamSubscription? _listingPubSub;

  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);

  static List<Map<String, dynamic>>? _cachedTrending;
  static DateTime? _cacheTime;
  static String? _cachedLocation;
  static const _cacheDuration = Duration(minutes: 2);

  static const List<String> _locations = [
    'All Zimbabwe',
    'Harare',
    'Bulawayo',
    'Chitungwiza',
    'Mutare',
    'Gweru',
    'Kwekwe',
    'Kadoma',
    'Masvingo',
    'Chinhoyi',
    'Chegutu',
    'Bindura',
    'Marondera',
    'Redcliff',
  ];

  static const List<Map<String, String>> _categories = [
    {"id": "trending", "icon": "trending", "label": "Trending"},
    {"id": "phones_tablets", "icon": "phones_tablets", "label": "Phones"},
    {"id": "vehicles", "icon": "vehicles", "label": "Vehicles"},
    {"id": "property", "icon": "property", "label": "Property"},
    {"id": "electronics", "icon": "electronics", "label": "Electronics"},
    {"id": "fashion", "icon": "fashion", "label": "Fashion"},
    {"id": "services", "icon": "services", "label": "Services"},
    {"id": "jobs", "icon": "jobs", "label": "Jobs"},
    {"id": "seeking_work_cvs", "icon": "seeking_work_cvs", "label": "Jobs Seeking"},
    {
      "id": "home_furniture_appliances",
      "icon": "home_furniture_appliances",
      "label": "Home & Furniture"
    },
    {
      "id": "beauty_personal_care",
      "icon": "beauty_personal_care",
      "label": "Beauty & Care"
    },
    {"id": "pets", "icon": "pets", "label": "Pets"},
    {"id": "babies_kids", "icon": "babies_kids", "label": "Baby & Kids"},
    {"id": "repair_construction", "icon": "repair_construction", "label": "Repair"},
    {"id": "leisure_activities", "icon": "leisure_activities", "label": "Leisure"},
    {"id": "food_agriculture_drinks", "icon": "food_agriculture_drinks", "label": "Food & Drinks"},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadTrending(showLoading: true);

    _listingPubSub = ListingEventsBus.instance.stream.listen((e) {
      if (e is ListingPublishedEvent) {
        _loadTrending(bypassCache: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchCtrl.dispose();
    _listingPubSub?.cancel();
    super.dispose();
  }

  double _iosBump(BuildContext context) {
    if (!Platform.isIOS) return 0;
    final top = MediaQuery.of(context).padding.top;
    return top + 10;
  }

  String _formatPrice(dynamic priceData) {
    if (priceData == null) return '';
    if (priceData is num) {
      if (priceData == 0) return 'Free';
      return '\$${priceData.toStringAsFixed(0)}';
    }
    if (priceData is String) {
      final lower = priceData.toLowerCase();
      if (lower.contains('free') || priceData == '0') return 'Free';
      final cleanPrice = priceData.replaceAll(RegExp(r'[^\d.]'), '');
      final parsedPrice = num.tryParse(cleanPrice);
      if (parsedPrice != null) {
        if (parsedPrice == 0) return 'Free';
        return '\$${parsedPrice.toStringAsFixed(0)}';
      } else {
        if (priceData.contains('\$') || priceData.contains('USD')) {
          return priceData;
        } else {
          return '\$$priceData';
        }
      }
    }
    return priceData.toString();
  }

  Future<List<Map<String, dynamic>>> _fetchTrendingMixed({
    String? city,
    int pinnedLimit = _featuredAdsLimit,
    int latestLimit = _popularItemsLimit,
    bool bypassCache = false,
  }) async {
    final startTime = DateTime.now();

    final results = await Future.wait([
      CouponService.getTrendingPinnedAds(
        city: city,
        limit: pinnedLimit,
      ).timeout(const Duration(seconds: 10)),
      ListingApi.fetchListings(
        city: city,
        limit: latestLimit,
        offset: 0,
        orderBy: 'created_at',
        ascending: false,
        status: 'active',
        forceNetwork: bypassCache,
      ).timeout(const Duration(seconds: 10)),
    ]).timeout(const Duration(seconds: 15));

    final pinnedAds = results[0] as List;
    final latest = results[1] as List<Map<String, dynamic>>;

    final duration = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('✅ [Performance] 数据请求耗时: ${duration}ms (pinned: ${pinnedAds.length}, latest: ${latest.length})');

    final list = <Map<String, dynamic>>[];
    for (final e in pinnedAds) {
      final l = (e['listings'] as Map<String, dynamic>? ?? {});
      if (l.isEmpty) continue;
      final imgs = (l['images'] as List?) ?? (l['image_urls'] as List?) ?? const [];
      list.add({
        'id': l['id'],
        'title': l['title'],
        'price': l['price'],
        'images': imgs,
        'city': l['city'],
        'created_at': l['created_at'],
        'pinned': true,
      });
    }
    final seen = <String>{...list.map((x) => x['id'].toString())};
    for (final r in latest) {
      final id = r['id']?.toString();
      if (id == null || seen.contains(id)) continue;
      seen.add(id);
      final imgs = (r['images'] as List?) ?? (r['image_urls'] as List?) ?? const [];
      list.add({
        'id': r['id'],
        'title': r['title'],
        'price': r['price'],
        'images': imgs,
        'city': r['city'],
        'created_at': r['created_at'],
        'pinned': false,
      });
    }
    return list.toList();
  }

  Future<void> _loadTrending({bool bypassCache = false, bool showLoading = true}) async {
    final city = _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;
    final cacheKey = city ?? 'All Zimbabwe';

    if (!bypassCache && _cachedTrending != null && _cacheTime != null && _cachedLocation == cacheKey) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age < _cacheDuration) {
        debugPrint('✅ [SWR] 使用缓存数据 (${age.inSeconds}秒前, ${_cachedTrending!.length}条)');
        if (mounted) {
          setState(() {
            _trendingRemote = _cachedTrending!;
            _isFirstLoad = false;
          });
        }

        if (age > const Duration(minutes: 1)) {
          debugPrint('🔄 [SWR] 后台刷新数据...');
          _refreshInBackground(city);
        }

        return;
      }
    }

    if (_trendingRemote.isEmpty) {
      if (mounted) {
        setState(() => _isFirstLoad = true);
      }
    } else {
      if (mounted) {
        setState(() => _isBackgroundRefreshing = true);
      }
    }

    try {
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: _featuredAdsLimit,
        latestLimit: _popularItemsLimit,
        bypassCache: bypassCache,
      );

      if (mounted) {
        setState(() {
          _trendingRemote = rows;
          _isFirstLoad = false;
          _isBackgroundRefreshing = false;
        });

        _cachedTrending = rows;
        _cacheTime = DateTime.now();
        _cachedLocation = cacheKey;
        debugPrint('✅ [Cache] 缓存已更新 (${rows.length}条)');
      }
    } catch (e) {
      debugPrint('❌ [Error] 加载数据失败: $e');
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
          _isBackgroundRefreshing = false;
        });
      }
    }
  }

  Future<void> _refreshInBackground(String? city) async {
    if (_isBackgroundRefreshing) return;

    setState(() => _isBackgroundRefreshing = true);

    try {
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: _featuredAdsLimit,
        latestLimit: _popularItemsLimit,
        bypassCache: true,
      );
      if (mounted) {
        setState(() {
          _trendingRemote = rows;
          _isBackgroundRefreshing = false;
        });
        _cachedTrending = rows;
        _cacheTime = DateTime.now();
        debugPrint('✅ [SWR] 后台刷新完成 (${rows.length}条)');
      }
    } catch (e) {
      debugPrint('❌ [SWR] 后台刷新失败: $e');
      if (mounted) {
        setState(() => _isBackgroundRefreshing = false);
      }
    }
  }

  void _navigateToCategory(String categoryId, String categoryName) {
    if (categoryId == "trending") {
      _scrollToTrending();
    } else {
      SafeNavigator.push(
        MaterialPageRoute(
          builder: (_) => CategoryProductsPage(
            categoryId: categoryId,
            categoryName: categoryName,
          ),
        ),
      );
    }
  }

  void _navigateToProductDetail(String productId) {
    SafeNavigator.push(
      MaterialPageRoute(builder: (_) => ProductDetailPage(productId: productId)),
    );
  }

  void _scrollToTrending() {
    final ctx = _trendingKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // ✅ 优化：导航到独立搜索输入页面
  void _navigateToSearchWithFocus() {
    debugPrint('[HomePage] ==================== NAVIGATE TO SEARCH ====================');
    debugPrint('[HomePage] Current keyword: "${_searchCtrl.text}"');
    debugPrint('[HomePage] Current location: "$_selectedLocation"');

    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) => _SearchInputPage(
          initialKeyword: _searchCtrl.text,
          location: _selectedLocation,
          onSearch: (keyword) {
            debugPrint('[HomePage] ==================== SEARCH CALLBACK ====================');
            debugPrint('[HomePage] Search submitted: "$keyword"');
            debugPrint('[HomePage] Location: "$_selectedLocation"');

            Navigator.of(context).pop(); // 关闭输入页面

            debugPrint('[HomePage] Navigating to SearchResultsPage...');
            SafeNavigator.push(
              MaterialPageRoute(
                builder: (_) {
                  debugPrint('[HomePage] Building SearchResultsPage');
                  return SearchResultsPage(
                    keyword: keyword,
                    location: _selectedLocation,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onTapPost() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: const Text('Login Required'),
          content: const Text('Please login to post listings.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Login')),
          ],
        ),
      );
      if (goLogin == true && mounted) {
        await SafeNavigator.pushNamed('/login');
      }
      if (Supabase.instance.client.auth.currentUser == null) return;
    }
    if (!mounted) return;
    final ok = await SafeNavigator.push(
      MaterialPageRoute(builder: (_) => const SellFormPage()),
    );
    if (ok == true && mounted) {
      await _loadTrending(bypassCache: true);
      _scrollToTrending();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final pinnedItems = _trendingRemote.where((r) => r['pinned'] == true).toList();
    final regularItems = _trendingRemote.where((r) => r['pinned'] != true).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          if (_isBackgroundRefreshing)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10.h,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(20.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14.w,
                          height: 14.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(_primaryBlue),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Updating...',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          RefreshIndicator(
            onRefresh: () async {
              await _loadTrending(bypassCache: true, showLoading: false);
            },
            color: _primaryBlue,
            backgroundColor: Colors.white,
            child: CustomScrollView(
              key: const PageStorageKey<String>('home_page_scroll'),
              controller: _scrollController,
              physics: _isFirstLoad
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildCompactHeader()),

                SliverToBoxAdapter(
                  child: Padding(
                    key: _trendingKey,
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      Platform.isIOS ? 10.h : 20.h,
                      16.w,
                      Platform.isIOS ? 8.h : 10.h,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Trending',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Icon(
                          Icons.local_fire_department,
                          color: Colors.orange[600],
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 4.h),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Icon(Icons.star, color: Colors.orange[600], size: 14.sp),
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          'Featured Ads',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(width: 4.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                          decoration: BoxDecoration(
                            color: Colors.orange[600],
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'PREMIUM',
                            style: TextStyle(
                              fontSize: 6.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  key: const ValueKey('featured_ads_grid'),
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  sliver: _buildHybridGrid(
                    items: pinnedItems,
                    isPinned: true,
                    isLoading: _isFirstLoad,
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 4.h),
                    child: Text(
                      'Popular Items',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  key: const ValueKey('popular_items_grid'),
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  sliver: _buildHybridGrid(
                    items: regularItems,
                    isPinned: false,
                    isLoading: _isFirstLoad,
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: 80.h)),
              ],
            ),
          ),
          Positioned(
            right: 16.w,
            bottom: 16.h,
            child: FloatingActionButton.extended(
              heroTag: 'post-fab',
              onPressed: _onTapPost,
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: Icon(Icons.add, size: 18.sp),
              label: Text(
                'Post Ad',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHybridGrid({
    required List<Map<String, dynamic>> items,
    required bool isPinned,
    required bool isLoading,
  }) {
    if (isLoading) {
      final skeletonCount = isPinned ? _minFeaturedPlaceholder : 6;
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8.h,
          crossAxisSpacing: 8.w,
          childAspectRatio: 0.66,
        ),
        delegate: SliverChildBuilderDelegate(
              (context, index) => _buildSkeletonCard(isPinned: isPinned),
          childCount: skeletonCount,
        ),
      );
    }

    if (items.isEmpty) {
      if (isPinned) {
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8.h,
            crossAxisSpacing: 8.w,
            childAspectRatio: 0.66,
          ),
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              if (index == 0) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stars, size: 24.sp, color: Colors.grey[400]),
                        SizedBox(height: 6.h),
                        Text(
                          'No featured ads',
                          style: TextStyle(fontSize: 10.sp, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return const SizedBox.shrink();
              }
            },
            childCount: _minFeaturedPlaceholder,
          ),
        );
      } else {
        return SliverToBoxAdapter(
          child: Container(
            height: 100.h,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_up, size: 28.sp, color: Colors.grey[400]),
                  SizedBox(height: 6.h),
                  Text(
                    'No items available',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 0.66,
      ),
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final item = items[index];
          final itemId = item['id']?.toString() ?? 'unknown_$index';

          return KeyedSubtree(
            key: ValueKey('${isPinned ? 'p' : 'r'}_$itemId'),
            child: isPinned ? _buildPremiumCard(item) : _buildRegularCard(item),
          );
        },
        childCount: items.length,
      ),
    );
  }

  Widget _buildCompactHeader() {
    final bump = _iosBump(context);
    final double headerHeight = Platform.isIOS ? 120.h : 140.h;

    return Stack(
      children: [
        Container(
          height: headerHeight + bump,
          color: _primaryBlue,
        ),
        Column(
          children: [
            SizedBox(height: bump),
            Container(
              padding: EdgeInsets.only(
                top: Platform.isIOS ? 10.h : 35.h,
                bottom: Platform.isIOS ? 10.h : 16.h,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28.w,
                    height: 28.h,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Swaply',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16.w,
                      top: Platform.isIOS ? 10.h : 12.h,
                      bottom: Platform.isIOS ? 8.h : 10.h,
                    ),
                    child: Text(
                      'What are you looking for?',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: _primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildCompactSearchSection(),
                  _buildCompactCategoriesGrid(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactSearchSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              height: 36.h,
              decoration: BoxDecoration(
                border: Border.all(color: _primaryBlue, width: 1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: DropdownButtonHideUnderline(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: DropdownButton<String>(
                    value: _selectedLocation,
                    icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 18.sp),
                    isExpanded: true,
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[800]),
                    onChanged: (v) {
                      setState(() => _selectedLocation = v!);
                      _loadTrending();
                    },
                    items: _locations
                        .map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(
                        loc,
                        style: TextStyle(fontSize: 11.sp),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),

          // ✅ 优化：点击后导航到独立搜索页面
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () {
                debugPrint('[HomePage] Search field tapped');
                _navigateToSearchWithFocus();
              },
              child: Container(
                height: 36.h,
                decoration: BoxDecoration(
                  border: Border.all(color: _primaryBlue, width: 1),
                  borderRadius: BorderRadius.circular(6.r),
                  color: Colors.grey[50],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.w),
                        child: Text(
                          _searchCtrl.text.isEmpty
                              ? 'Search products...'
                              : _searchCtrl.text,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: _searchCtrl.text.isEmpty
                                ? Colors.grey[500]
                                : Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        debugPrint('[HomePage] Search icon tapped');
                        _navigateToSearchWithFocus();
                      },
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(Icons.search, size: 18.sp, color: _primaryBlue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCategoriesGrid() {
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          const int crossAxisCount = 4;
          final double crossAxisSpacing = 6.w;
          final double mainAxisSpacing = 6.h;
          const double childAspectRatio = 1.0;
          final double padHLeft = 12.w;
          final double padHRight = 12.w;
          final double padVTop = Platform.isIOS ? 10.h : 12.h;
          final double padVBottom = Platform.isIOS ? 12.h : 16.h;

          final double usableWidth = constraints.maxWidth - padHLeft - padHRight;
          final double tileW = (usableWidth - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;
          final double tileH = tileW / childAspectRatio;

          final int rows = (_categories.length / crossAxisCount).ceil();
          final double gridCoreHeight = rows * tileH + (rows - 1) * mainAxisSpacing;
          final double gridTotalHeight = padVTop + gridCoreHeight + padVBottom;

          return SizedBox(
            height: gridTotalHeight,
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(padHLeft, padVTop, padHRight, padVBottom),
              primary: false,
              shrinkWrap: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isTrending = index == 0;

                const double iconBox = 50.0;
                const double iconSize = 34.0;
                const double iconFallbackSize = 26.0;
                const double gap = 8.0;

                return GestureDetector(
                  onTap: () => _navigateToCategory(cat['id']!, cat['label']!),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isTrending ? Colors.orange.shade50 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: isTrending ? Colors.orange.shade200 : Colors.transparent,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        final double H = c.maxHeight;
                        final double labelMax = (H - iconBox - gap).clamp(0.0, 40.h);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: iconBox,
                              height: iconBox,
                              decoration: BoxDecoration(
                                color: isTrending ? Colors.orange.shade100 : Colors.white,
                                borderRadius: BorderRadius.circular(10.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: iconSize,
                                  height: iconSize,
                                  child: Image.asset(
                                    'assets/icons/${cat['icon']}.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) {
                                      return Image.asset(
                                        'assets/icons/${cat['icon']}.jpg',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          isTrending ? Icons.local_fire_department : Icons.category,
                                          size: iconFallbackSize,
                                          color: isTrending ? Colors.orange : Colors.grey,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: gap),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: labelMax),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2.w),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text(
                                    cat['label']!,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonCard({bool isPinned = false}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1500),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: isPinned ? Border.all(color: Colors.orange.shade300, width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60.w,
                    height: 16.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Container(
                    width: double.infinity,
                    height: 12.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    width: 80.w,
                    height: 12.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Container(
                    width: 50.w,
                    height: 10.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumCard(Map<String, dynamic> r) {
    final images = (r['images'] as List?) ?? const [];
    final img = images.isNotEmpty ? images.first.toString() : null;
    final priceText = _formatPrice(r['price']);
    return GestureDetector(
      onTap: () => _navigateToProductDetail(r['id'].toString()),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildOptimizedImageWidget(img),
                  Positioned(
                    top: 6.h,
                    left: 6.w,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.orange[600],
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 8.sp, color: Colors.white),
                          SizedBox(width: 2.w),
                          Text(
                            'PINNED',
                            style: TextStyle(
                              fontSize: 7.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(8.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priceText.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: _successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(color: _successGreen.withOpacity(0.3)),
                      ),
                      child: Text(
                        priceText,
                        style: TextStyle(
                          color: _successGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.sp,
                        ),
                      ),
                    ),
                  SizedBox(height: 4.h),
                  Text(
                    r['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 8.sp, color: Colors.grey[600]),
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

  Widget _buildRegularCard(Map<String, dynamic> r) {
    final images = (r['images'] as List?) ?? const [];
    final img = images.isNotEmpty ? images.first.toString() : null;
    final priceText = _formatPrice(r['price']);
    return GestureDetector(
      onTap: () => _navigateToProductDetail(r['id'].toString()),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildOptimizedImageWidget(img),
            ),
            Padding(
              padding: EdgeInsets.all(6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priceText.isNotEmpty)
                    Text(
                      priceText,
                      style: TextStyle(
                        color: _successGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  SizedBox(height: 2.h),
                  Text(
                    r['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 1.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 8.sp, color: Colors.grey[600]),
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

  Widget _buildOptimizedImageWidget(String? src) {
    if (src == null || src.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
        ),
        child: Center(
          child: Icon(Icons.image, size: 24.sp, color: Colors.grey[400]),
        ),
      );
    }

    if (!src.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
        child: Image.asset(
          src,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 20.sp, color: Colors.grey[400]),
                  SizedBox(height: 2.h),
                  Text(
                    'Image not found',
                    style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
      child: CachedNetworkImage(
        imageUrl: src,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        maxHeightDiskCache: 400,
        maxWidthDiskCache: 400,
        memCacheWidth: 400,
        memCacheHeight: 400,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[200],
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 20.sp, color: Colors.grey[400]),
                SizedBox(height: 2.h),
                Text(
                  'Image failed to load',
                  style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ 独立的搜索输入页面（轻量级，避免主页卡顿）
class _SearchInputPage extends StatefulWidget {
  final String initialKeyword;
  final String location;
  final Function(String) onSearch;

  const _SearchInputPage({
    required this.initialKeyword,
    required this.location,
    required this.onSearch,
  });

  @override
  State<_SearchInputPage> createState() => _SearchInputPageState();
}

class _SearchInputPageState extends State<_SearchInputPage> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  static const Color _primaryBlue = Color(0xFF1877F2);

  @override
  void initState() {
    super.initState();
    debugPrint('[SearchInputPage] ==================== INIT ====================');
    debugPrint('[SearchInputPage] Initial keyword: "${widget.initialKeyword}"');
    debugPrint('[SearchInputPage] Location: "${widget.location}"');

    _controller = TextEditingController(text: widget.initialKeyword);

    // ✅ 页面加载后自动获得焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[SearchInputPage] Requesting focus...');
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    debugPrint('[SearchInputPage] Disposing...');
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSearch() {
    final keyword = _controller.text.trim();
    debugPrint('[SearchInputPage] ==================== SUBMIT ====================');
    debugPrint('[SearchInputPage] Keyword: "$keyword"');

    if (keyword.isEmpty) {
      debugPrint('[SearchInputPage] ❌ Keyword is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter search keywords'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    debugPrint('[SearchInputPage] ✅ Calling onSearch callback');
    widget.onSearch(keyword);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            debugPrint('[SearchInputPage] Back button pressed');
            Navigator.pop(context);
          },
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search products...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: () {
                debugPrint('[SearchInputPage] Clear button pressed');
                _controller.clear();
                setState(() {});
              },
            )
                : null,
          ),
          onChanged: (value) {
            debugPrint('[SearchInputPage] Text changed: "$value"');
            setState(() {});
          },
          onSubmitted: (_) => _handleSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _handleSearch,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 48.sp, color: Colors.grey[300]),
              SizedBox(height: 16.h),
              Text(
                'Enter keywords to search',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: _primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, size: 14.sp, color: _primaryBlue),
                    SizedBox(width: 4.w),
                    Text(
                      widget.location,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: _primaryBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
