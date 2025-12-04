// lib/pages/home_page.dart
// ✅ [主页停滞修复] 优化首次加载体验，始终显示骨架屏
// ✅ [性能优化] 优化数据加载逻辑，减少主线程阻塞
// ✅ [UI优化] Popular Items 标题始终显示，不跟随图片动画

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  // ✅ [性能优化] 缓存机制
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
    {
      "id": "seeking_work_cvs",
      "icon": "seeking_work_cvs",
      "label": "Jobs Seeking"
    },
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
    {
      "id": "repair_construction",
      "icon": "repair_construction",
      "label": "Repair"
    },
    {
      "id": "leisure_activities",
      "icon": "leisure_activities",
      "label": "Leisure"
    },
    {
      "id": "food_agriculture_drinks",
      "icon": "food_agriculture_drinks",
      "label": "Food & Drinks"
    },
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

    // ✅ [主页停滞修复] 首次加载显示骨架屏（showLoading: true）
    _loadTrending(showLoading: true);

    _listingPubSub = ListingEventsBus.instance.stream.listen((e) {
      if (e is ListingPublishedEvent) {
        _loadTrending(bypassCache: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 保留占位
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    int pinnedLimit = 10,
    int latestLimit = 30,
    bool bypassCache = false,
  }) async {
    final startTime = DateTime.now();

    final results = await Future.wait([
      CouponService.getTrendingPinnedAds(
        city: city,
        limit: pinnedLimit,
      ),
      ListingApi.fetchListings(
        city: city,
        limit: latestLimit,
        offset: 0,
        orderBy: 'created_at',
        ascending: false,
        status: 'active',
        forceNetwork: bypassCache,
      ),
    ]);

    final pinnedAds = results[0] as List;
    final latest = results[1] as List<Map<String, dynamic>>;

    final duration = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('✅ [Performance] 数据请求耗时: ${duration}ms (pinned: ${pinnedAds.length}, latest: ${latest.length})');

    final list = <Map<String, dynamic>>[];
    for (final e in pinnedAds) {
      final l = (e['listings'] as Map<String, dynamic>? ?? {});
      if (l.isEmpty) continue;
      final imgs =
          (l['images'] as List?) ?? (l['image_urls'] as List?) ?? const [];
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
      final imgs =
          (r['images'] as List?) ?? (r['image_urls'] as List?) ?? const [];
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
    final city =
    _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;
    final cacheKey = city ?? 'All Zimbabwe';

    // ✅ [性能优化] 检查缓存
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
        return;
      }
    }

    // ✅ [主页停滞修复] 始终显示loading状态（骨架屏）
    if (showLoading && mounted) {
      setState(() => _loadingTrending = true);
    }

    try {
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: 10,
        latestLimit: 30,
        bypassCache: bypassCache,
      );
      if (mounted) {
        setState(() => _trendingRemote = rows);
        _cachedTrending = rows;
        _cacheTime = DateTime.now();
        _cachedLocation = cacheKey;
        debugPrint('✅ [Cache] 缓存已更新 (${rows.length}条)');

        // ✅ [性能优化] 数据加载完成后才启动fade动画
        if (_trendingRemote.isNotEmpty) {
          _fadeController.forward();
        }
      }
    } catch (e) {
      debugPrint('❌ [Error] 加载数据失败: $e');
    } finally {
      if (mounted) setState(() => _loadingTrending = false);
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
      MaterialPageRoute(
          builder: (_) => ProductDetailPage(productId: productId)),
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
        builder: (_) =>
            SearchResultsPage(keyword: keyword, location: _selectedLocation),
      ),
    );
  }

  Future<void> _onTapPost() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: const Text('Login Required'),
          content: const Text('Please login to post listings.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Login')),
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          ListView(
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
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.grey[600], size: 18.sp),
                    isExpanded: true,
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[800]),
                    onChanged: (v) {
                      setState(() => _selectedLocation = v!);
                      _loadTrending();
                    },
                    items: _locations
                        .map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc,
                          style: TextStyle(fontSize: 11.sp),
                          overflow: TextOverflow.ellipsis),
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
                          hintStyle: TextStyle(
                              color: Colors.grey[500], fontSize: 11.sp),
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
                      child:
                      Icon(Icons.search, size: 18.sp, color: _primaryBlue),
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
          final double mainAxisSpacing  = 6.h;
          const double childAspectRatio = 1.0;
          final double padHLeft  = 12.w;
          final double padHRight = 12.w;
          final double padVTop   = Platform.isIOS ? 10.h : 12.h;
          final double padVBottom= Platform.isIOS ? 12.h : 16.h;

          final double usableWidth =
              constraints.maxWidth - padHLeft - padHRight;
          final double tileW = (usableWidth -
              crossAxisSpacing * (crossAxisCount - 1)) /
              crossAxisCount;
          final double tileH = tileW / childAspectRatio;

          final int rows =
          (_categories.length / crossAxisCount).ceil();
          final double gridCoreHeight =
              rows * tileH + (rows - 1) * mainAxisSpacing;
          final double gridTotalHeight =
              padVTop + gridCoreHeight + padVBottom;

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
                        color: isTrending
                            ? Colors.orange.shade200
                            : Colors.transparent,
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
                                color: isTrending
                                    ? Colors.orange.shade100
                                    : Colors.white,
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
                                          isTrending
                                              ? Icons.local_fire_department
                                              : Icons.category,
                                          size: iconFallbackSize,
                                          color: isTrending
                                              ? Colors.orange
                                              : Colors.grey,
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

  // ✅ [UI优化] 修改此方法：Popular Items 标题移到外面，始终显示
  Widget _buildTrendingSection() {
    // 预先计算是否有 pinned 和 regular items（用于判断是否显示标题）
    final hasPinned = _trendingRemote.where((r) => r['pinned'] == true).isNotEmpty;
    final hasRegular = _trendingRemote.where((r) => r['pinned'] != true).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trending 标题（始终显示）
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

        // ✅ Featured Ads 标题（如果有数据则显示，loading时隐藏）
        if (!_loadingTrending && hasPinned) ...[
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
        ],

        // ✅ Popular Items 标题（始终显示，不参与动画）
        if (_loadingTrending || hasRegular) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.w,
              (_loadingTrending || hasPinned) ? 16.h : 0,  // loading时或有featured ads时加间距
              16.w,
              Platform.isIOS ? 2.h : 8.h,
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
        ],

        // 图片网格区域（保持loading和fade动画）
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child:
          _loadingTrending ? _buildTrendingLoading() : _buildTrendingGrid(),
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
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.70,
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

  // ✅ [UI优化] 修改此方法：移除 Popular Items 标题（已移到外面）
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
          // Featured Ads 网格（如果有）
          if (_trendingRemote.where((r) => r['pinned'] == true).isNotEmpty) ...[
            _buildFeaturedTrendingGrid(),
            Container(
              margin: EdgeInsets.symmetric(vertical: 12.h),
              height: 1.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.orange[300]!,
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ],
          // Popular Items 网格（如果有）
          if (_trendingRemote.where((r) => r['pinned'] != true).isNotEmpty) ...[
            _buildRegularTrendingGrid(),
          ],
        ],
      ),
    );
  }

  // ✅ [UI优化] 新方法：只返回 Featured Ads 网格（标题已移到外面）
  Widget _buildFeaturedTrendingGrid() {
    final pinnedItems =
    _trendingRemote.where((r) => r['pinned'] == true).toList();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
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
    final regularItems =
    _trendingRemote.where((r) => r['pinned'] != true).toList();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: Platform.isIOS ? EdgeInsets.zero : null,
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
                      padding:
                      EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
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
                      padding:
                      EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: _successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4.r),
                        border:
                        Border.all(color: _successGreen.withOpacity(0.3)),
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
                      Icon(Icons.location_on,
                          size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 8.sp, color: Colors.grey[600]),
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
                      Icon(Icons.location_on,
                          size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 1.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 8.sp, color: Colors.grey[600]),
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
                  Text('Image not found',
                      style: TextStyle(fontSize: 8.sp, color: Colors.grey[500])),
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
                Text('Image failed to load',
                    style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
