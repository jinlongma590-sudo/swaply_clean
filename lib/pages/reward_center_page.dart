// lib/pages/reward_center_page.dart
// 修复:
// 1) Realtime 订阅使用 PostgresChangeFilterType 枚举;
// 2) 首刷强制刷新;
// 3) 邀请/任务/优惠券/日志变更即刻同步;
// 4) 任务表名改正为 user_tasks(原 reward_tasks 会收不到推送);
// 5) 更稳健的 UTF-8 乱码与分隔符归一化处理。
// 6) ✅ 历史从 coupon_usages 直接加载,不再依赖 RewardService.getUserRewardHistory
// 7) ✅ Realtime 历史频道改为监听 coupon_usages 表
// 8) ✅ 历史卡片:第一行券标题,第二行友好化 reason(app/system/auto/空隐藏或映射)
// 9) ✅ iOS 头部改为"基准页像素对齐"的自定义头;Android 保持 AppBar
// 10) ✅ 顶部区域采用「导航条渐变 + 白色卡片(统计+Tab)」布局;标题与左右按钮像素对齐
// 11) ✅ 修复 QuickStats Row 溢出问题 - 使用 Expanded 包裹子元素
// 12) ✅ Android 右上角刷新按钮尺寸固定,和 My Coupons 一致(不再撑满 AppBar)
// 13) ✅ 升级为 Reward Center:顶部增加 Airtime Points + Spins 两张卡(Redeem / Spin Now)
// 14) ✅ 新增 user_reward_state 加载 + Realtime 订阅
// 15) ✅ Redeem 按钮调用 reward_redeem_airtime RPC(你刚做完的第六步)
// 16) ✅ Spin Now:采用独立 SpinSheet(更稳,避免 RewardBottomSheet 的 listing 依赖)
// 17) ✅ 接入真实的 reward-spin Edge Function（与你贴的后端完全一致）
// 18) ✅ 修复 Spin Now 按钮逻辑:始终可点击,点击后再判断 spins
// 19) ✅ 移除前端查询奖池的依赖,简化流程
// 20) ✅ coupon_usages 同时兼容 used_at / created_at：优先 used_at，缺失则用 created_at，并用"coalesce字段"映射 created_at
// 21) ✅ GPT修复1: SpinSheet 本地状态管理(支持连续抽取,Sheet内数字实时更新)
// 22) ✅ GPT修复2: isInitialLoading 判断修复(避免首屏闪空白)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:flutter/services.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:uuid/uuid.dart';

class RewardCenterPage extends StatefulWidget {
  final int initialTab;

  const RewardCenterPage({super.key, this.initialTab = 0});

  @override
  State<RewardCenterPage> createState() => _RewardCenterPageState();
}

class _RewardCenterPageState extends State<RewardCenterPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ===== 防循环:TTL + Future缓存 =====
  static const _ttl = Duration(seconds: 30);
  static DateTime? _lastFetchAt;
  static bool _loading = false;

  Future<void>? _dataFuture;

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isRefreshing = false;

  // ✅ GPT修复2: 新增字段
  bool _hasLoadedOnce = false;

  // 数据
  List<Map<String, dynamic>> _tasks = []; // 仅活跃任务
  List<Map<String, dynamic>> _rewardHistory = [];
  Map<String, dynamic> _rewardStats = {};
  List<CouponModel> _rewardCoupons = [];

  // ===== Reward Center 新增字段 =====
  int _airtimePoints = 0;
  int _spinsBalance = 0;
  int _qualifiedCount = 0;
  String _loopProgressText = '';
  bool _isRedeeming = false;
  bool _isSpinning = false;

  // Realtime
  RealtimeChannel? _couponChannel;
  RealtimeChannel? _logsChannel;
  RealtimeChannel? _taskChannel;
  RealtimeChannel? _referralChannel;
  RealtimeChannel? _rewardStateChannel;

  // -------- UTF-8 乱码修复 --------
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

  /// 更谨慎的修复:仅在明显乱码痕迹出现时才做 cp1252→utf8 的回转
  String _fixUtf8Mojibake(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;

    // 只含 ASCII + 常见分隔符 等"安全字符"——直接返回,避免误修
    final safe = RegExp(
        r'^[\x00-\x7F\u00B7\u2022\s\.\,\;\:\!\?\-_/()\[\]&\+\%]*$');
    if (safe.hasMatch(s)) return s;

    // 只有出现这些"明显乱码痕迹"时才尝试修复
    final looksBroken =
        s.contains('Ã') || s.contains('Â') || s.contains('â') || s.contains('ð');
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

  /// 分隔符归一化:把 `Â· / â€¢ / • / ` 等统一成 " · "
  String _normalizeSeparators(String s) {
    return s
        .replaceAll('Â·', ' · ')
        .replaceAll('â€¢', ' · ')
        .replaceAll('•', ' · ')
        .replaceAll(RegExp(r'\s\u{FFFD}\s'), ' · ') // U+FFFD
        .replaceAll(RegExp(r'\s{2,}'), ' ');
  }
  // ---------------------------------

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2).toInt(),
    );

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
      value: 0.0, // 首次进入做淡入
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // 首次进入强制刷新
    _dataFuture = _loadDataOnce(force: true);

    // 建立 Realtime 订阅
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    _disposeChannel(_couponChannel);
    _disposeChannel(_logsChannel);
    _disposeChannel(_taskChannel);
    _disposeChannel(_referralChannel);
    _disposeChannel(_rewardStateChannel);
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

    // coupons(用户优惠券变化 -> 更新可用券 + 统计)
    _couponChannel = client
        .channel('rewards-coupons-${user.id}')
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
        _loadRewardStats();
      },
    )
        .subscribe();

    // ✅ coupon_usages(历史/统计变化 -> 立即刷新)
    _logsChannel = client
        .channel('rewards-logs-${user.id}')
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
        _loadRewardStats();
      },
    )
        .subscribe();

    // user_tasks(任务进度)
    _taskChannel = client
        .channel('rewards-tasks-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_tasks',
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) async {
        await _loadTasks();
        await _loadRewardStats();
      },
    )
        .subscribe();

    // referrals(邀请关系状态变化 -> 刷新统计/奖励券/历史)
    _referralChannel = client
        .channel('rewards-referrals-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'referrals',
      filter: PostgresChangeFilter(
        column: 'inviter_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) async {
        await _loadRewardStats();
        await _loadRewardCoupons();
        await _loadRewardHistory();
        await _loadRewardState(); // ✅ 新增
      },
    )
        .subscribe();

    // ✅ Reward State(Points / Spins)
    _rewardStateChannel = client
        .channel('reward-state-${user.id}')
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

  // ===== 核心:限流加载 =====
  Future<void> _loadDataOnce({bool force = false}) async {
    if (_loading) return;

    final now = DateTime.now();
    if (!force && _lastFetchAt != null && now.difference(_lastFetchAt!) < _ttl) {
      if (mounted && _animationController.value == 0.0) {
        _animationController.forward();
      }
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
        _loadTasks(),
        _loadRewardHistory(),
        _loadRewardStats(),
        _loadRewardCoupons(),
        _loadRewardState(), // ✅ 新增
      ]);

      if (mounted) {
        _animationController.forward();
        // ✅ GPT修复2: 成功后标记已加载
        _hasLoadedOnce = true;
      }
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

  // 手动刷新(强制绕过 TTL)
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    _dataFuture = _loadDataOnce(force: true);
    await _dataFuture;
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadTasks() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final tasks = await RewardService.getActiveTasks(user.id);
      if (!mounted) return;
      _tasks = tasks;
      setState(() {});
    } catch (e) {}
  }

  /// ✅ 直接从 coupon_usages 加载历史
  /// - 优先 used_at 排序
  /// - 若 used_at 为空/不存在，则用 created_at
  /// - 本地把 created_at 映射为 created_at(展示用)
  Future<void> _loadRewardHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final supabase = Supabase.instance.client;

    List<dynamic> usages = [];
    try {
      // 1) 优先 used_at（如果字段存在）
      usages = await supabase
          .from('coupon_usages')
          .select('id,coupon_id,user_id,listing_id,used_at,created_at,note,context')
          .eq('user_id', user.id)
          .order('used_at', ascending: false);
    } catch (_) {
      // 2) fallback created_at（兼容有些环境没有 used_at 或不能 order）
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

    try {
      // 2) 批量取回相关券信息
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

      // 3) 映射页面字段
      final List<Map<String, dynamic>> history = [];
      for (final u in usages) {
        if (u is! Map) continue;

        // coalesce: used_at ?? created_at
        final dynamic ts = u['used_at'] ?? u['created_at'];

        // 解析 context.source
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
          'created_at': ts, // ✅ 展示字段统一叫 created_at
          'reward_reason': (source ?? 'coupon_used'),
          'coupon_title': couponTitle,
          'reward_type': rewardType,
        });
      }

      if (!mounted) return;
      setState(() => _rewardHistory = history);
    } catch (e) {
      // 静默失败
    }
  }

  Future<void> _loadRewardStats() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final stats = await RewardService.getUserRewardStats(user.id);
      if (!mounted) return;
      setState(() => _rewardStats = stats);
    } catch (e) {}
  }

  /// ✅ 加载 Reward Center 状态(Airtime points / spins / loop)
  /// 说明:字段可能尚未完全建好,所以做"容错读取"
  Future<void> _loadRewardState() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      // 先用宽松 select(*),本地再取字段,避免字段缺失时报错(更稳)
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

  /// 放宽查询条件,只按 user_id + status=active;本地再过滤奖励券
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
      // 回退:走服务封装
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
      'trending', // 兼容 hot
      'hot',
      'category',
      'boost', // 兼容 featured
      'featured',
    };
    return rewardLike.contains(n);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return FutureBuilder<void>(
      future: _dataFuture,
      builder: (context, snapshot) {
        // ✅ GPT修复2: 使用 _hasLoadedOnce 判断
        final isInitialLoading = !_hasLoadedOnce &&
            snapshot.connectionState == ConnectionState.waiting;

        if (isIOS) {
          // ===== iOS:自定义头部(绿色渐变仅用于导航条) + 白色卡片 =====
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: Column(
              children: [
                _buildHeaderIOSRewards(context),
                _buildBodyMain(isInitialLoading),
              ],
            ),
          );
        } else {
          // ===== Android:保持 AppBar,但主体同样使用白色卡片样式 =====
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
                onPressed: () => Navigator.of(context).pop(),
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
            body: Column(
              children: [
                _buildBodyMain(isInitialLoading),
              ],
            ),
          );
        }
      },
    );
  }

  // ===== ✅ iOS 自定义头部(与基准页像素对齐,仅导航条用渐变) =====
  Widget _buildHeaderIOSRewards(BuildContext context) {
    final double statusBar = MediaQuery.of(context).padding.top;

    const double kNavBarHeight = 44.0; // 标准导航条高度
    const double kButtonSize = 32.0; // 标准按钮尺寸
    const double kSidePadding = 16.0; // 标准左右内边距
    const double kButtonSpacing = 12.0; // 标准间距

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
          height: kNavBarHeight, // 仅 44pt 导航条高度
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

  // ===== 主体内容:白色卡片(统计 + Tab) + 内容区 =====
  Widget _buildBodyMain(bool isInitialLoading) {
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildQuickStatsCardStyle(), // ✅ 已升级为 Reward Center
                    SizedBox(height: 12.h),
                    _buildTabsCardStyle(),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: isInitialLoading
                ? _buildLoadingState()
                : FadeTransition(
              opacity: _fadeAnimation,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveTasksTab(),
                  _buildRewardCouponsTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====== ✅ Reward Center 顶部概览:Points + Spins + 原有统计 ======
  Widget _buildQuickStatsCardStyle() {
    final activeTasks = _tasks.length;
    final completedTasks = (_rewardStats['completed_tasks'] as int?) ?? 0;
    final availableCoupons = _rewardCoupons.length;

    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        children: [
          _buildPointsRow(),
          SizedBox(height: 12.h),
          Divider(color: Colors.green.shade200, height: 1),
          SizedBox(height: 12.h),
          _buildSpinsRow(),
          SizedBox(height: 12.h),
          Divider(color: Colors.green.shade200, height: 1),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildQuickStatItemCard(
                  'Active\nTasks',
                  activeTasks.toString(),
                  Icons.assignment,
                ),
              ),
              Container(width: 1, height: 28.h, color: Colors.green.shade200),
              Expanded(
                child: _buildQuickStatItemCard(
                  'Completed',
                  completedTasks.toString(),
                  Icons.check_circle,
                ),
              ),
              Container(width: 1, height: 28.h, color: Colors.green.shade200),
              Expanded(
                child: _buildQuickStatItemCard(
                  'Coupons',
                  availableCoupons.toString(),
                  Icons.card_giftcard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatItemCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 20.r),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.black54,
            fontSize: 10.sp,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ✅ Airtime Points 卡片(Redeem)
  Widget _buildPointsRow() {
    final progress = (_airtimePoints / 100).clamp(0.0, 1.0);
    final canRedeem = _airtimePoints >= 100 && !_isRedeeming;

    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
        ),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 24.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Airtime Points',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
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
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ' / 100',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 4.h,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          ElevatedButton(
            onPressed: canRedeem ? _onRedeemPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.3),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: _isRedeeming
                ? SizedBox(
              width: 16.r,
              height: 16.r,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4CAF50),
              ),
            )
                : Text(
              'Redeem',
              style: TextStyle(
                fontSize: 13.sp,
                color: canRedeem
                    ? const Color(0xFF4CAF50)
                    : Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Spins 卡片(Spin Now) - 修复:始终可点击
  Widget _buildSpinsRow() {
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.casino,
              color: Colors.white,
              size: 24.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Spins',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '$_spinsBalance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_loopProgressText.trim().isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    _loopProgressText.trim(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11.sp,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (_qualifiedCount > 0) ...[
                  SizedBox(height: 4.h),
                  Text(
                    'Qualified listings: $_qualifiedCount',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11.sp,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 12.w),
          ElevatedButton(
            onPressed: _isSpinning ? null : _onSpinNowPressed, // ✅ 始终可点
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.3),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: _isSpinning
                ? SizedBox(
              width: 16.r,
              height: 16.r,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF1976D2),
              ),
            )
                : Text(
              'Spin Now',
              style: TextStyle(
                fontSize: 13.sp,
                color: const Color(0xFF2196F3),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====== 白卡内的分段 Tab ======
  Widget _buildTabsCardStyle() {
    return Container(
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
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12.sp,
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
                Icon(Icons.assignment, size: 14.r),
                SizedBox(width: 4.w),
                const Text('Tasks'),
              ],
            ),
          ),
          Tab(
            height: 44.h,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_giftcard, size: 14.r),
                SizedBox(width: 4.w),
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
                Icon(Icons.history, size: 14.r),
                SizedBox(width: 4.w),
                const Text('History'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
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
              children: [
                SizedBox(
                  width: 40.r,
                  height: 40.r,
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
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
        ],
      ),
    );
  }

  Widget _buildActiveTasksTab() {
    final activeTasks = _tasks;

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: activeTasks.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.assignment_outlined,
            title: 'No Active Tasks',
            subtitle: 'Complete daily activities to earn rewards',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: activeTasks.length,
        itemBuilder: (context, index) =>
            _buildTaskCard(activeTasks[index], index),
      ),
    );
  }

  Widget _buildRewardCouponsTab() {
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
            subtitle: 'Complete tasks to earn reward coupons',
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

  // ===== Cards =====

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final currentCount = task['current_count'] as int? ?? 0;
    final targetCount = task['target_count'] as int? ?? 1;
    final progress = targetCount > 0 ? currentCount / targetCount : 0.0;
    final isCompleted = task['status'] == 'completed';

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15.r,
            offset: Offset(0, 5.h),
          ),
        ],
        border: isCompleted
            ? Border.all(color: Colors.green.withOpacity(0.3), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48.r,
                height: 48.r,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCompleted
                        ? [Colors.green.shade400, Colors.green.shade600]
                        : [const Color(0xFF4CAF50), const Color(0xFF45A049)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle
                      : _getTaskIcon(task['task_type']),
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
                      task['task_name'] ??
                          _getTaskDisplayName(task['task_type']),
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (task['description'] != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        _normalizeSeparators(
                            _fixUtf8Mojibake(task['description'])),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Text(
                'Progress: $currentCount/$targetCount',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? Colors.green : const Color(0xFF4CAF50),
              ),
              minHeight: 6.h,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCouponCard(CouponModel coupon, int index) {
    final fixedTitle = _normalizeSeparators(_fixUtf8Mojibake(coupon.title));
    final fixedDesc = _normalizeSeparators(_fixUtf8Mojibake(coupon.description));

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
                  padding:
                  EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
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
                padding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
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
    // created_at 可能是 String / DateTime / null（我们在 _loadRewardHistory 里 coalesce 过）
    final rawTs = reward['created_at'];
    DateTime createdAt;
    if (rawTs is DateTime) {
      createdAt = rawTs;
    } else if (rawTs is String) {
      createdAt = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    // 第一行券标题;第二行友好化 reason
    final couponTitle = _normalizeSeparators(
      _fixUtf8Mojibake(reward['coupon_title'] ?? 'Coupon Reward'),
    );

    final rawReason =
    (reward['reward_reason'] ?? '').toString().trim().toLowerCase();

    String prettyReason(String raw, String? type) {
      if (raw.isEmpty || raw == 'app' || raw == 'system' || raw == 'auto') {
        switch ((type ?? '').toLowerCase()) {
          case 'welcome':
            return 'Welcome reward';
          case 'referral_bonus':
            return 'Referral reward';
          case 'activity_bonus':
            return 'Task reward';
          default:
            return '';
        }
      }
      return _normalizeSeparators(_fixUtf8Mojibake(raw));
    }

    final reason = prettyReason(rawReason, reward['reward_type']);

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
                if (reason.isNotEmpty) ...[
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

  void _onUseNowPressed(CouponModel coupon) {
    if (!coupon.canPin || !coupon.isUsable) return;
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (context) => const SellFormPage(),
        settings: RouteSettings(arguments: {'couponId': coupon.id}),
      ),
    );
  }

  // ====== ✅ Redeem Logic (RPC: reward_redeem_airtime) ======
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem Airtime'),
        content: const Text('Redeem 100 points for airtime credit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRedeeming = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.rpc(
        'reward_redeem_airtime',
        params: {
          'p_user': user.id,
          'p_campaign': 'launch_v1',
          'p_points': 100,
        },
      );

      // 刷新(Realtime 可能也会推,但这里主动刷新更及时)
      await _loadRewardState();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Redemption submitted! We will contact you soon.'),
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

  // ====== ✅ Spin Now Logic（完全对齐你当前 Edge Function 的返回） ======
  Future<void> _onSpinNowPressed() async {
    if (_isSpinning) return;

    // ✅ 修复:点击后再检查 spins,而不是按钮禁用
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

      await showModalBottomSheet(
        context: context,
        useRootNavigator: true, // ✅ 多 Navigator / 多 Tab 更稳
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SpinSheet(
          airtimePoints: _airtimePoints,
          spins: _spinsBalance,
          qualifiedCount: _qualifiedCount,
          loopProgressText: _loopProgressText,
          onAfterSpin: () async {
            await _loadRewardState();
            await _loadRewardCoupons();
            await _loadRewardHistory();
            await _loadRewardStats();
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

  // ===== Helper methods =====
  IconData _getTaskIcon(String? taskType) {
    switch (taskType) {
      case 'publish_items':
        return Icons.publish;
      case 'invite_friends':
        return Icons.group_add;
      case 'daily_check':
        return Icons.check_circle;
      default:
        return Icons.assignment;
    }
  }

  String _getTaskDisplayName(String? taskType) {
    switch (taskType) {
      case 'publish_items':
        return 'Publish Items';
      case 'invite_friends':
        return 'Invite Friends';
      case 'daily_check':
        return 'Daily Check-in';
      default:
        return 'Task';
    }
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

  /// 将券类型映射为历史卡片用的 reward_type
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

// ============================================================
// ✅ 独立 SpinSheet(接入真实 reward-spin Edge Function，完全对齐后端返回)
// ✅ GPT修复1: 添加本地状态管理，支持连续抽取，Sheet内数字实时更新
// ============================================================
class _SpinSheet extends StatefulWidget {
  final int airtimePoints;
  final int spins;
  final int qualifiedCount;
  final String loopProgressText;
  final Future<void> Function() onAfterSpin;

  const _SpinSheet({
    required this.airtimePoints,
    required this.spins,
    required this.qualifiedCount,
    required this.loopProgressText,
    required this.onAfterSpin,
  });

  @override
  State<_SpinSheet> createState() => _SpinSheetState();
}

class _SpinSheetState extends State<_SpinSheet> {
  bool _busy = false;

  // ✅ GPT修复1: 添加本地状态
  late int _localSpins;
  late int _localPoints;
  late int _localQualified;
  late String _localLoopText;

  @override
  void initState() {
    super.initState();
    // ✅ GPT修复1: 初始化本地状态
    _localSpins = widget.spins;
    _localPoints = widget.airtimePoints;
    _localQualified = widget.qualifiedCount;
    _localLoopText = widget.loopProgressText;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          margin: EdgeInsets.all(12.w),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // handle
              Container(
                width: 44.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: [
                  Text(
                    'Spin & Win',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  // ✅ GPT修复1: 使用本地状态显示
                  'Spins: $_localSpins  •  Points: $_localPoints',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_localLoopText.trim().isNotEmpty) ...[
                SizedBox(height: 6.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _localLoopText.trim(),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
              SizedBox(height: 20.h),

              // Spin action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _spinOnce,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                    width: 20.r,
                    height: 20.r,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    'Spin Now',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 10.h),
              Text(
                'Tap to spin and win rewards!',
                style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
              ),
              SizedBox(height: 6.h),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 接入真实的 reward-spin Edge Function（对齐你现在的后端：spins_left/airtime_points/qualified_count/reward）
  // ✅ GPT修复1: spin成功后立即更新本地状态
  Future<void> _spinOnce() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final supabase = Supabase.instance.client;

      // ✅ 幂等 request_id:一次点击一个
      final requestId = const Uuid().v4();

      final res = await supabase.functions.invoke(
        'reward-spin',
        body: {
          'campaign_code': 'launch_v1',
          'request_id': requestId,
          // listing_id / device_id 可选：Reward Center 场景可不传
        },
      );

      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      // 后端在 no_spins 时会返回 ok:false reason:no_spins status=200
      final ok = data['ok'] == true;
      if (!ok) {
        final reason = (data['reason'] ?? data['error'] ?? 'spin failed').toString();
        throw Exception(reason);
      }

      // ✅ GPT修复1: 用后端回包即时更新 Sheet 内显示（关键）
      final spinsLeft = (data['spins_left'] as num?)?.toInt();
      final points = (data['airtime_points'] as num?)?.toInt();
      final qualified = (data['qualified_count'] as num?)?.toInt();

      if (mounted) {
        setState(() {
          if (spinsLeft != null) _localSpins = spinsLeft;
          if (points != null) _localPoints = points;
          if (qualified != null) _localQualified = qualified;
        });
      }

      final reward = (data['reward'] is Map)
          ? Map<String, dynamic>.from(data['reward'] as Map)
          : <String, dynamic>{};

      // 后端 rewardPayload 一定带 result_type
      final resultType = (reward['result_type'] ?? 'none').toString();

      String title;
      String message;

      if (resultType == 'airtime_points') {
        final pts = reward['points'] ?? 0;
        final newPts = reward['new_points'] ?? _localPoints;
        title = '🎉 Airtime Points';
        message = '+$pts points (now: $newPts)';
      } else if (resultType == 'boost_coupon') {
        // 你后端返回：pin_scope / pin_days / coupon_id
        final pinDays = reward['pin_days'] ?? '';
        final scope = reward['pin_scope'] ?? '';
        title = '🎁 Boost Coupon';
        message = '$pinDays days • $scope';
      } else {
        title = 'No reward';
        message = 'Better luck next time!';
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // ✅ 刷新 Reward Center:points / spins / coupons / history / stats
      await widget.onAfterSpin();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Spin failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}