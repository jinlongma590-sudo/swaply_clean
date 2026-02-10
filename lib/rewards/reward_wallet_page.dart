// lib/pages/reward/reward_wallet_page.dart
// Wallet 页面：Coupons + History 两个 Tab
// ✅ 修复：SafeNavigator.pop() + 优化History文案

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:flutter/services.dart';
import 'package:swaply/router/safe_navigator.dart';

class RewardWalletPage extends StatefulWidget {
  final int initialTab;

  const RewardWalletPage({super.key, this.initialTab = 0});

  @override
  State<RewardWalletPage> createState() => _RewardWalletPageState();
}

class _RewardWalletPageState extends State<RewardWalletPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  bool _isRefreshing = false;
  bool _hasLoadedOnce = false;

  // 数据
  List<CouponModel> _rewardCoupons = [];
  List<Map<String, dynamic>> _rewardHistory = [];

  // Realtime
  RealtimeChannel? _couponChannel;
  RealtimeChannel? _historyChannel;

  // UTF-8 乱码修复
  static const Map<int, int> _cp1252Reverse = {
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };

  String _fixUtf8Mojibake(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;

    final safe =
    RegExp(r'^[\x00-\x7F\u00B7\u2022\s\.\,\;\:\!\?\-_/()\[\]&\+\%]*$');
    if (safe.hasMatch(s)) return s;

    final looksBroken = s.contains('Ã') ||
        s.contains('Â') ||
        s.contains('â') ||
        s.contains('ð');
    if (!looksBroken) return s;

    try {
      final bytes = <int>[];
      for (final rune in s.runes) {
        final mapped = _cp1252Reverse[rune];
        if (mapped != null) {
          bytes.add(mapped);
        } else if (rune <= 0xFF) {
          bytes.add(rune & 0xFF);
        } else {
          bytes.add(0x3F);
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      try {
        return utf8.decode(latin1.encode(s), allowMalformed: true);
      } catch (e) {
        return s;
      }
    }
  }

  String _normalizeSeparators(String s) {
    return s
        .replaceAll('Â·', ' · ')
        .replaceAll('â€¢', ' · ')
        .replaceAll('•', ' · ')
        .replaceAll(RegExp(r'\s\u{FFFD}\s'), ' · ')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1).toInt(),
    );

    _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disposeChannel(_couponChannel);
    _disposeChannel(_historyChannel);
    super.dispose();
  }

  void _disposeChannel(RealtimeChannel? ch) {
    if (ch == null) return;
    try {
      ch.unsubscribe();
      Supabase.instance.client.removeChannel(ch);
    } catch (e) {}
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    // 订阅 coupons 表
    _couponChannel = client
        .channel('wallet-coupons-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'coupons',
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) {
        _loadRewardCoupons();
      },
    )
        .subscribe();

    // 订阅 coupon_usages 表
    _historyChannel = client
        .channel('wallet-history-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'coupon_usages',
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) {
        _loadRewardHistory();
      },
    )
        .subscribe();
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        _loadRewardCoupons(),
        _loadRewardHistory(),
      ]);
      if (mounted) setState(() => _hasLoadedOnce = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _loadData();
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadRewardCoupons() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      final rows = await supabase
          .from('coupons')
          .select('*')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final List<CouponModel> all = [];
      for (final row in rows) {
        try {
          final c = CouponModel.fromMap(row);
          if (_isRewardCoupon(c.type) && !c.isExpired) {
            all.add(c);
          }
        } catch (e) {}
      }

      if (!mounted) return;
      setState(() => _rewardCoupons = all);
    } catch (e) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;
        final coupons = await CouponService.getUserCoupons(
          userId: user.id,
          status: CouponStatus.active,
        );
        final rewardCoupons = coupons
            .where((c) => _isRewardCoupon(c.type) && !c.isExpired)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (!mounted) return;
        setState(() => _rewardCoupons = rewardCoupons);
      } catch (e) {}
    }
  }

  Future<void> _loadRewardHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final supabase = Supabase.instance.client;

    List<dynamic> usages = [];
    try {
      usages = await supabase
          .from('coupon_usages')
          .select(
          'id,coupon_id,user_id,listing_id,used_at,created_at,note,context')
          .eq('user_id', user.id)
          .order('used_at', ascending: false);
    } catch (_) {
      try {
        usages = await supabase
            .from('coupon_usages')
            .select('id,coupon_id,user_id,listing_id,created_at,note,context')
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
      } catch (e) {
        return;
      }
    }

    // ✅ 新增：查询 airtime 兑换记录
    List<dynamic> redemptions = [];
    try {
      redemptions = await supabase
          .from('airtime_redemptions')
          .select('id,user_id,phone,points_spent,status,requested_at')
          .eq('user_id', user.id)
          .order('requested_at', ascending: false);
    } catch (e) {
      // 如果表不存在或权限问题，忽略但不中断
      print('Warning: Failed to load airtime redemptions: $e');
    }

    try {
      final List<String> ids = usages
          .map((u) => (u is Map ? u['coupon_id'] : null))
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> couponById = {};
      if (ids.isNotEmpty) {
        final coupons = await supabase
            .from('coupons')
            .select('id,title,type')
            .or(ids.map((id) => 'id.eq.$id').join(','));
        for (final c in coupons) {
          final id = c['id'] as String;
          couponById[id] = (c as Map).map((k, v) => MapEntry(k.toString(), v));
        }
      }

      final List<Map<String, dynamic>> history = [];
      
      // 1. 处理 coupon_usages 记录
      for (final u in usages) {
        if (u is! Map) continue;

        final dynamic ts = u['used_at'] ?? u['created_at'];

        final ctx = u['context'];
        String? source;
        try {
          if (ctx is Map) {
            source = ctx['source']?.toString();
          } else if (ctx is String && ctx.isNotEmpty) {
            final parsed = jsonDecode(ctx);
            if (parsed is Map && parsed['source'] != null) {
              source = parsed['source'].toString();
            }
          }
        } catch (e) {}

        final String couponId = (u['coupon_id'] as String?) ?? '';
        final Map<String, dynamic>? c = couponById[couponId];

        final couponTitle = (c?['title'] as String?) ?? 'Coupon Used';
        final rewardType = _mapCouponTypeToRewardType(c?['type'] as String?);

        history.add({
          'created_at': ts,
          'reward_reason': (source ?? 'coupon_used'),
          'coupon_title': couponTitle,
          'reward_type': rewardType,
          'record_type': 'coupon', // 新增字段标识记录类型
        });
      }
      
      // 2. 处理 airtime_redemptions 记录
      for (final r in redemptions) {
        if (r is! Map) continue;
        
        final dynamic ts = r['requested_at'];
        final int pointsSpent = (r['points_spent'] as num?)?.toInt() ?? 0;
        final String status = (r['status'] as String?) ?? 'pending';
        final String phone = (r['phone'] as String?) ?? '';
        
        // 脱敏手机号（仅显示后4位）
        final String maskedPhone = phone.length > 4 
            ? '****${phone.substring(phone.length - 4)}'
            : '****';
            
        String statusText = '';
        switch (status) {
          case 'pending':
            statusText = 'Pending';
            break;
          case 'completed':
            statusText = 'Completed';
            break;
          case 'failed':
            statusText = 'Failed';
            break;
          default:
            statusText = status;
        }
        
        history.add({
          'created_at': ts,
          'reward_reason': 'airtime_redeem',
          'coupon_title': 'Airtime Redemption ($pointsSpent points)',
          'reward_type': 'airtime_redeem',
          'record_type': 'airtime', // 新增字段标识记录类型
          'metadata': {
            'points_spent': pointsSpent,
            'status': status,
            'status_text': statusText,
            'phone_masked': maskedPhone,
          },
        });
      }
      
      // 3. 按时间倒序排序（合并后的列表）
      history.sort((a, b) {
        final dynamic tsA = a['created_at'];
        final dynamic tsB = b['created_at'];
        
        DateTime dateA;
        DateTime dateB;
        
        if (tsA is DateTime) dateA = tsA;
        else if (tsA is String) dateA = DateTime.tryParse(tsA) ?? DateTime(0);
        else dateA = DateTime(0);
        
        if (tsB is DateTime) dateB = tsB;
        else if (tsB is String) dateB = DateTime.tryParse(tsB) ?? DateTime(0);
        else dateB = DateTime(0);
        
        return dateB.compareTo(dateA); // 降序：最新的在前
      });

      if (!mounted) return;
      setState(() => _rewardHistory = history);
    } catch (e) {
      print('Error in _loadRewardHistory: $e');
    }
  }

  String _couponTypeName(CouponType t) {
    final s = t.toString();
    final i = s.indexOf('.');
    return i >= 0 ? s.substring(i + 1) : s;
  }

  bool _isRewardCoupon(CouponType type) {
    final n = _couponTypeName(type);
    const rewardLike = {
      'registerBonus',
      'referralBonus',
      'activityBonus',
      'welcome',
      'trending',
      'hot',
      'category',
      'boost',
      'featured',
    };
    return rewardLike.contains(n);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            _buildHeaderIOS(context),
            _buildTabs(),
            Expanded(
              child: _buildTabView(),
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Text(
            'My Wallet',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF4CAF50),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18.w),
            onPressed: () => SafeNavigator.pop(), // ✅ 改用SafeNavigator
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.refresh, color: Colors.white, size: 24),
                onPressed: _isRefreshing ? null : _refreshData,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 24,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildTabs(),
            Expanded(
              child: _buildTabView(),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildHeaderIOS(BuildContext context) {
    final double statusBar = MediaQuery.of(context).padding.top;

    const double kNavBarHeight = 44.0;
    const double kButtonSize = 32.0;
    const double kSidePadding = 16.0;
    const double kButtonSpacing = 12.0;

    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => SafeNavigator.pop(), // ✅ 改用SafeNavigator
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

    final Widget iosRefreshButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: _isRefreshing ? null : _refreshData,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: _isRefreshing
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.refresh, color: Colors.white, size: 18),
        ),
      ),
    );

    final Widget iosTitle = Expanded(
      child: Text(
        'My Wallet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF45A049), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
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
                iosRefreshButton,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade700,
          indicator: BoxDecoration(
            color: const Color(0xFF4CAF50),
            borderRadius: BorderRadius.circular(12.r),
          ),
          labelStyle: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.normal,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: EdgeInsets.zero,
          dividerColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            Tab(
              height: 44.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_giftcard, size: 16.r),
                  SizedBox(width: 6.w),
                  const Text('Coupons'),
                ],
              ),
            ),
            Tab(
              height: 44.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 16.r),
                  SizedBox(width: 6.w),
                  const Text('History'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabView() {
    if (!_hasLoadedOnce) {
      return _buildLoadingState();
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildCouponsTab(),
        _buildHistoryTab(),
      ],
    );
  }

  Widget _buildCouponsTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: _rewardCoupons.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.card_giftcard_outlined,
            title: 'No Reward Coupons',
            subtitle: 'Your coupons will appear here',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: _rewardCoupons.length,
        itemBuilder: (context, index) =>
            _buildRewardCouponCard(_rewardCoupons[index], index),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: _rewardHistory.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.history_outlined,
            title: 'No History Records',
            subtitle: 'Your reward history will appear here',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: _rewardHistory.length,
        itemBuilder: (context, index) =>
            _buildHistoryCard(_rewardHistory[index], index),
      ),
    );
  }

  Widget _buildRewardCouponCard(CouponModel coupon, int index) {
    final fixedTitle = _normalizeSeparators(_fixUtf8Mojibake(coupon.title));
    final fixedDesc =
    _normalizeSeparators(_fixUtf8Mojibake(coupon.description));

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: _getCouponColor(coupon.type).withOpacity(0.15),
            blurRadius: 15.r,
            offset: Offset(0, 5.h),
          ),
        ],
        border: Border.all(
          color: _getCouponColor(coupon.type).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getCouponColor(coupon.type),
                  _getCouponColor(coupon.type).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              _getCouponIcon(coupon.type),
              color: Colors.white,
              size: 24.r,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fixedTitle,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  fixedDesc,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    coupon.code.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.grey[700],
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (coupon.canPin && coupon.isUsable)
            ElevatedButton(
              onPressed: () => _onUseNowPressed(coupon),
              style: ElevatedButton.styleFrom(
                backgroundColor: _getCouponColor(coupon.type),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              child: Text(
                'Use Now',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> reward, int index) {
    final rawTs = reward['created_at'];
    DateTime createdAt;
    if (rawTs is DateTime) {
      createdAt = rawTs;
    } else if (rawTs is String) {
      createdAt = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    final couponTitle = _normalizeSeparators(
      _fixUtf8Mojibake(reward['coupon_title'] ?? 'Coupon Reward'),
    );

    final rawReason =
    (reward['reward_reason'] ?? '').toString().trim().toLowerCase();

    // ✅ 修复：优化文案，避免"Task reward"困惑
    String prettyReason(String raw, String? type) {
      if (raw.isEmpty || raw == 'app' || raw == 'system' || raw == 'auto') {
        switch ((type ?? '').toLowerCase()) {
          case 'welcome':
            return 'Welcome reward';
          case 'referral_bonus':
            return 'Referral reward';
          case 'activity_bonus':
            return 'Campaign reward'; // ✅ 改为更泛化的文案
          default:
            return '';
        }
      }
      return _normalizeSeparators(_fixUtf8Mojibake(raw));
    }

    final reason = prettyReason(rawReason, reward['reward_type']);
    
    // ✅ 检查是否为 airtime 兑换记录
    final bool isAirtime = reward['record_type'] == 'airtime';
    final Map<String, dynamic> metadata = (reward['metadata'] as Map<String, dynamic>?) ?? {};
    final String? statusText = metadata['status_text'] as String?;
    final String? phoneMasked = metadata['phone_masked'] as String?;
    final int? pointsSpent = metadata['points_spent'] as int?;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getRewardTypeColor(reward['reward_type']),
                  _getRewardTypeColor(reward['reward_type']).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              _getRewardTypeIcon(reward['reward_type']),
              color: Colors.white,
              size: 20.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  couponTitle,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (isAirtime && statusText != null) ...[
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: _getStatusColor(statusText),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          statusText.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (phoneMasked != null && phoneMasked.isNotEmpty) ...[
                        SizedBox(width: 8.w),
                        Text(
                          phoneMasked,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (reason.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: _getRewardTypeColor(reward['reward_type']),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                SizedBox(height: 4.h),
                Text(
                  _formatDateTime(createdAt),
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80.r,
          height: 80.r,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(40.r),
          ),
          child: Icon(icon, size: 40.r, color: const Color(0xFF4CAF50)),
        ),
        SizedBox(height: 24.h),
        Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20.r,
              offset: Offset(0, 10.h),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40.r,
              height: 40.r,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onUseNowPressed(CouponModel coupon) {
    if (!coupon.canPin || !coupon.isUsable) return;
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (context) => const SellFormPage(),
        settings: RouteSettings(arguments: {'couponId': coupon.id}),
      ),
    );
  }

  IconData _getCouponIcon(CouponType type) {
    final n = _couponTypeName(type);
    switch (n) {
      case 'registerBonus':
      case 'welcome':
        return Icons.card_giftcard;
      case 'activityBonus':
        return Icons.task_alt;
      case 'referralBonus':
        return Icons.group_add;
      case 'hot':
      case 'trending':
        return Icons.local_fire_department;
      case 'category':
        return Icons.push_pin;
      case 'featured':
      case 'boost':
        return Icons.workspace_premium;
      default:
        return Icons.card_giftcard;
    }
  }

  Color _getCouponColor(CouponType type) {
    final n = _couponTypeName(type);
    switch (n) {
      case 'registerBonus':
      case 'welcome':
        return const Color(0xFF4CAF50);
      case 'activityBonus':
        return const Color(0xFF2196F3);
      case 'referralBonus':
        return const Color(0xFFE91E63);
      case 'hot':
      case 'trending':
        return const Color(0xFFFF6B35);
      case 'category':
        return const Color(0xFF2196F3);
      case 'featured':
      case 'boost':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF2196F3);
    }
  }

  Color _getRewardTypeColor(String? rewardType) {
    switch (rewardType) {
      case 'welcome':
      case 'register_bonus':
        return const Color(0xFF4CAF50);
      case 'activity_bonus':
        return const Color(0xFF2196F3);
      case 'referral_bonus':
        return const Color(0xFFE91E63);
      case 'airtime_redeem':
        return const Color(0xFFFF9800); // 橙色
      default:
        return Colors.grey;
    }
  }

  IconData _getRewardTypeIcon(String? rewardType) {
    switch (rewardType) {
      case 'welcome':
      case 'register_bonus':
        return Icons.card_giftcard;
      case 'activity_bonus':
        return Icons.task_alt;
      case 'referral_bonus':
        return Icons.group_add;
      case 'airtime_redeem':
        return Icons.phone_iphone;
      default:
        return Icons.card_giftcard;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 30) return '${difference.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}';
  }

  Color _getStatusColor(String statusText) {
    final lower = statusText.toLowerCase();
    if (lower.contains('pending')) {
      return const Color(0xFFFF9800); // 橙色
    } else if (lower.contains('completed')) {
      return const Color(0xFF4CAF50); // 绿色
    } else if (lower.contains('failed')) {
      return const Color(0xFFF44336); // 红色
    }
    return Colors.grey;
  }

  String _mapCouponTypeToRewardType(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'welcome':
      case 'registerbonus':
        return 'welcome';
      case 'referralbonus':
        return 'referral_bonus';
      case 'trending':
      case 'hot':
      case 'category':
      case 'featured':
      case 'boost':
      case 'activitybonus':
        return 'activity_bonus';
      default:
        return 'activity_bonus';
    }
  }

  @override
  bool get wantKeepAlive => true;
}
