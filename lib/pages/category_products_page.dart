// lib/pages/category_products_page.dart
// 使用Facebook亮蓝色和Jiji风格的自动图片调整功能 - 更紧凑设计
// ✅ [DONE] 与 Sell / Notifications / Saved 一致的 iOS 顶部距离（statusBar + 44）
// ✅ [UPDATED] 商品图片展示尺寸与主页保持一致（childAspectRatio: 0.66）
// ✅ [P0性能优化] 分页提前加载（80%位置触发，而非200px）
// ✅ [P1性能优化] 图片加载优化 - 使用 CachedNetworkImage + memCache

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart'; // v1.0.1: 轮播组件
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/listing_api.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/widgets/pinned_ad_card.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/core/qa_keys.dart'; // QaKeys
import 'package:swaply/utils/image_utils.dart'; // 图片优化工具

class CategoryProductsPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String _selectedSort = 'newest';
  String _selectedLocation = 'All Zimbabwe';

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Facebook亮蓝色配色方案
  static const Color _primaryBlue = Color(0xFF1877F2); // Facebook亮蓝色
  static const Color _lightBlue = Color(0xFFE3F2FD);
  static const Color _successGreen = Color(0xFF4CAF50);

  final List<String> _locations = const [
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

  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _pinnedAds = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadingPinned = false;
  bool _hasMore = true;
  String? _error;

  int? _totalCount;

  static const int _pageSize = 24;
  int _offset = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _loadInitial();
    _loadPinnedAds();

    // ✅ [P0优化] 分页提前加载 - 改为80%位置触发，而非固定200px
    _scroll.addListener(() {
      final position = _scroll.position;
      final threshold = position.maxScrollExtent * 0.8; // 80%位置触发

      if (position.pixels >= threshold) {
        _loadMore();
      }
    });

    // 开始动画
    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 当应用从暂停或非活动状态恢复时，刷新置顶广告数据
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [CategoryTabSwitch] 应用恢复，静默刷新置顶广告数据');
      // 静默刷新，不显示加载状态
      _loadPinnedAds();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _categoryIdToDb(String id) {
    const map = {
      'vehicles': 'Vehicles',
      'property': 'Property',
      'beauty_personal_care': 'Beauty and Personal Care',
      'jobs': 'Jobs',
      'babies_kids': 'Babies and Kids',
      'services': 'Services',
      'leisure_activities': 'Leisure Activities',
      'repair_construction': 'Repair and Construction',
      'home_furniture_appliances': 'Home Furniture and Appliances',
      'pets': 'Pets',
      'electronics': 'Electronics',
      'phones_tablets': 'Phones and Tablets',
      'seeking_work_cvs': 'Seeking Work and CVs',
      'fashion': 'Fashion',
      'food_agriculture_drinks': 'Food Agriculture and Drinks',
    };
    return map[id] ?? widget.categoryName;
  }

  /// 修复的价格格式化函数
  String _formatPrice(dynamic priceData) {
    if (priceData == null) return '';

    if (priceData is num) {
      if (priceData == 0) return 'Free';
      return '\$${priceData.toStringAsFixed(0)}';
    }

    if (priceData is String) {
      if (priceData.toLowerCase().contains('free') || priceData == '0') {
        return 'Free';
      }

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

  /* ============== 云端置顶广告 ============== */
  Future<void> _loadPinnedAds() async {
    setState(() => _loadingPinned = true);
    try {
      final categoryDb = _categoryIdToDb(widget.categoryId);
      final city =
          _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;

      final pinnedAds = await CouponService.getCategoryPinnedAds(
        category: categoryDb,
        city: city,
        limit: 20, // v1.0.1: 改为20，实现无限池轮播
      );

      setState(() => _pinnedAds = pinnedAds);
    } catch (e) {
      debugPrint('Error loading pinned ads: $e');
    } finally {
      if (mounted) setState(() => _loadingPinned = false);
    }
  }

  /* ============== 云端列表 ============== */

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _offset = 0;
      _hasMore = true;
      _totalCount = null;
    });

    try {
      final futures = <Future>[];
      futures.add(_fetchPage(offset: 0).then((list) {
        _items.addAll(list);
        _sortInMemory();
        _hasMore = list.length >= _pageSize;
        _offset = list.length;
      }));
      futures.add(_refreshTotalCount());
      await Future.wait(futures);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final list = await _fetchPage(offset: _offset);
      setState(() {
        _items.addAll(list);
        _sortInMemory();
        _hasMore = list.length >= _pageSize;
        _offset += list.length;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refreshTotalCount() async {
    final categoryDb = _categoryIdToDb(widget.categoryId);
    final city = _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;
    final total =
        await ListingApi.countListings(category: categoryDb, city: city);
    if (mounted) setState(() => _totalCount = total);
  }

  Future<List<Map<String, dynamic>>> _fetchPage({required int offset}) async {
    final categoryDb = _categoryIdToDb(widget.categoryId);
    final city = _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;

    String orderBy = 'created_at';
    bool ascending = false;
    switch (_selectedSort) {
      case 'price_low':
        orderBy = 'price';
        ascending = true;
        break;
      case 'price_high':
        orderBy = 'price';
        ascending = false;
        break;
      default:
        orderBy = 'created_at';
        ascending = false;
    }

    final rows = await ListingApi.fetchListings(
      category: categoryDb,
      city: city,
      limit: _pageSize,
      offset: offset,
      orderBy: orderBy,
      ascending: ascending,
      status: 'active',
    );

    return rows.map<Map<String, dynamic>>((r) {
      final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
      final priceText = _formatPrice(r['price']);
      final imgs = (r['images'] as List?) ??
          (r['image_urls'] as List?) ??
          const <String>[];

      return {
        'id': r['id'],
        'title': r['title'] ?? '',
        'price': priceText,
        'price_num': priceNum,
        'location': r['city'] ?? '',
        'images': List<String>.from(imgs.map((e) => e.toString())),
        'postedDate': r['created_at'] ?? r['posted_at'],
        'full': r,
      };
    }).toList();
  }

  /* ---------- 前端排序 ---------- */
  void _sortInMemory() {
    if (_items.isEmpty) return;
    if (_selectedSort == 'price_low') {
      _items.sort((a, b) {
        final an = (a['price_num'] as num?) ?? 1e15;
        final bn = (b['price_num'] as num?) ?? 1e15;
        return an.compareTo(bn);
      });
    } else if (_selectedSort == 'price_high') {
      _items.sort((a, b) {
        final an = (a['price_num'] as num?) ?? -1e15;
        final bn = (b['price_num'] as num?) ?? -1e15;
        return bn.compareTo(an);
      });
    } else {
      _items.sort((a, b) {
        final sa = (a['postedDate'] ?? '').toString();
        final sb = (b['postedDate'] ?? '').toString();
        DateTime? da, db;
        try {
          da = DateTime.tryParse(sa);
        } catch (_) {}
        try {
          db = DateTime.tryParse(sb);
        } catch (_) {}
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
    }
  }

  /* ========================= UI ========================= */

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 6.h),
            Container(
              width: 28.w,
              height: 3.h,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                'Sort by',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
            ),
            _sortTile('Newest First', 'newest', Icons.access_time),
            _sortTile('Price: Low to High', 'price_low', Icons.arrow_upward),
            _sortTile('Price: High to Low', 'price_high', Icons.arrow_downward),
            SizedBox(height: 16.h),
          ],
        ),
      ),
    );
  }

  ListTile _sortTile(String title, String value, IconData icon) {
    final selected = _selectedSort == value;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? _primaryBlue : Colors.grey[600],
        size: 18.sp,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? _primaryBlue : Colors.grey[800],
          fontSize: 13.sp,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: _primaryBlue, size: 18.sp)
          : null,
      onTap: () {
        setState(() => _selectedSort = value);
        Navigator.pop(context);
        _sortInMemory();
      },
    );
  }

  void _openLocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 6.h),
            Container(
              width: 28.w,
              height: 3.h,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                'Select Location',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _locations.length,
                itemBuilder: (context, index) {
                  final loc = _locations[index];
                  final selected = _selectedLocation == loc;
                  return ListTile(
                    leading: Icon(
                      Icons.location_on,
                      color: selected ? _primaryBlue : Colors.grey[600],
                      size: 18.sp,
                    ),
                    title: Text(
                      loc,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? _primaryBlue : Colors.grey[800],
                        fontSize: 13.sp,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle,
                            color: _primaryBlue, size: 18.sp)
                        : null,
                    onTap: () {
                      setState(() => _selectedLocation = loc);
                      Navigator.pop(context);
                      _loadInitial();
                      _loadPinnedAds();
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildCompactAppBar(),
      body: Column(
        children: [
          _buildCompactFilterBar(),
          _buildCompactCountBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadInitial();
                await _loadPinnedAds();
              },
              color: _primaryBlue,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildCompactAppBar() {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (!isIOS) {
      // Android / Web：系统 AppBar
      return AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1877F2),
        foregroundColor: Colors.white,
        toolbarHeight: 44.h,
        title: Text(
          widget.categoryName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16.sp,
          ),
        ),
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.sp),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.white, size: 20.sp),
            onPressed: () {
              /* TODO: search */
            },
          ),
          SizedBox(width: 2.w),
        ],
      );
    }

    // iOS：自定义头部（认证页标准 44pt Row 布局）
    const double kNavBarHeight = 44.0;
    const double kButtonSize = 32.0;
    const double kSidePadding = 16.0;
    const double kButtonSpacing = 12.0;

    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white),
        ),
      ),
    );

    final Widget iosSearchButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () {
          /* TODO: search */
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.search, size: 20.sp, color: Colors.white),
        ),
      ),
    );

    final Widget iosTitle = Expanded(
      child: Text(
        widget.categoryName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16.sp,
        ),
      ),
    );

    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight),
      child: Container(
        color: const Color(0xFF1877F2),
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: kNavBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iosBackButton,
                const SizedBox(width: kButtonSpacing),
                iosTitle,
                const SizedBox(width: kButtonSpacing),
                iosSearchButton,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactFilterBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openLocationSheet,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(6.r),
                  color: Colors.grey[50],
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 14.sp, color: _primaryBlue),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        _selectedLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down,
                        color: Colors.grey[600], size: 18.sp),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _openSortSheet,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(6.r),
                color: Colors.grey[50],
              ),
              child: Row(
                children: [
                  Icon(Icons.sort, size: 14.sp, color: _primaryBlue),
                  SizedBox(width: 4.w),
                  Text(
                    'Sort',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
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

  Widget _buildCompactCountBar() {
    return Container(
      alignment: Alignment.centerLeft,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        children: [
          if (_totalCount == null)
            SizedBox(
              width: 12.w,
              height: 12.h,
              child: const CircularProgressIndicator(
                  strokeWidth: 2, color: _primaryBlue),
            )
          else ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: _primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: _primaryBlue.withOpacity(0.3)),
              ),
              child: Text(
                '$_totalCount ${_totalCount == 1 ? 'ad' : 'ads'} found',
                style: TextStyle(
                  color: _primaryBlue,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_pinnedAds.isNotEmpty) ...[
              SizedBox(width: 6.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange[300]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin, size: 8.sp, color: Colors.orange[700]),
                    SizedBox(width: 1.w),
                    Text(
                      '${_pinnedAds.length} featured',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 8.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty && _pinnedAds.isEmpty) {
      return _buildSkeleton();
    }
    if (_error != null) {
      return _buildErrorState();
    }
    if (_items.isEmpty && _pinnedAds.isEmpty && !_loading) {
      return _buildEmptyState();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            // 特色广告区域 - 垂直网格广告墙
            if (_pinnedAds.isNotEmpty || _loadingPinned) ...[
              // 标题
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 6.h),
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
              // 内容 - 根据状态显示SliverGrid或加载状态
              if (_loadingPinned)
                SliverToBoxAdapter(child: _buildPinnedAdsLoading())
              else if (_pinnedAds.isEmpty)
                SliverToBoxAdapter(child: const SizedBox.shrink())
              else
                _buildPinnedAdsSliver(),
            ],

            // 常规广告区域
            if (_items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
                  child: Text(
                    'All Listings',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ),

            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.66,
                  crossAxisSpacing: 8.w,
                  mainAxisSpacing: 8.h,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i >= _items.length) return _buildLoadingTile();
                    final p = _items[i];
                    return _buildProductCard(p);
                  },
                  childCount: _items.length + (_loadingMore ? 1 : 0),
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 12.h)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 6.h),
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
        if (_loadingPinned) _buildPinnedAdsLoading() else _buildPinnedAdsGrid(),
        if (_pinnedAds.isNotEmpty) ...[
          SizedBox(height: 12.h),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 12.w),
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
      ],
    );
  }

  Widget _buildPinnedAdsGrid() {
    if (_pinnedAds.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 改为和普通商品卡片一致的网格布局（一行两个，不横向滑动）
    // 显示20个随机置顶商品（10行×2列）
    final displayAds = _pinnedAds.take(20).toList(); // 最多显示20个
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(), // 禁止滚动
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // 一行两个
          childAspectRatio: 0.66, // 与普通商品卡片完全一致
          crossAxisSpacing: 8.w, // 横向间距
          mainAxisSpacing: 8.h, // 纵向间距
        ),
        itemCount: displayAds.length,
        itemBuilder: (context, index) {
          final pinnedAd = displayAds[index];
          final listing = pinnedAd['listings'] as Map<String, dynamic>;
          
          return PinnedAdCard(
            listingData: listing,
            pinnedData: pinnedAd,
            onTap: () => _openDetail({
              'id': listing['id'],
              'title': listing['title'],
              'price': _formatPrice(listing['price']),
              'location': listing['city'],
              'images': listing['images'],
              'full': listing,
            }),
          );
        },
      ),
    );
  }

  /// 构建置顶广告的SliverGrid（垂直网格广告墙）
  /// 返回SliverGrid，用于直接插入CustomScrollView
  Widget _buildPinnedAdsSliver() {
    if (_pinnedAds.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    
    // 显示20个随机置顶商品（10行×2列）
    final displayAds = _pinnedAds.take(20).toList(); // 最多显示20个
    
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 一行两个
        childAspectRatio: 0.66, // 与普通商品卡片完全一致
        crossAxisSpacing: 8.w, // 横向间距
        mainAxisSpacing: 8.h, // 纵向间距
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final pinnedAd = displayAds[index];
          final listing = pinnedAd['listings'] as Map<String, dynamic>;
          
          return PinnedAdCard(
            listingData: listing,
            pinnedData: pinnedAd,
            onTap: () => _openDetail({
              'id': listing['id'],
              'title': listing['title'],
              'price': _formatPrice(listing['price']),
              'location': listing['city'],
              'images': listing['images'],
              'full': listing,
            }),
          );
        },
        childCount: displayAds.length,
      ),
    );
  }

  Widget _buildPinnedAdsLoading() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.66,
          crossAxisSpacing: 8.w,
          mainAxisSpacing: 8.h,
        ),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: Colors.orange[300]!, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(10.r)),
                    ),
                    child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _primaryBlue)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12.h,
                        width: 60.w,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        height: 10.h,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        height: 8.h,
                        width: 50.w,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    return GestureDetector(
      onTap: () => _openDetail(p),
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
              child: _buildThumb(p),
            ),
            Padding(
              padding: EdgeInsets.all(6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p['price']?.toString().isNotEmpty ?? false)
                    Text(
                      p['price']?.toString() ?? '',
                      style: TextStyle(
                        color: _successGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  SizedBox(height: 2.h),
                  Text(
                    p['title']?.toString() ?? '',
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
                          p['location']?.toString() ?? '',
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

  // ✅ [P1性能优化] 图片加载优化 - 使用 CachedNetworkImage
  Widget _buildThumb(Map<String, dynamic> p) {
    final imgs = p['images'];
    String? src;
    if (imgs is List && imgs.isNotEmpty) {
      src = imgs.first.toString();
    } else if (p['image'] != null) {
      src = p['image'].toString();
    }

    if (src == null || src.isEmpty) return _buildImagePlaceholder();

    Widget imageWidget;

    if (src.startsWith('http')) {
      // ✅ 修复：使用 CachedNetworkImage 替代 Image.network
      imageWidget = CachedNetworkImage(
        imageUrl: SupabaseImageConfig.getThumbnailUrl(src),
        cacheKey: SupabaseImageConfig.getThumbnailUrl(src),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        memCacheWidth: 600, // ✅ 性能优化：限制内存缓存大小
        memCacheHeight: 600,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _primaryBlue,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildImagePlaceholder(),
      );
    } else if (src.startsWith('/') || src.startsWith('file:')) {
      imageWidget = Image.file(
        File(src.replaceFirst('file://', '')),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else {
      imageWidget = Image.asset(
        src,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
      child: SizedBox.expand(child: imageWidget),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.image, size: 24.sp, color: Colors.grey[400]),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> item) {
    final full = (item['full'] as Map?) ?? {};
    final images = (item['images'] as List?) ?? [];
    final pdData = {
      'id': item['id'],
      'title': item['title'],
      'price': item['price'],
      'location': item['location'],
      'images': images,
      'postedDate': item['postedDate'] ?? full['created_at'],
      'description': full['description'] ?? '',
      'sellerName': full['name'] ?? '',
      'sellerPhone': full['phone'] ?? '',
      'category': full['category'] ?? '',
    };
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          productId: item['id']?.toString(),
          productData: pdData,
        ),
      ),
    );
  }

  Widget _buildLoadingTile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: const Center(
          child:
              CircularProgressIndicator(strokeWidth: 2, color: _primaryBlue)),
    );
  }

  Widget _buildSkeleton() {
    return GridView.builder(
      padding: EdgeInsets.all(12.w),
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
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(10.r)),
                ),
                child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _primaryBlue)),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 12.h, width: 60.w, color: Colors.grey[300]),
                  SizedBox(height: 4.h),
                  Container(
                      height: 10.h,
                      width: double.infinity,
                      color: Colors.grey[200]),
                  SizedBox(height: 4.h),
                  Container(height: 8.h, width: 50.w, color: Colors.grey[200]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40.sp, color: Colors.red[400]),
          SizedBox(height: 10.h),
          Text(
            'Something went wrong',
            style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800]),
          ),
          SizedBox(height: 4.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'Failed to load listings. Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
            ),
          ),
          SizedBox(height: 12.h),
          ElevatedButton.icon(
            onPressed: () {
              _loadInitial();
              _loadPinnedAds();
            },
            icon: Icon(Icons.refresh, size: 14.sp),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6.r)),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 50.sp, color: Colors.grey[400]),
          SizedBox(height: 12.h),
          Text(
            'No listings found',
            style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700]),
          ),
          SizedBox(height: 6.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'There are no listings in this category for the selected location. Try changing the location or check back later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.sp, color: Colors.grey[600], height: 1.3),
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: () {
              _loadInitial();
              _loadPinnedAds();
            },
            icon: Icon(Icons.refresh, size: 14.sp),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6.r)),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            ),
          ),
        ],
      ),
    );
  }
}
