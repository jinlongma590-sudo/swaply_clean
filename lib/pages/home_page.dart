// lib/pages/home_page.dart
// ✅ [架构符合] 符合 Swaply 架构，HomePage 只负责数据展示
// ✅ [滚动优化] 增强滚动位置保持，多重保护机制
// ✅ [性能优化] 缓存 + 骨架屏 + 图片优化
// ✅ [用户体验] 滚动位置不会因为数据加载而重置

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

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _trendingKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String _selectedLocation = 'All Zimbabwe';

  List<Map<String, dynamic>> _trendingRemote = [];
  bool _loadingTrending = false;
  StreamSubscription? _listingPubSub;

  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);

  bool _welcomeChecked = false;

  static List<Map<String, dynamic>>? _cachedTrending;
  static DateTime? _cacheTime;
  static String? _cachedLocation;
  static const _cacheDuration = Duration(minutes: 2);

  // ✅ [滚动优化] 增强的滚动位置管理
  double _savedScrollPosition = 0.0;
  bool _isRestoringScroll = false;
  bool _scrollPositionRestored = false;
  int _restoreAttempts = 0;
  static const int _maxRestoreAttempts = 3;

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
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _scrollController.addListener(_onScroll);
    _loadTrending(showLoading: true);

    _listingPubSub = ListingEventsBus.instance.stream.listen((e) {
      if (e is ListingPublishedEvent) {
        _loadTrending(bypassCache: true);
      }
    });
  }

  // ✅ [滚动优化] 增强的滚动监听器
  void _onScroll() {
    if (_isRestoringScroll) return;
    if (!_scrollController.hasClients) return;

    final currentPosition = _scrollController.position.pixels;

    // ✅ 只在滚动位置真正变化时才保存
    if ((currentPosition - _savedScrollPosition).abs() > 5.0) {
      _savedScrollPosition = currentPosition;

      if (mounted) {
        debugPrint('💾 [Scroll] 保存滚动位置: ${_savedScrollPosition.toStringAsFixed(1)}');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 保留占位
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchCtrl.dispose();
    _fadeController.dispose();
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

    // 检查缓存
    if (!bypassCache && _cachedTrending != null && _cacheTime != null && _cachedLocation == cacheKey) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age < _cacheDuration) {
        debugPrint('✅ [Cache] 使用缓存数据 (${age.inSeconds}秒前, ${_cachedTrending!.length}条)');
        if (mounted) {
          setState(() {
            _trendingRemote = _cachedTrending!;
            _loadingTrending = false;
          });
          if (_trendingRemote.isNotEmpty) {
            _fadeController.forward();
          }
        }

        if (age > const Duration(minutes: 1)) {
          debugPrint('🔄 [Cache] 后台刷新数据...');
          _refreshInBackground(city);
        }

        return;
      }
    }

    // ✅ [滚动优化] 保存当前滚动位置（在加载开始前）
    if (_scrollController.hasClients) {
      _savedScrollPosition = _scrollController.position.pixels;
      debugPrint('💾 [Scroll] 数据加载前保存位置: ${_savedScrollPosition.toStringAsFixed(1)}');
    }

    if (showLoading && mounted) {
      setState(() => _loadingTrending = true);
    }

    try {
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: _featuredAdsLimit,
        latestLimit: _popularItemsLimit,
        bypassCache: bypassCache,
      );
      if (mounted) {
        setState(() => _trendingRemote = rows);
        _cachedTrending = rows;
        _cacheTime = DateTime.now();
        _cachedLocation = cacheKey;
        debugPrint('✅ [Cache] 缓存已更新 (${rows.length}条)');

        if (_trendingRemote.isNotEmpty) {
          _fadeController.forward();
        }

        // ✅ [滚动优化] 数据加载完成后恢复滚动位置
        _restoreScrollPositionEnhanced();
      }
    } catch (e) {
      debugPrint('❌ [Error] 加载数据失败: $e');
    } finally {
      if (mounted) setState(() => _loadingTrending = false);
    }
  }

  // ✅ [滚动优化] 增强的滚动位置恢复（多重保护 + 多次尝试）
  void _restoreScrollPositionEnhanced() {
    if (_savedScrollPosition <= 0 || !_scrollController.hasClients) {
      _scrollPositionRestored = true;
      return;
    }

    _isRestoringScroll = true;
    _scrollPositionRestored = false;
    _restoreAttempts = 0;

    debugPrint('🔄 [Scroll] 开始恢复滚动位置: ${_savedScrollPosition.toStringAsFixed(1)}');

    // ✅ 第一次尝试：立即恢复（postFrameCallback）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptRestoreScroll(delay: 0);
    });

    // ✅ 第二次尝试：100ms 后（确保布局稳定）
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scrollPositionRestored && _restoreAttempts < _maxRestoreAttempts) {
        _attemptRestoreScroll(delay: 1);
      }
    });

    // ✅ 第三次尝试：300ms 后（图片加载可能影响布局）
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_scrollPositionRestored && _restoreAttempts < _maxRestoreAttempts) {
        _attemptRestoreScroll(delay: 2);
      }
    });
  }

  void _attemptRestoreScroll({required int delay}) {
    if (!mounted || !_scrollController.hasClients || _scrollPositionRestored) {
      return;
    }

    _restoreAttempts++;

    try {
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final targetPosition = _savedScrollPosition.clamp(0.0, maxScroll);

      // ✅ 关键优化：只在位置真正不同时才跳转（避免微小差异导致的闪烁）
      final diff = (currentScroll - targetPosition).abs();
      if (diff < 2.0) {
        debugPrint('✅ [Scroll] 位置已正确 (diff: ${diff.toStringAsFixed(1)}px) - 尝试 $_restoreAttempts/$_maxRestoreAttempts');
        _scrollPositionRestored = true;
        _isRestoringScroll = false;
        return;
      }

      // ✅ 检查布局是否稳定（maxScrollExtent 应该大于 0）
      if (maxScroll <= 0) {
        debugPrint('⚠️ [Scroll] 布局未稳定 (maxScroll=$maxScroll) - 尝试 $_restoreAttempts/$_maxRestoreAttempts');
        return;
      }

      _scrollController.jumpTo(targetPosition);
      debugPrint('✅ [Scroll] 位置已恢复: ${targetPosition.toStringAsFixed(1)} (max: ${maxScroll.toStringAsFixed(1)}, diff: ${diff.toStringAsFixed(1)}px) - 尝试 $_restoreAttempts');

      _scrollPositionRestored = true;

      // ✅ 延迟清除恢复标志，避免用户快速滚动时被打断
      Future.delayed(const Duration(milliseconds: 100), () {
        _isRestoringScroll = false;
      });
    } catch (e) {
      debugPrint('❌ [Scroll] 恢复失败 (尝试 $_restoreAttempts): $e');
      if (_restoreAttempts >= _maxRestoreAttempts) {
        _isRestoringScroll = false;
        _scrollPositionRestored = true;
      }
    }
  }

  Future<void> _refreshInBackground(String? city) async {
    try {
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: _featuredAdsLimit,
        latestLimit: _popularItemsLimit,
        bypassCache: true,
      );
      if (mounted) {
        // ✅ [滚动优化] 后台刷新时也保存滚动位置
        if (_scrollController.hasClients) {
          _savedScrollPosition = _scrollController.position.pixels;
          debugPrint('💾 [Scroll] 后台刷新前保存位置: ${_savedScrollPosition.toStringAsFixed(1)}');
        }

        setState(() {
          _trendingRemote = rows;
          _cachedTrending = rows;
          _cacheTime = DateTime.now();
        });
        debugPrint('✅ [Cache] 后台刷新完成 (${rows.length}条)');

        // ✅ [滚动优化] 恢复滚动位置
        _restoreScrollPositionEnhanced();
      }
    } catch (e) {
      debugPrint('❌ [Cache] 后台刷新失败: $e');
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

  void _performSearch() {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) => SearchResultsPage(keyword: keyword, location: _selectedLocation),
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

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          ListView(
            key: const PageStorageKey<String>('home_page_list'),
            controller: _scrollController,
            padding: EdgeInsets.zero,
            children: [
              _buildCompactHeader(),
              _buildTrendingSection(),
              SizedBox(height: 80.h),
            ],
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
          Expanded(
            flex: 3,
            child: Container(
              height: 36.h,
              decoration: BoxDecoration(
                border: Border.all(color: _primaryBlue, width: 1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(fontSize: 12.sp),
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 11.sp),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _performSearch,
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      child: Icon(Icons.search, size: 18.sp, color: _primaryBlue),
                    ),
                  ),
                ],
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

  Widget _buildTrendingSection() {
    final hasPinned = _trendingRemote.where((r) => r['pinned'] == true).isNotEmpty;
    final hasRegular = _trendingRemote.where((r) => r['pinned'] != true).isNotEmpty;

    final double popularItemsTopPadding = hasPinned ? 16.h : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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

        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
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

        Padding(
          padding: EdgeInsets.fromLTRB(
            16.w,
            popularItemsTopPadding,
            16.w,
            0,
          ),
          child: Text(
            'Popular Items',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: _loadingTrending ? _buildTrendingLoading() : _buildTrendingGrid(),
        ),
      ],
    );
  }

  Widget _buildTrendingLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1500),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.66,
          crossAxisSpacing: 8.w,
          mainAxisSpacing: 8.h,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
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
      ),
    );
  }

  Widget _buildTrendingGrid() {
    if (_trendingRemote.isEmpty) {
      return Container(
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
                'No trending items available',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trendingRemote.where((r) => r['pinned'] == true).isNotEmpty) ...[
            _buildFeaturedTrendingGrid(),
            Container(
              margin: EdgeInsets.symmetric(vertical: 12.h),
              height: 1.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.orange[300]!, Colors.transparent],
                ),
              ),
            ),
          ],
          if (_trendingRemote.where((r) => r['pinned'] != true).isNotEmpty) ...[
            _buildRegularTrendingGrid(),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturedTrendingGrid() {
    final pinnedItems = _trendingRemote.where((r) => r['pinned'] == true).toList();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 0.66,
      ),
      itemCount: pinnedItems.length,
      itemBuilder: (context, i) {
        final r = pinnedItems[i];
        return _buildPremiumCard(r);
      },
    );
  }

  Widget _buildRegularTrendingGrid() {
    final regularItems = _trendingRemote.where((r) => r['pinned'] != true).toList();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 0.66,
      ),
      itemCount: regularItems.length,
      itemBuilder: (context, i) {
        final r = regularItems[i];
        return _buildRegularCard(r);
      },
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
