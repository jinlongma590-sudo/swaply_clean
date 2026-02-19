// lib/pages/reward/reward_center_hub.dart
// Hub 概览页：Points + Spins + 统计 + 导航入口
// ✅ 修复：SafeNavigator.pop() + 非static缓存 + BottomSheet导航
// ✅ 兼容旧版 supabase_flutter：移除 FetchOptions/CountOption，改用 select('id') + length 计数

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/services/edge_functions_client.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:rxdart/rxdart.dart';
import 'reward_wallet_page.dart';
import 'package:swaply/pages/reward_rules_page.dart';
import 'package:swaply/core/qa_keys.dart'; // QaKeys

class RewardCenterHub extends StatefulWidget {
  final int initialTab;

  const RewardCenterHub({super.key, this.initialTab = 0});

  @override
  State<RewardCenterHub> createState() => _RewardCenterHubState();
}

class _RewardCenterHubState extends State<RewardCenterHub>
    with AutomaticKeepAliveClientMixin {
  // ===== ✅ 修复：改为实例变量，避免跨session污染 =====
  static const _ttl = Duration(seconds: 30);
  DateTime? _lastFetchAt; // ✅ 改为实例变量
  bool _loading = false; // ✅ 改为实例变量

  Future<void>? _dataFuture;
  bool _isRefreshing = false;
  bool _hasLoadedOnce = false;

  // ===== Hub 只需要的数据 =====
  int _airtimePoints = 0;
  int _spinsBalance = 0;
  int _qualifiedCount = 0;
  String _loopProgressText = '';
  bool _isRedeeming = false;
  bool _isSpinning = false;

  // 统计数据（轻量级）
  int _couponsCount = 0;
  
  // 奖池数据
  List<Map<String, dynamic>> _spinPool = [];
  int _historyCount = 0;

  // Realtime（只订阅必要的）
  RealtimeChannel? _rewardStateChannel;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDataOnce(force: true);
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _disposeChannel(_rewardStateChannel);
    super.dispose();
  }

  void _disposeChannel(RealtimeChannel? ch) {
    if (ch == null) return;
    try {
      ch.unsubscribe();
      Supabase.instance.client.removeChannel(ch);
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    // 只订阅 reward_state（Points/Spins 变化）
    _rewardStateChannel = client
        .channel('reward-state-hub-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_reward_state',
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) {
        _loadRewardState();
      },
    )
        .subscribe();
  }

  Future<void> _loadDataOnce({bool force = false}) async {
    if (_loading) return;

    final now = DateTime.now();
    if (!force &&
        _lastFetchAt != null &&
        now.difference(_lastFetchAt!) < _ttl) {
      if (mounted) setState(() => _hasLoadedOnce = true);
      return;
    }

    _loading = true;
    _lastFetchAt = now;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _loading = false;
      return;
    }

    try {
      await Future.wait([
        _loadRewardState(),
        _loadCounts(),
        _loadSpinPool(), // ✅ 新增奖池加载
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
    } finally {
      _loading = false;
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    _dataFuture = _loadDataOnce(force: true);
    await _dataFuture;
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadRewardState() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;
      final row = await supabase
          .from('user_reward_state')
          .select('*')
          .eq('user_id', user.id)
          .eq('campaign_code', 'launch_v1')
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _airtimePoints = (row?['airtime_points'] as int?) ?? 0;
        _spinsBalance = (row?['spins_balance'] as int?) ?? 0;
        _qualifiedCount = (row?['qualified_listings_count'] as int?) ?? 0;
        _loopProgressText =
            (row?['spin_loop_progress_text'] as String?)?.toString() ?? '';
      });
    } catch (e) {
      debugPrint('Failed to load reward state: $e');
    }
  }

  // ✅ 兼容旧版 supabase_flutter：不使用 count 选项
  Future<void> _loadCounts() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      final couponsRows = await supabase
          .from('coupons')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'active');

      final historyRows = await supabase
          .from('coupon_usages')
          .select('id')
          .eq('user_id', user.id);

      if (!mounted) return;

      setState(() {
        _couponsCount = (couponsRows as List).length;
        _historyCount = (historyRows as List).length;
      });
    } catch (e) {
      debugPrint('Failed to load counts: $e');
    }
  }

  Future<void> _loadSpinPool() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;
      
      final rows = await supabase
          .from('reward_pool_items')
          .select('id, title, item_type, weight, payload')
          .eq('campaign_code', 'launch_v1')
          .eq('is_active', true)
          .order('sort_order');

      final List<Map<String, dynamic>> pool = [];
      for (final row in rows) {
        if (row is Map) {
          pool.add(Map<String, dynamic>.from(row));
        }
      }

      if (!mounted) return;
      setState(() => _spinPool = pool);
    } catch (e) {
      debugPrint('Failed to load spin pool: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return FutureBuilder<void>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final isInitialLoading =
            !_hasLoadedOnce && snapshot.connectionState == ConnectionState.waiting;

        if (isIOS) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: Column(
              children: [
                _buildHeaderIOS(context),
                Expanded(
                  child: isInitialLoading ? _buildLoadingState() : _buildContent(),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
              title: Text(
                'Reward Center',
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
                        : const Icon(Icons.refresh,
                        color: Colors.white, size: 24),
                    onPressed: _isRefreshing ? null : _refreshData,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 24,
                  ),
                ),
              ],
            ),
            body: isInitialLoading ? _buildLoadingState() : _buildContent(),
          );
        }
      },
    );
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
          child:
          const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
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
        'Reward Center',
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

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: ListView(
        padding: EdgeInsets.all(16.r),
        children: [
          _buildPointsCard(),
          SizedBox(height: 16.h),
          _buildSpinsCard(),
          SizedBox(height: 24.h),
          _buildNavigationCards(),
        ],
      ),
    );
  }

  Widget _buildPointsCard() {
    final progress = (_airtimePoints / 100).clamp(0.0, 1.0);
    final canRedeem = _airtimePoints >= 100 && !_isRedeeming;

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withOpacity(0.3),
            blurRadius: 12.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 28.r,
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Airtime Points',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Text(
                          '$_airtimePoints',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' / 100',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16.sp,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8.h,
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canRedeem ? _onRedeemPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withOpacity(0.3),
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: _isRedeeming
                  ? SizedBox(
                width: 20.r,
                height: 20.r,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4CAF50),
                ),
              )
                  : Text(
                'Redeem Airtime',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: canRedeem
                      ? const Color(0xFF4CAF50)
                      : Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinsCard() {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withOpacity(0.3),
            blurRadius: 12.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.casino,
                  color: Colors.white,
                  size: 28.r,
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Spins',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '$_spinsBalance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_loopProgressText.trim().isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                _loopProgressText.trim(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else if (_qualifiedCount > 0) ...[
            SizedBox(height: 12.h),
            Text(
              'Qualified listings: $_qualifiedCount',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12.sp,
              ),
            ),
          ],
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSpinning ? null : _onSpinNowPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withOpacity(0.3),
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: _isSpinning
                  ? SizedBox(
                width: 20.r,
                height: 20.r,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF1976D2),
                ),
              )
                  : Text(
                'Spin Now',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: const Color(0xFF2196F3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your Rewards',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 16.h),
        _buildNavCard(
          icon: Icons.card_giftcard,
          title: 'My Coupons',
          subtitle: '$_couponsCount available',
          color: const Color(0xFF4CAF50),
          onTap: () => _navigateToWallet(0),
        ),
        SizedBox(height: 12.h),
        _buildNavCard(
          key: const Key(QaKeys.rewardCenterHistory),
          icon: Icons.history,
          title: 'History',
          subtitle: '$_historyCount records',
          color: const Color(0xFF2196F3),
          onTap: () => _navigateToWallet(1),
        ),
        SizedBox(height: 12.h),
        _buildNavCard(
          key: const Key(QaKeys.rewardCenterRulesCard),
          icon: Icons.info_outline,
          title: 'Rules & Odds',
          subtitle: 'How spins work, prize pool, odds, eligibility',
          color: const Color(0xFF9C27B0),
          onTap: _navigateToRules,
        ),
      ],
    );
  }

  Widget _buildNavCard({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: color, size: 28.r),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 18.r),
            ],
          ),
        ),
      ),
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
              'Loading your rewards...',
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

  void _navigateToWallet(int initialTab) {
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (context) => RewardWalletPage(initialTab: initialTab),
      ),
    );
  }

  void _navigateToRules() {
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (context) => const RewardRulesPage(),
      ),
    );
  }

  // 手机号校验函数
  String? _validatePhone(String phone) {
    // 1. trim 去空格
    final trimmed = phone.trim();
    
    if (trimmed.isEmpty) {
      return 'Phone number is required';
    }
    
    // 2. 检查 + 只能出现在开头
    if (trimmed.contains('+') && !trimmed.startsWith('+')) {
      return 'Plus sign (+) must be at the beginning';
    }
    
    // 3. 只允许 + 和数字
    final allowedPattern = RegExp(r'^\+?[0-9]+$');
    if (!allowedPattern.hasMatch(trimmed)) {
      return 'Only numbers and + at the beginning allowed';
    }
    
    // 4. 计算数字长度（不包括 +）
    final digits = trimmed.replaceAll('+', '');
    final totalLength = trimmed.length; // 包含 + 的总长度
    
    // E.164 最长 15 位数字，带 + 最多 16
    if (digits.length < 8 || digits.length > 15) {
      return 'Phone number must be 8-15 digits (E.164 format)';
    }
    
    if (totalLength < 8 || totalLength > 16) {
      return 'Total length (with +) must be 8-16 characters';
    }
    
    return null;
  }

  Future<void> _onRedeemPressed() async {
    if (_isRedeeming) return;

    if (_airtimePoints < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You need 100 points to redeem'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    // 对话框状态
    String phoneInput = '';
    String? phoneError;
    bool isSubmitting = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void validateAndSubmit() {
              final error = _validatePhone(phoneInput);
              setState(() => phoneError = error);
              if (error == null) {
                Navigator.pop(context, true);
              }
            }
            
            return AlertDialog(
              title: const Text('Redeem Airtime'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Redeem 100 points for airtime credit'),
                    const SizedBox(height: 16),
                    // 手机号输入
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Phone number',
                        hintText: '+263771234567 or +8615615949938',
                        errorText: phoneError,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        setState(() {
                          phoneInput = value;
                          // 实时校验（清除错误）
                          if (phoneError != null) {
                            final error = _validatePhone(value);
                            setState(() => phoneError = error);
                          }
                        });
                      },
                      onSubmitted: (_) => validateAndSubmit(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Format: E.164 (e.g., +263771234567, +8615615949938)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Points 信息
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.currency_exchange, size: 20),
                          const SizedBox(width: 8),
                          const Text('Points to redeem:'),
                          const Spacer(),
                          Text('100',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isSubmitting)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => validateAndSubmit(),
                  child: const Text('Redeem'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    // 最终校验
    phoneError = _validatePhone(phoneInput);
    if (phoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid phone number: $phoneError'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final cleanPhone = phoneInput.trim();

    setState(() => _isRedeeming = true);
    try {
      await EdgeFunctionsClient.instance.call('airtime-redeem', body: {
        'phone': cleanPhone,
        'points': 100,
        'campaign': 'launch_v1',
      });

      await _loadRewardState();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          const Text('✅ Redemption submitted! We will contact you soon.'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to redeem: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  Future<void> _onSpinNowPressed() async {
    if (_isSpinning) return;

    if (_spinsBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No spins available'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    setState(() => _isSpinning = true);
    try {
      if (!mounted) return;

      // ✅ 修复：移除 useRootNavigator，走当前navigator
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SpinSheet(
          airtimePoints: _airtimePoints,
          spins: _spinsBalance,
          qualifiedCount: _qualifiedCount,
          loopProgressText: _loopProgressText,
          pool: _spinPool,
          onAfterSpin: () async {
            await _loadRewardState();
            await _loadCounts();
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open spin: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _isSpinning = false);
    }
  }

  @override
  bool get wantKeepAlive => true;
}

// ============================================================
// SpinSheet（转盘弹窗）
// ============================================================
class _SpinSheet extends StatefulWidget {
  final int airtimePoints;
  final int spins;
  final int qualifiedCount;
  final String loopProgressText;
  final List<Map<String, dynamic>> pool;
  final Future<void> Function() onAfterSpin;

  const _SpinSheet({
    required this.airtimePoints,
    required this.spins,
    required this.qualifiedCount,
    required this.loopProgressText,
    required this.pool,
    required this.onAfterSpin,
  });

  @override
  State<_SpinSheet> createState() => _SpinSheetState();
}

class _SpinSheetState extends State<_SpinSheet> with TickerProviderStateMixin {
  final StreamController<int> _selected = BehaviorSubject<int>();
  bool _isSpinning = false;
  late int _localSpins;
  late int _localPoints;
  String? _pendingTitle;
  String? _pendingMessage;

  static const Color kPrimaryGreen = Color(0xFF4CAF50);
  static const Color kDarkGreen = Color(0xFF2E7D32);
  static const Color kAccentGreen = Color(0xFF66BB6A);

  static const List<List<Color>> kSliceGradients = [
    [Color(0xFF4CAF50), Color(0xFF66BB6A)],
    [Color(0xFF2196F3), Color(0xFF42A5F5)],
    [Color(0xFF43A047), Color(0xFF66BB6A)],
    [Color(0xFFFF8A00), Color(0xFFFFB300)],
    [Color(0xFFFFD700), Color(0xFFFFA500)],
    [Color(0xFFD81B60), Color(0xFFEC407A)],
  ];

  final List<_WheelItem> _items = [
    _WheelItem(mainText: '100 PTS', subText: 'AIR', type: 'points', value: 100),
    _WheelItem(mainText: '5 PTS', subText: 'POINTS', type: 'points', value: 5),
    _WheelItem(mainText: '10 PTS', subText: 'POINTS', type: 'points', value: 10),
    _WheelItem(mainText: 'CAT', subText: 'BOOST', type: 'boost', scope: 'category'),
    _WheelItem(mainText: 'SEARCH', subText: 'BOOST', type: 'boost', scope: 'search'),
    _WheelItem(mainText: 'TREND', subText: 'BOOST', type: 'boost', scope: 'trending'),
  ];

  @override
  void initState() {
    super.initState();
    _localSpins = widget.spins;
    _localPoints = widget.airtimePoints;
  }

  @override
  void dispose() {
    _selected.close();
    super.dispose();
  }





  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: 650.h,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        children: [
          SizedBox(height: 12.h),
          Container(
            width: 40.w,
            height: 5.h,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3.r),
            ),
          ),
          SizedBox(height: 20.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(width: 48.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: kPrimaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: kPrimaryGreen.withOpacity(0.3)),
                ),
                child: Text(
                  'SPIN & WIN',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w900,
                    color: kPrimaryGreen,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: EdgeInsets.all(6.r),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: Colors.grey[700], size: 20.r),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
              decoration: BoxDecoration(
                color: kPrimaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: kPrimaryGreen.withOpacity(0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatCard('AVAILABLE SPINS', '$_localSpins', kPrimaryGreen),
                  Container(
                    width: 1.5,
                    height: 30.h,
                    color: kPrimaryGreen.withOpacity(0.3),
                  ),
                  _buildStatCard('AIRTIME POINTS', '$_localPoints',
                      const Color(0xFFFF6F00)),
                ],
              ),
            ),
          ),
          if (widget.loopProgressText.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: kAccentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: kAccentGreen.withOpacity(0.3)),
                ),
                child: Text(
                  widget.loopProgressText.trim(),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: kDarkGreen,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          SizedBox(height: 20.h),
          // Marketing banner for boosted win rate
          Container(
            margin: EdgeInsets.symmetric(horizontal: 24.w),
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 16.w),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.orange, width: 2.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_fire_department, color: Colors.red, size: 20.r),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '🔥 Win Rate Boosted! Over 50% chance to win Airtime!',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[800],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 30.r),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kPrimaryGreen.withOpacity(0.2),
                        width: 4.r,
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.all(8.r),
                    child: FortuneWheel(
                      selected: _selected.stream,
                      animateFirst: false,
                      physics: CircularPanPhysics(
                        duration: const Duration(milliseconds: 4500),
                        curve: Curves.decelerate,
                      ),
                      onAnimationEnd: _handleAnimationEnd,
                      indicators: <FortuneIndicator>[
                        FortuneIndicator(
                          alignment: Alignment.topCenter,
                          child: Transform.translate(
                            offset: const Offset(0, -10),
                            child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimaryGreen.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: TriangleIndicator(
                                color: kPrimaryGreen,
                                width: 28,
                                height: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                      items: List.generate(_items.length, (index) {
                        final item = _items[index];
                        final gradient = kSliceGradients[index];

                        return FortuneItem(
                          child: Center(
                            child: Padding(
                              // ✅ 增加 top padding 让文字更靠外，避免被中心按钮遮挡
                              padding: EdgeInsets.only(top: 26.r, bottom: 4.r),
                              child: FittedBox(
                                fit: BoxFit.scaleDown, // ✅ 关键：超出就缩小，不再 overflow
                                child: Column(
                                  mainAxisSize: MainAxisSize.min, // ✅ 关键：避免撑满导致溢出
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.mainText,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 14.sp, // 原来 16.sp 容易溢出，稍微降一点
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                        height: 0.95, // ✅ 压缩行高
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 3,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 1.h), // ✅ 原来 2.h 改小一点
                                    Text(
                                      item.subText,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 8.sp, // 原来 9.sp 改小一点
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white.withOpacity(0.95),
                                        letterSpacing: 0.2,
                                        height: 0.95, // ✅ 压缩行高
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withOpacity(0.2),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          style: FortuneItemStyle(
                            color: gradient[0],
                            borderColor: Colors.white,
                            borderWidth: 3.r,
                          ),
                        );
                      }),
                    ),
                  ),
                  GestureDetector(
                    onTap: _isSpinning ? null : _spinLogic,
                    child: Container(
                      width: 78.r,
                      height: 78.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isSpinning
                              ? [Colors.grey[300]!, Colors.grey[400]!]
                              : [kAccentGreen, kPrimaryGreen, kDarkGreen],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isSpinning
                                ? Colors.grey.withOpacity(0.3)
                                : kPrimaryGreen.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Container(
                        margin: EdgeInsets.all(3.r),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Container(
                          margin: EdgeInsets.all(6.r),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _isSpinning
                                  ? [Colors.grey[300]!, Colors.grey[400]!]
                                  : [kPrimaryGreen, kDarkGreen],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: _isSpinning
                              ? SizedBox(
                            width: 28.r,
                            height: 28.r,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3.5,
                            ),
                          )
                              : Text(
                            'SPIN',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.sp,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 28.h),
          Padding(
            padding: EdgeInsets.fromLTRB(24.r, 0, 24.r, 24.r),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGreen.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSpinning ? null : _spinLogic,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSpinning
                          ? [Colors.grey[300]!, Colors.grey[400]!]
                          : [kPrimaryGreen, kDarkGreen],
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: 18.h),
                    child: _isSpinning
                        ? SizedBox(
                      width: 24.r,
                      height: 24.r,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                        : Text(
                      'SPIN NOW',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17.sp,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontWeight: FontWeight.w700,
            color: Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _spinLogic() async {
    if (_isSpinning) return;
    if (_localSpins <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No spins left!'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    setState(() => _isSpinning = true);

    try {
      final supabase = Supabase.instance.client;
      final requestId = const Uuid().v4();

      final res = await supabase.functions.invoke(
        'reward-spin',
        body: {'campaign_code': 'launch_v1', 'request_id': requestId},
      );

      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      if (data['ok'] != true) {
        throw Exception(data['reason'] ?? data['error'] ?? 'Spin failed');
      }

      if (mounted) {
        setState(() {
          _localSpins = (data['spins_left'] as num?)?.toInt() ?? _localSpins;
          _localPoints = (data['airtime_points'] as num?)?.toInt() ?? _localPoints;
        });
      }

      final reward = Map<String, dynamic>.from(data['reward'] ?? {});
      final resultType = reward['result_type']?.toString() ?? 'none';
      
      // 优先使用后端返回的 selected_index
      int targetIndex = 4;
      final selectedIndex = (reward['selected_index'] as num?)?.toInt();
      
      if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < _items.length) {
        // 直接使用后端索引（现在_items顺序与后端pool一致）
        targetIndex = selectedIndex;
      } else {
        // 降级：如果没有selected_index，使用旧的映射逻辑
        if (resultType == 'airtime_points') {
          final pts = (reward['points'] as num?)?.toInt() ?? 0;
          final idx = _items.indexWhere((item) => item.type == 'points' && item.value == pts);
          if (idx != -1) targetIndex = idx;
        } else if (resultType == 'boost_coupon') {
          final scope = (reward['pin_scope'] ?? '').toString();
          final idx = _items.indexWhere((item) => item.type == 'boost' && item.scope == scope);
          if (idx != -1) targetIndex = idx;
        } else {
          // 备用情况：理论上不会发生，因为所有奖品都有类型
          final idx = _items.indexWhere((item) => item.type == 'points' && item.value == 100);
          if (idx != -1) targetIndex = idx;
        }
      }
      
      // 设置消息
      if (resultType == 'airtime_points') {
        final pts = (reward['points'] as num?)?.toInt() ?? 0;
        _pendingTitle = 'Points Earned!';
        _pendingMessage = 'You earned +$pts Airtime Points!';
      } else if (resultType == 'boost_coupon') {
        final scope = (reward['pin_scope'] ?? '').toString();
        final days = (reward['pin_days'] as num?)?.toInt() ?? 3;
        _pendingTitle = 'Boost Unlocked!';
        _pendingMessage = 'You got $days Days ${scope.toUpperCase()} Boost!';
      } else {
        _pendingTitle = 'Reward Claimed!';
        _pendingMessage = 'Check your rewards for details.';
      }

      _selected.add(targetIndex);
    } catch (e) {
      setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Spin failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _handleAnimationEnd() async {
    setState(() => _isSpinning = false);

    final title = _pendingTitle ?? '';
    final message = _pendingMessage ?? '';
    final isWin = title.contains('Earned') || title.contains('Unlocked');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        backgroundColor: Colors.white,
        contentPadding: EdgeInsets.all(24.r),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kAccentGreen, kPrimaryGreen]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWin ? Icons.celebration_outlined : Icons.refresh,
                color: Colors.white,
                size: 36.r,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20.sp,
                color: kDarkGreen,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: TextStyle(
                fontSize: 15.sp,
                height: 1.5,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kAccentGreen, kPrimaryGreen, kDarkGreen]),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Text(
                    'AWESOME!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16.sp,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await widget.onAfterSpin();
  }
}

class _WheelItem {
  final String mainText;
  final String subText;
  final String type;
  final int? value;
  final String? scope;

  _WheelItem({
    required this.mainText,
    required this.subText,
    required this.type,
    this.value,
    this.scope,
  });
}
