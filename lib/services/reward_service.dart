// lib/services/reward_service.dart - 里程碑单张奖励券版（1/5/10）
// 说明：
// - 采用 30s 内存缓存（统计 / 概览 / 历史等接口）
// - 不在本 Service 内调用 supabase.auth.refreshSession()
// - 推荐通过后端 RPC `issue_referral_milestone_reward` 发放；若不可用，前端兜底：
//    • 1 人：发 1 × Category Pin (3d)
//    • 5 人：发 1 × Search/Popular Pin (3d) —— 使用 CouponService.createSearchPopularCoupon（type='featured' + pin_scope='search'；用券时后端 RPC 完成搜索置顶 + Popular 注入）
//    • 10 人：发 1 × Home Trending (7d)

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/services/coupon_service.dart';
import 'dart:math';

/// 新增：统一承载 ensure_welcome_coupon 返回
class EnsureWelcomeResult {
  final bool created; // 本次是否新建了欢迎券
  final bool welcomeGranted; // 服务端是否已标记发过欢迎券
  final bool shouldPopup; // 只在“首次真正创建且此前未标记”时为 true
  final String? couponId; // 欢迎券的 id（服务端返回）
  EnsureWelcomeResult({
    required this.created,
    required this.welcomeGranted,
    required this.shouldPopup,
    this.couponId,
  });
}

class RewardService {
  static final SupabaseClient _client = Supabase.instance.client;

  // ===== 缓存 =====
  static const _ttl = Duration(seconds: 30);
  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<dynamic>> _inflight = {};

  static void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  static void _debugPrint(String message) {
    if (kDebugMode) print('[RewardService] $message');
  }

  // ===== Welcome Gift（一次性）=====
  // 仅用于“本进程防抖”，不再决定是否弹窗
  static bool _welcomeChecked = false;

  /// 新增：登录后统一调用。只看服务端“唯一事实”。
  /// - 成功时返回 EnsureWelcomeResult（依赖 ensure_welcome_coupon）
  /// - 抛错时由上层决定是否忽略（推荐忽略，不弹窗）
  ///
  /// ✅ [已按要求修改]：增加了客户端幂等性检查。
  static Future<EnsureWelcomeResult> ensureWelcomeForCurrentUser() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in');

    // ✅ [新增逻辑]：按照你的要求，在调用 RPC 前，先在客户端检查是否已存在 'welcome' 券
    try {
      final exist = await _client
          .from('coupons')
          .select('id') // 只需要知道存不存在
          .eq('user_id', uid)
          .eq('type', 'welcome')
          .limit(1);

      if (exist.isNotEmpty) {
        _debugPrint('Welcome coupon already exists for $uid (client-side check). Forcing shouldPopup=false.');
        // 如果已存在，直接返回 "不需要弹窗"，阻止后续 RPC
        return EnsureWelcomeResult(
          created: false, // 本次未创建
          welcomeGranted: true, // 视为已授予
          shouldPopup: false, // ✅ 关键：强制不弹窗
          couponId: (exist.first as Map<String, dynamic>?)?['id'] as String?,
        );
      }
    } catch (e) {
      // 如果检查出错（比如 RLS 权限问题），打印日志但继续执行 RPC（保持原有逻辑）
      _debugPrint('Client-side pre-check for welcome coupon failed: $e. Proceeding with RPC.');
    }
    // ✅ [新增逻辑结束]

    // [原有逻辑]：仅在客户端检查不存在 'welcome' 券时才执行
    final res =
    await _client.rpc('ensure_welcome_coupon', params: {'p_user': uid});
    final map = (res is Map)
        ? Map<String, dynamic>.from(res)
        : <String, dynamic>{};

    return EnsureWelcomeResult(
      created: map['created'] == true,
      welcomeGranted: map['welcome_reward_granted'] == true,
      shouldPopup: map['should_popup'] == true,
      couponId: map['coupon_id'] as String?,
    );
  }

  /// 改造：不再前端插券。调用 RPC 后返回欢迎券行（若存在）。
  static Future<Map<String, dynamic>?> ensureWelcomeGiftRow(
      String userId) async {
    if (userId.isEmpty) return null;

    try {
      // 1) 调服务端幂等 RPC（内部已保障并发/唯一性/置位 profiles）
      final res = await _client
          .rpc('ensure_welcome_coupon', params: {'p_user': userId});
      final map = (res is Map)
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{};
      final couponId = map['coupon_id'] as String?;

      // 2) 优先用 coupon_id 精准取券，否则回落到“取该用户最近的 welcome 券”
      Map<String, dynamic>? row;
      if (couponId != null) {
        final r = await _client
            .from('coupons')
            .select('id, code, title, description, expires_at, status, type')
            .eq('id', couponId)
            .maybeSingle();
        if (r != null) row = Map<String, dynamic>.from(r);
      }

      if (row == null) {
        final existingList = await _client
            .from('coupons')
            .select('id, code, title, description, expires_at, status, type')
            .eq('user_id', userId)
            .eq('type', 'welcome')
            .order('created_at', ascending: false)
            .limit(1);

        if (existingList.isNotEmpty) {
          row = Map<String, dynamic>.from(existingList.first);
        }
      }

      _welcomeChecked = true; // 仅防抖，无决策意义
      return row;
    } catch (e) {
      _debugPrint('ensureWelcomeGiftRow (RPC) failed: $e');

      // 兜底：只读查询（不再前端插券），避免重复发放
      try {
        final existingList = await _client
            .from('coupons')
            .select('id, code, title, description, expires_at, status, type')
            .eq('user_id', userId)
            .eq('type', 'welcome')
            .order('created_at', ascending: false)
            .limit(1);

        if (existingList.isNotEmpty) {
          _welcomeChecked = true;
          return Map<String, dynamic>.from(existingList.first);
        }
      } catch (_) {}
      return null;
    }
  }

  /// 改造：返回“服务端是否已标记发过欢迎礼”
  static Future<bool> ensureWelcomeGiftFor(String userId) async {
    if (userId.isEmpty) return false;
    try {
      final res = await _client
          .rpc('ensure_welcome_coupon', params: {'p_user': userId});
      final map = (res is Map)
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{};
      final granted = map['welcome_reward_granted'] == true;
      _welcomeChecked = true; // 仅防抖
      return granted;
    } catch (e) {
      _debugPrint('ensureWelcomeGiftFor (RPC) failed: $e');
      // 兜底：只要数据库里已有 welcome 券，也视为“已发”
      try {
        final has = await _client
            .from('coupons')
            .select('id')
            .eq('user_id', userId)
            .eq('type', 'welcome')
            .limit(1);
        final existed = (has.isNotEmpty);
        return existed;
      } catch (_) {
        return false;
      }
    }
  }

  // ===== 核心缓存 =====
  static Future<Map<String, dynamic>> getSummary(
      {required String userId}) async {
    final key = 'summary:$userId';
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.ts) < _ttl) {
      return cached.data as Map<String, dynamic>;
    }
    final inflight = _inflight[key];
    if (inflight != null) return await inflight as Map<String, dynamic>;

    final future = _fetchSummary(userId, key, now);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _fetchSummary(
      String userId, String cacheKey, DateTime now) async {
    try {
      final stats = await getUserRewardStats(userId);

      final activeTasks = await _client
          .from('user_tasks')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active');

      final activeTaskCount = (activeTasks.length);

      final activeCoupons = await _client
          .from('coupons')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active')
          .or('source.eq.rewards,source.eq.reward,source.eq.task,source.eq.signup,type.eq.welcome');

      final activeCouponCount =
      (activeCoupons.length);

      final summary = {
        'points': stats['total_rewards'] ?? 0,
        'coupons': activeCouponCount,
        'tasks': activeTaskCount,
        'completed_tasks': stats['completed_tasks'] ?? 0,
        'total_tasks': stats['total_tasks'] ?? 0,
        'stats': stats,
      };

      _cache[cacheKey] = _CacheEntry(now, summary);
      return summary;
    } on PostgrestException catch (e) {
      if (_is401Error(e)) {
        _debugPrint('Unauthorized (401) - return empty summary');
        final empty = _getEmptySummary();
        _cache[cacheKey] = _CacheEntry(now, empty);
        return empty;
      }
      rethrow;
    } catch (e) {
      _debugPrint('Error fetching summary: $e');
      final empty = _getEmptySummary();
      _cache[cacheKey] = _CacheEntry(now, empty);
      return empty;
    }
  }

  static bool _is401Error(PostgrestException e) {
    final msg = (e.message ?? '').toString().toLowerCase();
    final hint = (e.hint ?? '').toString().toLowerCase();
    final details = (e.details ?? '').toString().toLowerCase();
    final code = (e.code ?? '').toString().toLowerCase();

    return code == 'pgrst301' ||
        code == 'pgrst101' ||
        code == '28p01' ||
        code == '401' ||
        msg.contains('invalid jwt') ||
        msg.contains('jwt expired') ||
        msg.contains('unauthorized') ||
        hint.contains('invalid jwt') ||
        hint.contains('jwt expired') ||
        details.contains('invalid jwt') ||
        details.contains('jwt expired');
  }

  static Map<String, dynamic> _getEmptySummary() => {
    'points': 0,
    'coupons': 0,
    'tasks': 0,
    'completed_tasks': 0,
    'total_tasks': 0,
    'stats': {},
  };

  static String _generateInvitationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return 'INV${List.generate(6, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  // ===== 1. 注册奖励 =====
  static Future<bool> grantRegistrationReward(String userId) async {
    try {
      if (userId.trim().isEmpty) return false;

      _debugPrint('Granting registration reward to user: $userId');

      final existingReward = await _client
          .from('reward_logs')
          .select('id')
          .eq('user_id', userId)
          .eq('reward_type', 'register_bonus')
          .maybeSingle();

      if (existingReward != null) {
        _debugPrint('User has already received registration reward');
        return false;
      }

      final tasksCreated = await _createInitialTasks(userId);
      if (!tasksCreated) _debugPrint('Warning: failed to create initial tasks');

      final coupon = await CouponService.createCoupon(
        userId: userId,
        type: CouponType.category,
        title: 'New User Category Pinning Coupon',
        description:
        'Welcome to Swaply! Use this coupon to pin your item in category page for 3 days to increase exposure',
        durationDays: 3,
        maxUses: 1,
        metadata: {
          'source': 'registration_reward',
          'reward_type': 'register_bonus',
          'auto_granted': true,
          'granted_at': DateTime.now().toIso8601String(),
        },
      );

      if (coupon != null) {
        await _client.from('reward_logs').insert({
          'user_id': userId,
          'reward_type': 'register_bonus',
          'reward_reason': 'New user registration reward',
          'coupon_id': coupon.id,
          'metadata': {
            'actual_coupon_type': CouponType.category.value,
            'days': 3,
            'granted_at': DateTime.now().toIso8601String(),
          },
          'created_at': DateTime.now().toIso8601String(),
        });

        _debugPrint('Registration reward granted: ${coupon.code}');
        clearCache();
        return true;
      }
      _debugPrint('Failed to create registration coupon');
      return false;
    } catch (e, st) {
      _debugPrint('Failed to grant registration reward: $e');
      if (kDebugMode) print('Stack trace: $st');
      return false;
    }
  }

  static Future<bool> _createInitialTasks(String userId) async {
    try {
      if (userId.trim().isEmpty) return false;

      final existingTasks = await _client
          .from('user_tasks')
          .select('id')
          .eq('user_id', userId)
          .limit(1);

      final List<dynamic> tasksList = existingTasks;

      if (tasksList.isNotEmpty) {
        _debugPrint('User already has tasks created');
        return true;
      }

      final now = DateTime.now().toIso8601String();
      final tasks = [
        {
          'user_id': userId,
          'task_type': 'publish_items',
          'task_name': 'Publish Your First Items',
          'description':
          'Publish 3 items with images to unlock hot pinning coupon',
          'target_count': 3,
          'current_count': 0,
          'status': 'active',
          'reward_type': 'trending',
          'reward_config': {
            'days': 3,
            'actual_type': 'trending',
            'title': 'Active User Hot Pinning Coupon',
            'description':
            'Congratulations on completing the publishing task! Use this coupon to pin on homepage trending for 3 days'
          },
          'created_at': now,
        },
      ];

      await _client.from('user_tasks').insert(tasks);
      _debugPrint('Initial tasks created');
      clearCache();
      return true;
    } catch (e) {
      _debugPrint('Failed to create initial tasks: $e');
      return false;
    }
  }

  // ===== 2. 行为奖励 =====
  static Future<bool> updateTaskProgress({
    required String userId,
    required String taskType,
    int increment = 1,
  }) async {
    try {
      if (userId.trim().isEmpty || taskType.trim().isEmpty) return false;
      if (increment <= 0) return false;

      _debugPrint('Updating task progress: $userId, $taskType, +$increment');

      final response = await _client
          .from('user_tasks')
          .select('*')
          .eq('user_id', userId)
          .eq('task_type', taskType)
          .eq('status', 'active');

      final List<dynamic> tasks =
          response;

      if (tasks.isEmpty) {
        _debugPrint('No matching active tasks found');
        return false;
      }

      bool hasUpdated = false;
      for (final item in tasks) {
        try {
          final taskData = Map<String, dynamic>.from(item);
          final taskId = taskData['id'];
          final currentCount =
              (taskData['current_count'] as num?)?.toInt() ?? 0;
          final targetCount = (taskData['target_count'] as num?)?.toInt() ?? 1;
          final newCount = (currentCount + increment).clamp(0, targetCount);

          await _client.from('user_tasks').update({
            'current_count': newCount,
            'updated_at': DateTime.now().toIso8601String()
          }).eq('id', taskId);

          if (newCount >= targetCount && taskData['status'] == 'active') {
            await _completeTask(taskId.toString(), userId);
          }

          hasUpdated = true;
          _debugPrint(
              'Task progress updated: $taskType ($newCount/$targetCount)');
        } catch (e) {
          _debugPrint('Error updating individual task: $e');
        }
      }

      if (hasUpdated) clearCache();
      return hasUpdated;
    } catch (e) {
      _debugPrint('Failed to update task progress: $e');
      return false;
    }
  }

  static Future<void> _completeTask(String taskId, String userId) async {
    try {
      if (taskId.trim().isEmpty || userId.trim().isEmpty) return;

      final response = await _client
          .from('user_tasks')
          .update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String()
      })
          .eq('id', taskId)
          .select();

      final List<dynamic> taskList =
          response;
      if (taskList.isNotEmpty) {
        final taskData = Map<String, dynamic>.from(taskList.first);
        _debugPrint('Task completed: ${taskData['task_name']}');
        await _grantTaskReward(taskData);
        clearCache();
      }
    } catch (e) {
      _debugPrint('Failed to complete task: $e');
    }
  }

  static Future<void> _grantTaskReward(Map<String, dynamic> task) async {
    try {
      final userId = task['user_id']?.toString();
      final rewardType = task['reward_type']?.toString();
      final rewardConfig = task['reward_config'];

      if (userId == null || userId.isEmpty) return;
      if (rewardType == null || rewardType.isEmpty) return;

      final config = rewardConfig is Map<String, dynamic>
          ? rewardConfig
          : <String, dynamic>{};

      CouponType couponType;
      switch (rewardType) {
        case 'trending':
          couponType = CouponType.trending;
          break;
        case 'category':
          couponType = CouponType.category;
          break;
        case 'boost':
          couponType = CouponType.boost;
          break;
        default:
          couponType = CouponType.trending;
      }

      final coupon = await CouponService.createCoupon(
        userId: userId,
        type: couponType,
        title: config['title']?.toString() ?? 'Activity Reward Coupon',
        description: config['description']?.toString() ??
            'Congratulations on completing the task!',
        durationDays: (config['days'] as num?)?.toInt() ?? 3,
        maxUses: 1,
        metadata: {
          'source': 'task_reward',
          'reward_type': 'activity_bonus',
          'task_id': task['id']?.toString(),
          'task_name': task['task_name']?.toString(),
          'granted_at': DateTime.now().toIso8601String(),
        },
      );

      if (coupon != null) {
        await _client.from('user_tasks').update({
          'status': 'rewarded',
          'rewarded_at': DateTime.now().toIso8601String()
        }).eq('id', task['id']);

        await _client.from('reward_logs').insert({
          'user_id': userId,
          'reward_type': 'activity_bonus',
          'reward_reason': 'Task completed: ${task['task_name']}',
          'coupon_id': coupon.id,
          'task_id': task['id']?.toString(),
          'metadata': {
            ...config,
            'actual_coupon_type': couponType.value,
            'granted_at': DateTime.now().toIso8601String(),
          },
          'created_at': DateTime.now().toIso8601String(),
        });

        _debugPrint('Task reward granted: ${coupon.title}');
        clearCache();
      }
    } catch (e) {
      _debugPrint('Failed to grant task reward: $e');
    }
  }

  // ===== 3. 邀请奖励（referrals 版）=====

  static Future<String?> generateInvitationCode(String userId) async {
    try {
      if (userId.trim().isEmpty) return null;

      final existed = await _client
          .from('user_invite_codes')
          .select('code')
          .eq('user_id', userId)
          .maybeSingle();

      if (existed != null && existed['code'] != null) {
        final code = existed['code'].toString();
        _debugPrint('Invite code exists: $code');
        return code;
      }

      String code;
      int attempts = 0;
      const maxAttempts = 6;

      while (true) {
        code = _generateInvitationCode();
        attempts++;
        try {
          await _client.from('user_invite_codes').insert({
            'user_id': userId,
            'code': code,
            'created_at': DateTime.now().toIso8601String(),
          });
          _debugPrint('Invite code created: $code');
          return code;
        } catch (e) {
          if (attempts >= maxAttempts) {
            _debugPrint(
                'Create invite code failed after $attempts attempts: $e');
            return null;
          }
        }
      }
    } catch (e) {
      _debugPrint('generateInvitationCode error: $e');
      return null;
    }
  }

  /// 绑定邀请码（方案A：直接返回数据库函数的状态字符串）
  /// 可能返回：ok / already_linked / invalid_code / self_not_allowed / not_authenticated / error / code_not_found
  static Future<String> submitInviteCode(String code) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      _debugPrint('submitInviteCode: no current user');
      return 'not_authenticated';
    }
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return 'invalid_code';

    // 本地自检：避免输入自己的邀请码（减少一次 RPC 调用）
    try {
      final myCodeRow = await _client
          .from('user_invite_codes')
          .select('code')
          .eq('user_id', uid)
          .maybeSingle();
      final myCode = (myCodeRow?['code'] as String?)?.toUpperCase();
      if (myCode != null && myCode == c) {
        _debugPrint('submitInviteCode: self code detected');
        return 'self_not_allowed';
      }
    } catch (_) {}

    try {
      // ⚠️ 正确的参数名：p_code / p_invitee
      final res = await _client.rpc('link_referral', params: {
        'p_code': c,
        'p_invitee': uid,
      });

      final status = (res is String && res.isNotEmpty) ? res : 'ok';
      _debugPrint('link_referral result: code=$c invitee=$uid -> $status');
      return status;
    } on PostgrestException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      final codeStr = (e.code ?? '').toLowerCase();

      // 唯一约束冲突：按已绑定处理
      if (codeStr == '23505' ||
          msg.contains('unique') ||
          msg.contains('duplicate')) {
        return 'already_linked';
      }
      // 参数名不匹配/函数签名不匹配等
      if (msg.contains('could not find the function') ||
          msg.contains(
              'no function matches the given name and argument types')) {
        return 'error';
      }
      _debugPrint('link_referral error: $e');
      return 'error';
    } catch (e) {
      _debugPrint('link_referral error: $e');
      return 'error';
    }
  }

  /// 被邀请者首贴发布完成后：标记完成 + 服务端按 1/5/10 发券（security definer）
  static Future<void> handleInviteeFirstPost([String? inviteeUserId]) async {
    final uid = inviteeUserId ?? _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      _debugPrint('handleInviteeFirstPost: no invitee id');
      return;
    }
    try {
      final res =
      await _client.rpc('complete_referral', params: {'p_invitee': uid});

      if (res is String && res.isNotEmpty) {
        final inviterId = res;
        _debugPrint('referral completed, inviter=$inviterId');

        // 优先使用后端 RPC（单张里程碑券：1/5/10）
        try {
          final r =
          await _client.rpc('issue_referral_milestone_reward', params: {
            'p_inviter': inviterId,
          });
          _debugPrint('issue_referral_milestone_reward: $r');
        } catch (e) {
          _debugPrint('issue_referral_milestone_reward error: $e');
          // 兜底（若无 RPC 或 RLS 拦截）：前端计算发券
          await _grantReferralRewardByCount(inviterId);
        }
      } else {
        _debugPrint('referral complete: no pending record for $uid');
      }
    } catch (e) {
      _debugPrint('complete_referral error: $e');
      rethrow;
    }
  }

  /// 兜底：按完成数计算并发券（仅在邀请人自己的会话里运行才不会被 RLS 拦）
  static Future<void> _grantReferralRewardByCount(String inviterId) async {
    try {
      if (inviterId.trim().isEmpty) return;

      final response = await _client
          .from('referrals')
          .select('id')
          .eq('inviter_id', inviterId)
          .eq('status', 'completed');

      final List<dynamic> completed =
          response;
      final count = completed.length;
      _debugPrint('Completed referrals count: $count');

      String? rewardLevel;

      if (count == 1) {
        // 1 人：分类置顶 3 天
        rewardLevel = 'm1';

        final already = await _client
            .from('reward_logs')
            .select('id')
            .eq('user_id', inviterId)
            .eq('reward_type', 'referral_bonus')
            .contains('metadata', {'reward_level': rewardLevel}).maybeSingle();
        if (already != null) {
          _debugPrint('Reward for $rewardLevel already granted');
          return;
        }

        final coupon = await CouponService.createCoupon(
          userId: inviterId,
          type: CouponType.category,
          title: 'Referral Reward · Category Pin (3d)',
          description: 'Invite 1 friend completed — category pin for 3 days',
          durationDays: 3,
          maxUses: 1,
          metadata: {
            'source': 'referral_reward',
            'reward_type': 'referral_bonus',
            'completed_referrals': count,
            'reward_level': rewardLevel,
            'granted_at': DateTime.now().toIso8601String(),
          },
        );

        if (coupon != null) {
          await _client.from('reward_logs').insert({
            'user_id': inviterId,
            'reward_type': 'referral_bonus',
            'reward_reason': 'Friend referral reward (${count}th friend)',
            'coupon_id': coupon.id,
            'metadata': {
              'completed_referrals': count,
              'reward_level': rewardLevel,
              'actual_coupon_type': CouponType.category.value,
              'days': 3,
              'granted_at': DateTime.now().toIso8601String(),
            },
            'created_at': DateTime.now().toIso8601String(),
          });
          _debugPrint('Referral milestone reward granted: M1 - Category(3d)');
          clearCache();
        }
      } else if (count == 5) {
        // 5 人：Search/Popular Pin 3 天（featured/search；用券时 RPC 完成搜索 + Popular）
        rewardLevel = 'm5';

        final already = await _client
            .from('reward_logs')
            .select('id')
            .eq('user_id', inviterId)
            .eq('reward_type', 'referral_bonus')
            .contains('metadata', {'reward_level': rewardLevel}).maybeSingle();
        if (already != null) {
          _debugPrint('Reward for $rewardLevel already granted');
          return;
        }

        final coupon = await CouponService.createSearchPopularCoupon(
          userId: inviterId,
          durationDays: 3,
          title: 'Referral Reward · Search/Popular Pin (3d)',
          description:
          'Invite 5 friends completed — search top & appear in Popular for 3 days',
        );

        if (coupon != null) {
          await _client.from('reward_logs').insert({
            'user_id': inviterId,
            'reward_type': 'referral_bonus',
            'reward_reason': 'Friend referral reward (${count}th friend)',
            'coupon_id': coupon.id,
            'metadata': {
              'completed_referrals': count,
              'reward_level': rewardLevel,
              'actual_coupon_type': 'featured',
              'pin_scope': 'search',
              'days': 3,
              'granted_at': DateTime.now().toIso8601String(),
            },
            'created_at': DateTime.now().toIso8601String(),
          });
          _debugPrint(
              'Referral milestone reward granted: M5 - Search/Popular(3d)');
          clearCache();
        }
      } else if (count == 10) {
        // 10 人：首页 Trending 7 天
        rewardLevel = 'm10';

        final already = await _client
            .from('reward_logs')
            .select('id')
            .eq('user_id', inviterId)
            .eq('reward_type', 'referral_bonus')
            .contains('metadata', {'reward_level': rewardLevel}).maybeSingle();
        if (already != null) {
          _debugPrint('Reward for $rewardLevel already granted');
          return;
        }

        final coupon = await CouponService.createCoupon(
          userId: inviterId,
          type: CouponType.trending,
          title: 'Referral Reward · Home Trending (7d)',
          description:
          'Invite 10 friends completed — homepage trending for 7 days',
          durationDays: 7,
          maxUses: 1,
          metadata: {
            'source': 'referral_reward',
            'reward_type': 'referral_bonus',
            'completed_referrals': count,
            'reward_level': rewardLevel,
            'granted_at': DateTime.now().toIso8601String(),
          },
        );

        if (coupon != null) {
          await _client.from('reward_logs').insert({
            'user_id': inviterId,
            'reward_type': 'referral_bonus',
            'reward_reason': 'Friend referral reward (${count}th friend)',
            'coupon_id': coupon.id,
            'metadata': {
              'completed_referrals': count,
              'reward_level': rewardLevel,
              'actual_coupon_type': CouponType.trending.value,
              'days': 7,
              'granted_at': DateTime.now().toIso8601String(),
            },
            'created_at': DateTime.now().toIso8601String(),
          });
          _debugPrint('Referral milestone reward granted: M10 - Trending(7d)');
          clearCache();
        }
      } else {
        _debugPrint('No milestone reward for count=$count');
      }
    } catch (e) {
      _debugPrint('grantReferralRewardByCount failed: $e');
    }
  }

  // ===== 4. 配额控制 =====
  static Future<bool> checkAndConsumeQuota({
    required String quotaType,
    int maxDaily = 20,
  }) async {
    try {
      if (quotaType.trim().isEmpty || maxDaily <= 0) return false;

      final today = DateTime.now().toIso8601String().substring(0, 10);

      var quota = await _client
          .from('daily_quotas')
          .select('*')
          .eq('date', today)
          .eq('quota_type', quotaType)
          .maybeSingle();

      if (quota == null) {
        try {
          final resp = await _client
              .from('daily_quotas')
              .insert({
            'date': today,
            'quota_type': quotaType,
            'max_count': maxDaily,
            'used_count': 0,
            'created_at': DateTime.now().toIso8601String(),
          })
              .select()
              .single();
          quota = resp;
        } catch (_) {
          quota = await _client
              .from('daily_quotas')
              .select('*')
              .eq('date', today)
              .eq('quota_type', quotaType)
              .maybeSingle();
          if (quota == null) return false;
        }
      }

      final q = Map<String, dynamic>.from(quota);
      final used = (q['used_count'] as num?)?.toInt() ?? 0;
      final max = (q['max_count'] as num?)?.toInt() ?? maxDaily;

      if (used >= max) {
        _debugPrint('Daily quota exhausted: $quotaType ($used/$max)');
        return false;
      }

      await _client.from('daily_quotas').update({
        'used_count': used + 1,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', q['id']);

      _debugPrint('Quota consumed: $quotaType (${used + 1}/$max)');
      return true;
    } catch (e) {
      _debugPrint('checkAndConsumeQuota error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getQuotaStatus(String quotaType) async {
    try {
      if (quotaType.trim().isEmpty) {
        return {'error': 'Invalid quota type'};
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);

      final quota = await _client
          .from('daily_quotas')
          .select('*')
          .eq('date', today)
          .eq('quota_type', quotaType)
          .maybeSingle();

      if (quota == null) {
        return {
          'date': today,
          'quota_type': quotaType,
          'used_count': 0,
          'max_count': 20,
          'remaining': 20,
          'available': true,
          'usage_percentage': 0.0,
        };
      }

      final q = Map<String, dynamic>.from(quota);
      final used = (q['used_count'] as num?)?.toInt() ?? 0;
      final max = (q['max_count'] as num?)?.toInt() ?? 20;
      final remaining = (max - used).clamp(0, max);

      return {
        'date': today,
        'quota_type': quotaType,
        'used_count': used,
        'max_count': max,
        'remaining': remaining,
        'available': remaining > 0,
        'usage_percentage':
        max > 0 ? (used / max * 100).clamp(0.0, 100.0) : 0.0,
      };
    } catch (e) {
      _debugPrint('getQuotaStatus error: $e');
      return {
        'error': e.toString(),
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'quota_type': quotaType,
        'used_count': 0,
        'max_count': 0,
        'remaining': 0,
        'available': false,
        'usage_percentage': 0.0,
      };
    }
  }

  // ===== 5. 统计与查询 =====
  static Future<Map<String, dynamic>> getUserRewardStats(String userId) async {
    final key = 'stats:$userId';
    final now = DateTime.now();

    final cached = _cache[key];
    if (cached != null && now.difference(cached.ts) < _ttl) {
      return cached.data as Map<String, dynamic>;
    }
    final inflight = _inflight[key];
    if (inflight != null) return await inflight as Map<String, dynamic>;

    final future = _fetchUserRewardStats(userId, key, now);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _fetchUserRewardStats(
      String userId, String cacheKey, DateTime now) async {
    try {
      if (userId.trim().isEmpty) return _getEmptyStats();

      final futures = await Future.wait([
        _client.from('reward_logs').select('*').eq('user_id', userId),
        _client.from('user_tasks').select('*').eq('user_id', userId),
        _client.from('referrals').select('*').eq('inviter_id', userId),
      ]);

      final rewardsResponse = futures[0];
      final tasksResponse = futures[1];
      final referralsResponse = futures[2];

      final List<dynamic> rewards = rewardsResponse;
      final List<dynamic> tasks = tasksResponse;
      final List<dynamic> referrals = referralsResponse;

      int countRewardsByType(String type) {
        return rewards.where((r) {
          try {
            final reward = Map<String, dynamic>.from(r);
            return reward['reward_type']?.toString() == type;
          } catch (_) {
            return false;
          }
        }).length;
      }

      int countTasksByStatus(List<String> statuses) {
        return tasks.where((t) {
          try {
            final task = Map<String, dynamic>.from(t);
            final status = task['status']?.toString() ?? '';
            return statuses.contains(status);
          } catch (_) {
            return false;
          }
        }).length;
      }

      int countReferralsByStatus(String status) {
        return referrals.where((i) {
          try {
            final rec = Map<String, dynamic>.from(i);
            return rec['status']?.toString() == status;
          } catch (_) {
            return false;
          }
        }).length;
      }

      final totalTasks = tasks.length;
      final completedTasks = countTasksByStatus(['completed', 'rewarded']);
      final totalInvitations = referrals.length;
      final successfulInvitations = countReferralsByStatus('completed');

      final stats = {
        'total_rewards': rewards.length,
        'register_rewards': countRewardsByType('register_bonus'),
        'activity_rewards': countRewardsByType('activity_bonus'),
        'referral_rewards': countRewardsByType('referral_bonus'),
        'total_tasks': totalTasks,
        'completed_tasks': completedTasks,
        'pending_tasks': countTasksByStatus(['active']),
        'task_completion_rate': totalTasks > 0
            ? (completedTasks / totalTasks * 100).clamp(0.0, 100.0)
            : 0.0,
        'total_invitations': totalInvitations,
        'successful_invitations': successfulInvitations,
        'pending_invitations': countReferralsByStatus('pending'),
        'accepted_invitations': 0,
        'invitation_success_rate': totalInvitations > 0
            ? (successfulInvitations / totalInvitations * 100).clamp(0.0, 100.0)
            : 0.0,
      };

      _cache[cacheKey] = _CacheEntry(now, stats);
      return stats;
    } on PostgrestException catch (e) {
      if (_is401Error(e)) {
        _debugPrint('Unauthorized - returning empty stats');
        final empty = _getEmptyStats();
        _cache[cacheKey] = _CacheEntry(now, empty);
        return empty;
      }
      rethrow;
    } catch (e) {
      _debugPrint('Failed to get reward statistics: $e');
      final empty = _getEmptyStats();
      _cache[cacheKey] = _CacheEntry(now, empty);
      return empty;
    }
  }

  static Map<String, dynamic> _getEmptyStats() => {
    'total_rewards': 0,
    'register_rewards': 0,
    'activity_rewards': 0,
    'referral_rewards': 0,
    'total_tasks': 0,
    'completed_tasks': 0,
    'pending_tasks': 0,
    'task_completion_rate': 0.0,
    'total_invitations': 0,
    'successful_invitations': 0,
    'pending_invitations': 0,
    'accepted_invitations': 0,
    'invitation_success_rate': 0.0,
  };

  static Future<List<Map<String, dynamic>>> getUserInvitations(
      String userId) async {
    try {
      if (userId.trim().isEmpty) return [];

      final response = await _client
          .from('referrals')
          .select('*')
          .eq('inviter_id', userId)
          .order('created_at', ascending: false);

      final List<dynamic> list =
          response;
      return list
          .map<Map<String, dynamic>>((item) {
        try {
          return Map<String, dynamic>.from(item);
        } catch (_) {
          return <String, dynamic>{};
        }
      })
          .where((e) => e.isNotEmpty)
          .toList();
    } on PostgrestException catch (e) {
      if (_is401Error(e)) return [];
      rethrow;
    } catch (e) {
      _debugPrint('getUserInvitations error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserRewardHistory(
      String userId) async {
    final key = 'history:$userId';
    final now = DateTime.now();

    final cached = _cache[key];
    if (cached != null && now.difference(cached.ts) < _ttl) {
      return cached.data as List<Map<String, dynamic>>;
    }
    final inflight = _inflight[key];
    if (inflight != null) return await inflight as List<Map<String, dynamic>>;

    final future = _fetchUserRewardHistory(userId, key, now);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchUserRewardHistory(
      String userId, String cacheKey, DateTime now) async {
    try {
      if (userId.trim().isEmpty) return [];

      final response = await _client.from('reward_logs').select('''
            *,
            coupons:coupon_id (code, type, title, status)
          ''').eq('user_id', userId).order('created_at', ascending: false);

      final List<dynamic> rewards =
          response;

      final result = rewards
          .map<Map<String, dynamic>>((item) {
        try {
          final rewardData = Map<String, dynamic>.from(item);
          if (rewardData['coupons'] != null &&
              rewardData['coupons'] is Map) {
            final couponData =
            Map<String, dynamic>.from(rewardData['coupons']);
            rewardData['coupon_code'] = couponData['code'];
            rewardData['coupon_title'] = couponData['title'];
            rewardData['coupon_status'] = couponData['status'];
            rewardData['coupon_type'] = couponData['type'];
          }
          return rewardData;
        } catch (_) {
          return <String, dynamic>{};
        }
      })
          .where((e) => e.isNotEmpty)
          .toList();

      _cache[cacheKey] = _CacheEntry(now, result);
      return result;
    } on PostgrestException catch (e) {
      if (_is401Error(e)) {
        _cache[cacheKey] = _CacheEntry(now, []);
        return [];
      }
      rethrow;
    } catch (e) {
      _debugPrint('getUserRewardHistory error: $e');
      _cache[cacheKey] = _CacheEntry(now, []);
      return [];
    }
  }

  // 智能置顶
  static Future<Map<String, dynamic>> useSmartPinning({
    required String couponId,
    required String listingId,
  }) async {
    try {
      if (couponId.trim().isEmpty || listingId.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Invalid parameters provided',
          'error_code': 'INVALID_PARAMS'
        };
      }

      _debugPrint('Smart pinning: $couponId -> $listingId');

      final coupon = await CouponService.getCoupon(couponId);
      if (coupon == null) {
        return {
          'success': false,
          'message': 'Coupon not found',
          'error_code': 'COUPON_NOT_FOUND'
        };
      }
      if (!coupon.isUsable) {
        return {
          'success': false,
          'message': 'Coupon is not usable: ${coupon.statusDescription}',
          'error_code': 'COUPON_NOT_USABLE',
        };
      }

      if (coupon.type == CouponType.trending) {
        final ok = await checkAndConsumeQuota(
            quotaType: 'trending_pins', maxDaily: 20);
        if (!ok) {
          return {
            'success': false,
            'message':
            'Daily trending quota exhausted, please try again tomorrow',
            'error_code': 'QUOTA_EXHAUSTED',
          };
        }
      }

      final success = await CouponService.useCouponForPinning(
          couponId: couponId, listingId: listingId);

      if (success) {
        clearCache();
        return {
          'success': true,
          'message':
          'Coupon used successfully for ${coupon.type.displayLocation}',
          'coupon_type': coupon.type.value,
          'display_location': coupon.type.displayLocation,
          'function_description': coupon.type.functionDescription,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to use coupon for pinning',
          'error_code': 'PINNING_FAILED'
        };
      }
    } catch (e) {
      _debugPrint('useSmartPinning error: $e');
      return {
        'success': false,
        'message': 'Internal error occurred',
        'error_code': 'INTERNAL_ERROR',
        'error_details': e.toString(),
      };
    }
  }

  // 批量发券（管理）
  static Future<Map<String, dynamic>> batchGrantRewards({
    required List<String> userIds,
    required CouponType couponType,
    String? title,
    String? description,
    int durationDays = 7,
    String rewardReason = 'Admin batch reward',
  }) async {
    try {
      if (userIds.isEmpty) {
        return {
          'success': false,
          'message': 'No user IDs provided',
          'granted_count': 0,
          'failed_count': 0,
        };
      }

      final actualType =
      couponType.isActualCouponType ? couponType : CouponType.category;

      _debugPrint(
          'Batch granting ${actualType.value} coupons to ${userIds.length} users');

      int grantedCount = 0;
      int failedCount = 0;
      final results = <Map<String, dynamic>>[];

      for (final userId in userIds) {
        try {
          final coupon = await CouponService.createCoupon(
            userId: userId,
            type: actualType,
            title: title ?? 'Admin Reward ${actualType.displayNameEn}',
            description: description ??
                'Special reward from admin: ${actualType.functionDescription}',
            durationDays: durationDays,
            maxUses: 1,
            metadata: {
              'source': 'admin_batch_reward',
              'batch_granted_at': DateTime.now().toIso8601String(),
              'reason': rewardReason,
            },
          );

          if (coupon != null) {
            await _client.from('reward_logs').insert({
              'user_id': userId,
              'reward_type': 'admin_grant',
              'reward_reason': rewardReason,
              'coupon_id': coupon.id,
              'metadata': {
                'actual_coupon_type': actualType.value,
                'batch_granted_at': DateTime.now().toIso8601String(),
                'admin_action': true,
              },
              'created_at': DateTime.now().toIso8601String(),
            });

            grantedCount++;
            results.add({
              'user_id': userId,
              'success': true,
              'coupon_id': coupon.id,
              'coupon_code': coupon.code
            });
          } else {
            failedCount++;
            results.add({
              'user_id': userId,
              'success': false,
              'error': 'Failed to create coupon'
            });
          }
        } catch (e) {
          _debugPrint('Batch grant error for $userId: $e');
          failedCount++;
          results.add(
              {'user_id': userId, 'success': false, 'error': e.toString()});
        }
      }

      _debugPrint(
          'Batch grant completed: $grantedCount granted, $failedCount failed');
      clearCache();

      return {
        'success': grantedCount > 0,
        'message':
        'Batch reward completed: $grantedCount granted, $failedCount failed',
        'granted_count': grantedCount,
        'failed_count': failedCount,
        'total_count': userIds.length,
        'coupon_type': actualType.value,
        'results': results,
      };
    } catch (e) {
      _debugPrint('batchGrantRewards failed: $e');
      return {
        'success': false,
        'message': 'Batch operation failed: ${e.toString()}',
        'granted_count': 0,
        'failed_count': userIds.length,
        'total_count': userIds.length,
      };
    }
  }

  // 清理
  static Future<Map<String, dynamic>> cleanupExpiredData() async {
    try {
      _debugPrint('Starting expired data cleanup');

      final now = DateTime.now();
      final thirtyDaysAgo =
      now.subtract(const Duration(days: 30)).toIso8601String();

      final expiredTasksResponse = await _client
          .from('user_tasks')
          .update({'status': 'expired'})
          .eq('status', 'active')
          .lt('created_at', thirtyDaysAgo)
          .select('id');

      final expiredTasksCount = expiredTasksResponse.length;

      final cancelledReferralsResponse = await _client
          .from('referrals')
          .update({'status': 'cancelled'})
          .eq('status', 'pending')
          .lt('created_at', thirtyDaysAgo)
          .select('id');

      final cancelledReferralsCount = cancelledReferralsResponse.length;

      final sevenDaysAgo = now
          .subtract(const Duration(days: 7))
          .toIso8601String()
          .substring(0, 10);
      final deletedQuotasResponse = await _client
          .from('daily_quotas')
          .delete()
          .lt('date', sevenDaysAgo)
          .select('id');

      final deletedQuotasCount = deletedQuotasResponse.length;

      _debugPrint(
          'Cleanup: tasks=$expiredTasksCount, referrals_cancelled=$cancelledReferralsCount, quotas_deleted=$deletedQuotasCount');

      clearCache();

      return {
        'success': true,
        'message': 'Cleanup completed successfully',
        'expired_tasks': expiredTasksCount,
        'cancelled_referrals': cancelledReferralsCount,
        'deleted_quotas': deletedQuotasCount,
        'cleanup_date': now.toIso8601String(),
      };
    } catch (e) {
      _debugPrint('Cleanup failed: $e');
      return {
        'success': false,
        'message': 'Cleanup failed: ${e.toString()}',
        'expired_tasks': 0,
        'cancelled_referrals': 0,
        'deleted_quotas': 0,
      };
    }
  }

  // 系统总览
  static Future<Map<String, dynamic>> getSystemRewardOverview({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start = startDate?.toIso8601String() ??
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final end =
          endDate?.toIso8601String() ?? DateTime.now().toIso8601String();

      _debugPrint('Overview period: $start → $end');

      final futures = await Future.wait([
        _client
            .from('reward_logs')
            .select('*')
            .gte('created_at', start)
            .lte('created_at', end),
        _client
            .from('user_tasks')
            .select('*')
            .gte('created_at', start)
            .lte('created_at', end),
        _client
            .from('referrals')
            .select('*')
            .gte('created_at', start)
            .lte('created_at', end),
        _client
            .from('coupons')
            .select('*')
            .gte('created_at', start)
            .lte('created_at', end),
      ]);

      final rewardsData = futures[0] as List;
      final tasksData = futures[1] as List;
      final referralsData = futures[2] as List;
      final couponsData = futures[3] as List;

      Map<String, int> countByField(List<dynamic> items, String field) {
        final counts = <String, int>{};
        for (final item in items) {
          try {
            final data = Map<String, dynamic>.from(item);
            final value = data[field]?.toString() ?? 'unknown';
            counts[value] = (counts[value] ?? 0) + 1;
          } catch (_) {}
        }
        return counts;
      }

      return {
        'success': true,
        'period': {'start_date': start, 'end_date': end},
        'rewards': {
          'total': rewardsData.length,
          'by_type': countByField(rewardsData, 'reward_type')
        },
        'tasks': {
          'total': tasksData.length,
          'by_status': countByField(tasksData, 'status'),
          'by_type': countByField(tasksData, 'task_type'),
        },
        'invitations': {
          'total': referralsData.length,
          'by_status': countByField(referralsData, 'status')
        },
        'coupons': {
          'total': couponsData.length,
          'by_type': countByField(couponsData, 'type'),
          'by_status': countByField(couponsData, 'status'),
        },
      };
    } catch (e) {
      _debugPrint('getSystemRewardOverview failed: $e');
      return {
        'success': false,
        'message': 'Failed to get overview: ${e.toString()}',
        'rewards': {'total': 0, 'by_type': {}},
        'tasks': {'total': 0, 'by_status': {}, 'by_type': {}},
        'invitations': {'total': 0, 'by_status': {}},
        'coupons': {'total': 0, 'by_type': {}, 'by_status': {}},
      };
    }
  }

  static Future<bool> healthCheck() async {
    try {
      final futures = await Future.wait([
        _client.from('reward_logs').select('id').limit(1),
        _client.from('user_tasks').select('id').limit(1),
        _client.from('referrals').select('id').limit(1),
        _client.from('daily_quotas').select('id').limit(1),
      ]);
      return futures.every((r) => r != null);
    } catch (e) {
      _debugPrint('Health check failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getRewardStats(String userId) =>
      getUserRewardStats(userId);

  static Future<List<Map<String, dynamic>>> getRewardHistory({
    required String userId,
    int? limit,
  }) async {
    if (limit != null) {
      try {
        final response = await _client
            .from('reward_logs')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);
        final List<dynamic> list = response;
        return list.cast<Map<String, dynamic>>();
      } catch (e) {
        _debugPrint('getRewardHistory(limit) error: $e');
        return [];
      }
    }
    return getUserRewardHistory(userId);
  }

  static Future<List<Map<String, dynamic>>> getActiveTasks(
      String userId) async {
    final key = 'active_tasks:$userId';
    final now = DateTime.now();

    final cached = _cache[key];
    if (cached != null && now.difference(cached.ts) < _ttl) {
      return cached.data as List<Map<String, dynamic>>;
    }

    try {
      if (userId.trim().isEmpty) return [];

      final response = await _client
          .from('user_tasks')
          .select('*')
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final List<dynamic> list = response;
      final result = list.cast<Map<String, dynamic>>();

      _cache[key] = _CacheEntry(now, result);
      return result;
    } on PostgrestException catch (e) {
      if (_is401Error(e)) {
        _cache[key] = _CacheEntry(now, []);
        return [];
      }
      rethrow;
    } catch (e) {
      _debugPrint('getActiveTasks error: $e');
      _cache[key] = _CacheEntry(now, []);
      return [];
    }
  }
}

class _CacheEntry {
  final DateTime ts;
  final dynamic data;
  _CacheEntry(this.ts, this.data);
}
