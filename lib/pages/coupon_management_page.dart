// lib/pages/coupon_management_page.dart - iOS 头部对齐 + 顶部蓝色 44/56pt 统一 + Intro Banner
// ✅ 优化：减小卡片尺寸，一次显示更多优惠券
import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb / defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/router/safe_navigator.dart';

class CouponManagementPage extends StatefulWidget {
  const CouponManagementPage({super.key});
  @override
  State<CouponManagementPage> createState() => _CouponManagementPageState();
}

class _CouponManagementPageState extends State<CouponManagementPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ======== 基础色：Facebook 蓝（与首页一致） ========
  static const Color _PRIMARY_BLUE = Color(0xFF1877F2);

  // ========== 防循环：TTL + Future 缓存 ==========
  static const _ttl = Duration(seconds: 30);
  DateTime? _lastFetchAt;
  bool _loading = false; // 并发锁
  Future<void>? _dataFuture; // 缓存的 Future，避免每次 build 重建

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isRefreshing = false;

  List<CouponModel> _allCoupons = [];
  List<CouponModel> _activeCoupons = [];
  List<CouponModel> _usedCoupons = [];
  List<CouponModel> _expiredCoupons = [];
  Map<String, dynamic> _trendingQuotaStatus = {};
  Map<String, dynamic> _couponStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // 只触发一次，存储 Future
    _dataFuture = _loadDataOnce();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ========== 核心：防循环的数据加载 ==========
  Future<void> _loadDataOnce({bool force = false}) async {
    if (_loading) return; // 防并发

    final now = DateTime.now();
    if (!force &&
        _lastFetchAt != null &&
        now.difference(_lastFetchAt!) < _ttl) {
      return;
    }

    _loading = true;
    _lastFetchAt = now;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _allCoupons = [];
          _activeCoupons = [];
          _usedCoupons = [];
          _expiredCoupons = [];
          _trendingQuotaStatus = {};
          _couponStats = {};
        });
      }
      _loading = false;
      return;
    }

    try {
      await Future.wait([
        _loadCoupons(),
        _loadTrendingQuotaStatus(),
      ]);
      await _loadCouponStats();
      if (mounted) _animationController.forward();
    } catch (e) {
      debugPrint('Failed to load coupon data: $e');
      if (mounted) _showSnackBar('Failed to load data: $e', isError: true);
    } finally {
      _loading = false;
      if (mounted) setState(() {}); // 刷新 UI
    }
  }

  // ========== 手动刷新（强制绕过 TTL） ==========
  Future<void> _onPullToRefresh() async {
    setState(() => _isRefreshing = true);
    _dataFuture = _loadDataOnce(force: true);
    await _dataFuture;
    if (mounted) setState(() => _isRefreshing = false);
  }

  // ========== 数据加载：确保包含 welcome 券 + 健壮性处理 ==========
  Future<void> _loadCoupons() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('coupons')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(500);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final coupons = <CouponModel>[];
      for (final map in list) {
        try {
          map['used_count'] ??= 0;
          map['max_uses'] ??= 1;
          if (map['expires_at'] == null) {
            map['expires_at'] =
                DateTime.now().add(const Duration(days: 30)).toIso8601String();
          }
          coupons.add(CouponModel.fromMap(map));
        } catch (e) {
          debugPrint('Failed to parse coupon: $e, data: $map');
        }
      }

      if (!mounted) return;
      setState(() => _allCoupons = coupons);
    } catch (e) {
      debugPrint('Direct coupons query failed: $e');
      try {
        final coupons = await CouponService.getUserCoupons(userId: user.id);
        coupons.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!mounted) return;
        setState(() => _allCoupons = coupons);
      } catch (e2) {
        debugPrint('Fallback via CouponService failed: $e2');
        if (mounted) setState(() => _allCoupons = []);
      }
    }
  }

  Future<void> _loadTrendingQuotaStatus() async {
    try {
      final trendingAds = await CouponService.getTrendingPinnedAds();
      final usedCount = trendingAds.length;
      const maxCount = 20;

      if (mounted) {
        setState(() {
          _trendingQuotaStatus = {
            'used_count': usedCount,
            'max_count': maxCount,
            'available': usedCount < maxCount,
            'remaining': maxCount - usedCount,
          };
        });
      }
    } catch (e) {
      debugPrint('Failed to load trending quota status: $e');
      if (mounted) {
        setState(() {
          _trendingQuotaStatus = {
            'used_count': 0,
            'max_count': 20,
            'available': true,
            'remaining': 20,
          };
        });
      }
    }
  }

  // ========== 统计计算 ==========
  Future<void> _loadCouponStats() async {
    final now = DateTime.now();
    try {
      final activeCoupons = <CouponModel>[];
      final usedCoupons = <CouponModel>[];
      final expiredCoupons = <CouponModel>[];

      for (final coupon in _allCoupons) {
        bool isCurrentlyExpired = false;
        try {
          isCurrentlyExpired = now.isAfter(coupon.expiresAt);
        } catch (_) {
          isCurrentlyExpired = false;
        }

        final usedCount = coupon.usedCount ?? 0;
        final maxUses = coupon.maxUses ?? 1;

        if (coupon.status == CouponStatus.used) {
          usedCoupons.add(coupon);
        } else if (coupon.status == CouponStatus.expired ||
            isCurrentlyExpired) {
          expiredCoupons.add(coupon);
        } else if (coupon.status == CouponStatus.active &&
            !isCurrentlyExpired &&
            usedCount < maxUses) {
          activeCoupons.add(coupon);
        } else {
          expiredCoupons.add(coupon);
        }
      }

      int expiringSoon = 0;
      for (final c in activeCoupons) {
        try {
          if (c.daysUntilExpiry <= 3) expiringSoon++;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _activeCoupons = activeCoupons;
          _usedCoupons = usedCoupons;
          _expiredCoupons = expiredCoupons;
          _couponStats = {
            'total_coupons': _allCoupons.length,
            'active_coupons': activeCoupons.length,
            'used_coupons': usedCoupons.length,
            'expired_coupons': expiredCoupons.length,
            'expiring_soon': expiringSoon,
          };
        });
      }
    } catch (e) {
      debugPrint('Failed to calculate coupon stats: $e');
      if (mounted) {
        setState(() {
          _couponStats = {
            'total_coupons': _allCoupons.length,
            'active_coupons': 0,
            'used_coupons': 0,
            'expired_coupons': 0,
            'expiring_soon': 0,
          };
        });
      }
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // 1) 顶部头部：与 Wishlist 一致（状态栏 + 44/56pt）
          _buildUnifiedHeader(),

          // 2) 顶部 Intro Banner
          _buildIntroBanner(),

          // 3) 统计卡
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _buildQuickStats(),
          ),

          // 4) Trending 配额卡
          _buildTrendingQuotaCard(),

          // 5) Tabs
          _buildTabBar(),

          // 6) 内容
          Expanded(
            child: FutureBuilder<void>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _allCoupons.isEmpty) {
                  return _buildLoadingState();
                }
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCouponList(_activeCoupons, 'No available coupons'),
                      _buildCouponList(_usedCoupons, 'No usage records'),
                      _buildCouponList(_expiredCoupons, 'No expired coupons'),
                      _buildCouponList(_allCoupons, 'No coupons'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCouponTips,
        icon: const Icon(Icons.help_outline),
        label: const Text('Usage Guide'),
        backgroundColor: _PRIMARY_BLUE,
        foregroundColor: Colors.white,
      ),
    );
  }

  // ===== 统一头部（平台对齐：状态栏 + iOS 44 / Android 56，高度与 Wishlist 一致；按钮适当放大） =====
  Widget _buildUnifiedHeader() {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final double toolbarHeight = isIOS ? 44.0 : 56.0; // 与 Wishlist 的 AppBar 对齐
    const double kBtnSize = 36.0; // 32 -> 36
    const double kIconSize = 20.0; // 18 -> 20
    const double kRadius = 12.0; // 圆角略增以匹配尺寸

    final Widget backBtn = SizedBox(
      width: kBtnSize,
      height: kBtnSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new,
              size: kIconSize, color: Colors.white),
        ),
      ),
    );

    final Widget refreshBtn = SizedBox(
      width: kBtnSize,
      height: kBtnSize,
      child: GestureDetector(
        onTap: _isRefreshing ? null : _onPullToRefresh,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          alignment: Alignment.center,
          child: _isRefreshing
              ? const SizedBox(
                  width: kIconSize,
                  height: kIconSize,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh, size: kIconSize, color: Colors.white),
        ),
      ),
    );

    final Widget title = Text(
      'My Coupons',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 18.sp,
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(color: _PRIMARY_BLUE),
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: toolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                backBtn,
                const SizedBox(width: 12),
                Expanded(child: title),
                const SizedBox(width: 12),
                refreshBtn,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== 顶部 Intro Banner =====
  Widget _buildIntroBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _PRIMARY_BLUE.withOpacity(0.10),
              _PRIMARY_BLUE.withOpacity(0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _PRIMARY_BLUE.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _PRIMARY_BLUE.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.card_giftcard,
                  color: _PRIMARY_BLUE, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage & Use Your Coupons',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Copy codes, pin items to trending/category, and boost your search ranking.',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      height: 1.40,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _showCouponTips,
              style: TextButton.styleFrom(
                foregroundColor: _PRIMARY_BLUE,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text(
                'Usage',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Trending 配额卡 =====
  Widget _buildTrendingQuotaCard() {
    final used = _trendingQuotaStatus['used_count'] as int? ?? 0;
    final max = _trendingQuotaStatus['max_count'] as int? ?? 20;
    final remaining = _trendingQuotaStatus['remaining'] as int? ?? 20;
    final available = _trendingQuotaStatus['available'] as bool? ?? true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PRIMARY_BLUE,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _PRIMARY_BLUE.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_fire_department,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s Hot Pinning Quota',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  available
                      ? 'Remaining $remaining free hot pins'
                      : 'Today\'s quota used up, try again tomorrow',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (used / max).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$used/$max',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final availableCount = _activeCoupons.length;
    final usedCount = _usedCoupons.length;
    final expiredCount = _expiredCoupons.length;
    final allCount = _allCoupons.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[600],
        indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12), color: _PRIMARY_BLUE),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.zero,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: [
          Tab(
            height: 56,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Available'),
              const SizedBox(height: 2),
              Text('($availableCount)', style: const TextStyle(fontSize: 10)),
            ]),
          ),
          Tab(
            height: 56,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Used'),
              const SizedBox(height: 2),
              Text('($usedCount)', style: const TextStyle(fontSize: 10)),
            ]),
          ),
          Tab(
            height: 56,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Expired'),
              const SizedBox(height: 2),
              Text('($expiredCount)', style: const TextStyle(fontSize: 10)),
            ]),
          ),
          Tab(
            height: 56,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('All'),
              const SizedBox(height: 2),
              Text('($allCount)', style: const TextStyle(fontSize: 10)),
            ]),
          ),
        ],
      ),
    );
  }

  // ====== 浅色卡片版 QuickStats ======
  Widget _buildQuickStats() {
    final expiringSoon = _couponStats['expiring_soon'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickStatItem('Available', _activeCoupons.length.toString(),
              Icons.card_giftcard),
          Container(width: 1, height: 30, color: Colors.grey.shade300),
          _buildQuickStatItem(
              'Used', _usedCoupons.length.toString(), Icons.check_circle),
          Container(width: 1, height: 30, color: Colors.grey.shade300),
          _buildQuickStatItem(
              'Expiring\nSoon', expiringSoon.toString(), Icons.schedule),
        ],
      ),
    );
  }

  Widget _buildQuickStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: _PRIMARY_BLUE, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10))
              ],
            ),
            child: const Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_PRIMARY_BLUE),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Loading your coupons...',
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            const Text('Failed to load coupons',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _onPullToRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _PRIMARY_BLUE,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponList(List<CouponModel> coupons, String emptyMessage) {
    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      color: _PRIMARY_BLUE,
      child: coupons.isEmpty
          ? _buildEmptyState(emptyMessage)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: coupons.length,
              itemBuilder: (context, index) {
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(
                          opacity: value,
                          child: _buildCouponCard(coupons[index])),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  _PRIMARY_BLUE.withOpacity(0.10),
                  _PRIMARY_BLUE.withOpacity(0.05),
                ]),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(Icons.card_giftcard_outlined,
                  size: 50, color: _PRIMARY_BLUE),
            ),
            const SizedBox(height: 24),
            const Text('No coupons',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ===== ✅ 优化后的卡片：减小尺寸，一次显示更多 =====
  Widget _buildCouponCard(CouponModel coupon) {
    bool isExpiringSoon = false;
    try {
      isExpiringSoon = coupon.daysUntilExpiry <= 3 && coupon.isUsable;
    } catch (e) {
      isExpiringSoon = false;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // 16 -> 12
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _getCouponColor(coupon.type).withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
        border: isExpiringSoon
            ? Border.all(color: Colors.red.withOpacity(0.3), width: 2)
            : Border.all(
                color: _getCouponColor(coupon.type).withOpacity(0.2), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // 头部色带 - 减小 padding
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14), // 20 -> 14
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getCouponColor(coupon.type),
                    _getCouponColor(coupon.type).withOpacity(0.8),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, // 56 -> 48
                    height: 48, // 56 -> 48
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Icon(_getCouponIcon(coupon.type),
                        color: Colors.white, size: 24), // 28 -> 24
                  ),
                  const SizedBox(width: 12), // 16 -> 12
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(coupon.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis), // 18 -> 16
                        const SizedBox(height: 4), // 6 -> 4
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3), // 10,4 -> 8,3
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            coupon.code,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12, // 13 -> 12
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5), // 12,6 -> 10,5
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      coupon.statusDescription,
                      style: TextStyle(
                          color: _getCouponColor(coupon.type),
                          fontSize: 11,
                          fontWeight: FontWeight.w600), // 12 -> 11
                    ),
                  ),
                ],
              ),
            ),

            // 内容 - 减小 padding
            Padding(
              padding: const EdgeInsets.all(14), // 20 -> 14
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isExpiringSoon) ...[
                    Container(
                      padding: const EdgeInsets.all(10), // 12 -> 10
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 18), // 20 -> 18
                          const SizedBox(width: 6), // 8 -> 6
                          Expanded(
                            child: Text(
                              'Expiring soon! Use within ${coupon.daysUntilExpiry} days.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600), // 12 -> 11
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12), // 16 -> 12
                  ],
                  Text(
                    coupon.description,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.4), // 14 -> 13
                    maxLines: 2, // 限制描述最多 2 行
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8), // 10 -> 8
                  if (coupon.isWelcome || coupon.pinScope != null) ...[
                    Row(
                      children: [
                        Icon(Icons.push_pin,
                            size: 14, color: Colors.orange[700]), // 16 -> 14
                        const SizedBox(width: 4), // 6 -> 4
                        Text(
                          'Scope: ${coupon.isWelcome ? 'Category Pin' : (coupon.pinScope ?? 'N/A')}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[800],
                              fontWeight: FontWeight.w600), // 12 -> 11
                        ),
                      ],
                    ),
                    const SizedBox(height: 8), // 10 -> 8
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyCouponCode(coupon.code),
                          icon: const Icon(Icons.copy, size: 14), // 16 -> 14
                          label: const Text('Copy Code',
                              style: TextStyle(fontSize: 13)), // 14 -> 13
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _getCouponColor(coupon.type),
                            side:
                                BorderSide(color: _getCouponColor(coupon.type)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10), // 12 -> 10
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (coupon.isUsable) ...[
                        const SizedBox(width: 10), // 12 -> 10
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _onUseNow(coupon),
                            icon: Icon(
                                coupon.canPin
                                    ? Icons.post_add
                                    : Icons.info_outline,
                                size: 14), // 16 -> 14
                            label: Text(
                                coupon.canPin ? 'Use Now' : 'How to Use',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)), // 14 -> 13
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _getCouponColor(coupon.type),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10), // 12 -> 10
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
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

  // ===== 类型色/图标 =====
  Color _getCouponColor(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return const Color(0xFFFF6B35);
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return const Color(0xFF2196F3);
      case CouponType.boost:
        return const Color(0xFF9C27B0);
      case CouponType.registerBonus:
      case CouponType.welcome:
        return const Color(0xFF4CAF50);
      case CouponType.activityBonus:
        return const Color(0xFFFF9800);
      case CouponType.referralBonus:
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF2196F3);
    }
  }

  IconData _getCouponIcon(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return Icons.local_fire_department;
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return Icons.push_pin;
      case CouponType.boost:
        return Icons.rocket_launch;
      case CouponType.registerBonus:
      case CouponType.welcome:
        return Icons.card_giftcard;
      case CouponType.activityBonus:
        return Icons.task_alt;
      case CouponType.referralBonus:
        return Icons.group_add;
      default:
        return Icons.card_giftcard;
    }
  }

  String _readableType(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return 'Hot Pin';
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return 'Category Pin';
      case CouponType.boost:
        return 'Search Boost';
      case CouponType.registerBonus:
        return 'Register Bonus';
      case CouponType.welcome:
        return 'Welcome Reward';
      case CouponType.activityBonus:
        return 'Activity Bonus';
      case CouponType.referralBonus:
        return 'Referral Bonus';
      default:
        return 'Coupon';
    }
  }

  void _copyCouponCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showSnackBar('Coupon code copied: $code');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : _PRIMARY_BLUE,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ===== 入口动作（WidgetBuilder 签名） =====
  void _onUseNow(CouponModel coupon) {
    if (coupon.canPin) {
      SafeNavigator.push(
        MaterialPageRoute(
          builder: (context) => const SellFormPage(),
          settings: RouteSettings(arguments: {'couponId': coupon.id}),
        ),
      );
      _showSnackBar(
          'Tip: select this coupon in the posting page to pin your item.');
    } else {
      _showUseCouponDialog(coupon);
    }
  }

  void _showUseCouponDialog(CouponModel coupon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('How to Use',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (coupon.canPin) ...[
                const Text(
                    'This coupon can pin your item to get more visibility.',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                const Text(
                    'Post an item and choose this coupon during submission.',
                    style: TextStyle(fontSize: 14, color: Colors.black54)),
              ] else ...[
                const Text('This coupon cannot be used for pinning directly.',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('Type: ${_readableType(coupon.type)}',
                    style:
                        const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(coupon.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Code: ${coupon.code}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontFamily: 'monospace')),
                    ]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          if (coupon.canPin)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                SafeNavigator.push(
                  MaterialPageRoute(
                    builder: (context) => const SellFormPage(),
                    settings: RouteSettings(arguments: {'couponId': coupon.id}),
                  ),
                );
              },
              icon: const Icon(Icons.post_add, size: 18),
              label: const Text('Go to Post'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _PRIMARY_BLUE,
                  foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }

  void _showCouponTips() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('How to Use Coupons',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTipItem(
                  icon: Icons.local_fire_department,
                  title: 'Hot Pin Coupons',
                  description:
                      'Pin your items to the trending section on homepage for maximum visibility.',
                  color: const Color(0xFFFF6B35),
                ),
                const SizedBox(height: 16),
                _buildTipItem(
                  icon: Icons.push_pin,
                  title: 'Category Pin Coupons',
                  description:
                      'Pin your items to the top of specific category pages.',
                  color: const Color(0xFF2196F3),
                ),
                const SizedBox(height: 16),
                _buildTipItem(
                  icon: Icons.rocket_launch,
                  title: 'Boost Coupons',
                  description: 'Boost your item ranking in search results.',
                  color: const Color(0xFF9C27B0),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _PRIMARY_BLUE.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _PRIMARY_BLUE.withOpacity(0.30)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb, color: _PRIMARY_BLUE, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Use hot pin coupons during peak hours for best results!',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1366D1),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'))
        ],
      ),
    );
  }

  Widget _buildTipItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
            const SizedBox(height: 4),
            Text(description,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600], height: 1.3)),
          ]),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true; // 保持状态，避免 Tab 切换重建
}
