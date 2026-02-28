// lib/services/coupon_service.dart - 修正版（移除 pin_type 依赖 + 修复 Dart 语法 + 统一 RPC + 30s 缓存 + 完整日志 + 修复响应字段检查）
// 变更要点：
// 1) ❗修复 Dart 语法：把 `is not Map` 全改为 `is! Map`，消除 "The name 'not' isn't defined" 报错。
// 2) ❗前端不再读取表里不存在的字段 `pin_type`，所有逻辑只依据 `type` 与 `pin_scope`。
// 3) 统一调用后端 RPC：featured/search 走 `redeem_search_popular_coupon`；其他置顶走 `use_coupon_for_pinning`。
// 4) getTrendingPinnedAds 等 clamp 返回值强转为 int，避免 `num` 传给 `.limit()` 的类型告警。
// 5) 提供 30s TTL 的内存缓存与并发去重；提供 clearCache()。
// 6) ✅ getTrendingPinnedAds 为"随机洗牌"逻辑，并增加 DB 端上限以避免全表扫描。
// 7) ✅ getTrendingQuotaStatus 改为 DB 精确计数；healthCheck 更严谨。
// 8) ✅ useCouponForPinning 添加完整的响应日志和错误处理
// 9) ✅ 修复响应字段检查：同时兼容 'ok' 和 'success' 字段
// 10) ✅【本次修复】兼容 RPC 返回 bool=true：redeem_search_popular_coupon 返回 true 时也算成功（修复你日志里的“RPC true 但失败”）

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/services/edge_functions_client.dart';
import 'dart:math';

// 开关：是否打印缓存命中/完成日志（默认 false 关闭）
const bool _kLogCacheHit = false;

class CouponService {
  static final CouponService instance = CouponService._();
  CouponService._();

  static final SupabaseClient _client = Supabase.instance.client;

  // ===== 30s TTL 缓存 + 并发去重 =====
  static const _ttl = Duration(seconds: 30);

  // 券列表缓存（按 userId|status|type 维度）
  static final Map<String, _CacheEntry<List<CouponModel>>> _couponCache = {};
  static final Map<String, Future<List<CouponModel>>> _couponInflight = {};

  // 首页"热门置顶"缓存（按 city|limit 维度）
  static final Map<String, _CacheEntry<List<Map<String, dynamic>>>>
      _trendingCache = {};
  static final Map<String, Future<List<Map<String, dynamic>>>>
      _trendingInflight = {};

  // ✅ 并发锁：防止同一张券被连点使用
  static final Set<String> _pinInflightKeys = {};
  static String _pinKey(String c, String l) => '$c|$l';

  /// 清理缓存（同时清理券与置顶广告两个缓存与并发占位）
  static void clearCache() {
    _couponCache.clear();
    _couponInflight.clear();
    _trendingCache.clear();
    _trendingInflight.clear();
    // ✅ 确保不会因为异常而留下"永远上锁"的 key
    _pinInflightKeys.clear();
  }

  /// 仅清理某用户的券缓存
  static void clearUserCouponCache(String userId) {
    _couponCache.removeWhere((k, _) => k.startsWith('$userId|'));
    _couponInflight.removeWhere((k, _) => k.startsWith('$userId|'));
  }

  /// Debug print
  static void _debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[CouponService] $message');
    }
  }

  /// ✅ P1: 查询重试函数（最大2次，退避延迟）
  static Future<dynamic?> _fetchListingWithRetry(String listingId, {int maxRetries = 2}) async {
    if (listingId.isEmpty) return null;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _client.from('listings')
            .select('id, title, price, city, category, images, image_urls, created_at, description, name, phone')
            .eq('id', listingId)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));
        
        if (result != null) {
          _debugPrint('重试成功: listing $listingId (尝试 $attempt)');
          return result;
        }
      } catch (e) {
        _debugPrint('重试失败: listing $listingId (尝试 $attempt): $e');
      }
      
      // 退避延迟：300ms, 800ms
      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: attempt == 1 ? 300 : 800));
      }
    }
    
    return null;
  }

  /// ✅【关键】统一判断 RPC 是否成功：兼容 null / bool / Map(ok|success) / String(true)
  static bool _rpcOk(dynamic res) {
    if (res == null) return false; // ❌ null 不再视为成功
    if (res is bool) return res == true;
    if (res is String) {
      final s = res.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    if (res is Map) {
      return res['ok'] == true || res['success'] == true;
    }
    return false;
  }

  /// ✅ 从 RPC 返回里提取错误信息（用于日志/Exception）
  static String _rpcMsg(dynamic res, {String fallback = 'RPC failed'}) {
    if (res is Map) {
      return (res['message'] ?? res['error'] ?? fallback).toString();
    }
    if (res is String && res.trim().isNotEmpty) return res;
    if (res is bool) return res ? 'OK' : fallback;
    return fallback;
  }

  /// Generate coupon code
  static String _generateCouponCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(10, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Safe parsing method
  static CouponModel? _safeParseCoupon(dynamic data) {
    try {
      if (data == null) return null;
      return CouponModel.fromMap(Map<String, dynamic>.from(data));
    } catch (e) {
      _debugPrint('Error parsing coupon: $e');
      return null;
    }
  }

  /// Safe string conversion
  static String _safeString(dynamic value, [String defaultValue = '']) {
    if (value == null) return defaultValue;
    return value.toString();
  }

  // ========== ★ 核心映射 ==========

  /// 根据优惠券类型获取正确的 category 和 source（确保 welcome 被计入奖励）
  static (String category, String source) _categoryAndSourceForType(
      CouponType type) {
    switch (type) {
      case CouponType.welcome:
        return ('reward', 'signup'); // 关键：欢迎券算奖励，来源为注册
      case CouponType.registerBonus:
      case CouponType.activityBonus:
      case CouponType.referralBonus:
        return ('reward', 'task'); // 其他奖励券
      case CouponType.trending:
        return ('pinning', 'purchase'); // 热门置顶券
      case CouponType.category:
        return ('pinning', 'purchase'); // 分类置顶券
      case CouponType.boost:
        return ('boost', 'purchase'); // 搜索/曝光提升
      default:
        return ('pinning', 'legacy');
    }
  }

  /// 获取 pinned_ads 的 pinning_type（显式支持 welcome / 别名）
  static String _getPinningTypeFromCouponType(String couponType) {
    switch (couponType) {
      case 'trending':
      case 'trending_pin': // 兼容别名
        return 'trending';
      case 'category':
      case 'pinned':
      case 'featured':
      case 'premium':
      case 'register_bonus':
      case 'activity_bonus':
      case 'referral_bonus':
      case 'welcome':
        return 'category';
      case 'boost':
        return 'boost'; // 非置顶型（不占 pinned_ads 位置）
      default:
        return 'category';
    }
  }

  // ========== ★ 新增：createWelcomeCoupon 方法 ==========

  /// 创建欢迎券（pin_scope=category，pin_days=3）
  static Future<Map<String, dynamic>> createWelcomeCoupon(String userId) async {
    try {
      _debugPrint('Creating welcome coupon for user: $userId');

      final code = 'WELCOME-${userId.substring(0, 6).toUpperCase()}';
      final now = DateTime.now();
      final expiresAt =
          now.add(const Duration(days: 30)); // 券有效期（与RewardService一致）

      final couponData = {
        'user_id': userId,
        'type': 'welcome',
        'source': 'welcome',
        'status': 'active',
        'title': 'Welcome Coupon',
        'code': code,
        'pin_scope': 'category',
        'pin_days': 3,
        'max_uses': 1,
        'used_count': 0,
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

      // upsert 确保同一用户仅一张 welcome 券
      final row = await _client
          .from('coupons')
          .upsert(couponData, onConflict: 'user_id,type')
          .select('id, code')
          .maybeSingle();

      _debugPrint('Welcome coupon created successfully: $code');
      return {
        'ok': true,
        'id': row?['id'],
        'code': row?['code'] ?? code,
        'message': 'Welcome coupon created successfully',
      };
    } catch (e) {
      _debugPrint('Failed to create welcome coupon: $e');
      return {
        'ok': false,
        'error': e.toString(),
        'message': 'Failed to create welcome coupon',
      };
    }
  }

  // ========== ★ 新增：Search/Popular Pin 发券（featured/search） ==========

  /// 达到 5 人里程碑：只发一张 Search/Popular Pin(3d)
  /// 注意：此券不会直接创建 pinned_ads；只有在"用券"时通过 RPC 同步完成【搜索置顶 + Popular 注入】
  static Future<CouponModel?> createSearchPopularCoupon({
    required String userId,
    int durationDays = 3,
    String title = 'Referral Reward · Search/Popular Pin (3d)',
    String description = 'Invite 5 friends completed — search pin for 3 days.',
  }) async {
    try {
      _debugPrint(
          'Creating Search/Popular coupon (featured/search) for $userId');

      final code = _generateCouponCode();
      final now = DateTime.now();
      final expiresAt = now.add(Duration(days: durationDays));

      final data = {
        'code': code,
        'user_id': userId,
        'type': 'featured', // 关键：type=featured
        'pin_scope': 'search', // 这里只写 pin_scope
        'status': 'active',
        'category': 'pinning',
        'source': 'referral_reward',
        'title': title,
        'description': description,
        'pin_days': durationDays, // ✅ 与表字段一致
        'max_uses': 1,
        'used_count': 0,
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'metadata': {
          'source': 'referral_reward',
          'milestone': 5,
          'kind': 'search_popular',
        },
      };

      final response =
          await _client.from('coupons').insert(data).select().single();
      return _safeParseCoupon(response);
    } catch (e) {
      _debugPrint('Failed to create search/popular coupon: $e');
      return null;
    }
  }

  // ========== ★ 修改：邀请奖励发券（供 RewardService 调用） ==========

  /// 发放邀请奖励（5 人里程碑）：只发 1 × Search/Popular Pin (3d)
  static Future<void> issueInviteReward(String inviterId) async {
    try {
      if (inviterId.isEmpty) return;
      _debugPrint('Issuing milestone(5) reward to: $inviterId');
      await createSearchPopularCoupon(userId: inviterId, durationDays: 3);
      _debugPrint('Invite reward issued: Search/Popular Pin (3d).');
    } catch (e) {
      _debugPrint('issueInviteReward failed: $e');
    }
  }

  // ========== ★ 新增：getPinningEligibleCoupons 方法 ==========

  /// 获取可用于置顶的券（放宽查询，仅在内存中过滤 canPin & isUsable）
  static Future<List<CouponModel>> getPinningEligibleCoupons(
      String userId) async {
    try {
      _debugPrint('Getting pinning eligible coupons for user: $userId');

      final response = await _client
          .from('coupons')
          .select('*')
          .eq('user_id', userId)
          .eq('status', 'active')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      final responseList = response;
      final coupons = <CouponModel>[];

      for (final data in responseList) {
        final coupon = _safeParseCoupon(data);
        if (coupon != null && coupon.isUsable) {
          // 大多数券依赖 canPin；额外宽容 featured/search
          final raw = Map<String, dynamic>.from(data);
          final pinScope = _safeString(raw['pin_scope']).toLowerCase();
          final rawType = _safeString(raw['type']).toLowerCase();
          final isSearchPopular = rawType == 'featured' && pinScope == 'search';

          if (coupon.canPin || isSearchPopular) {
            coupons.add(coupon);
          }
        }
      }

      _debugPrint('Found ${coupons.length} pinning eligible coupons');
      return coupons;
    } catch (e) {
      _debugPrint('Failed to get pinning eligible coupons: $e');
      return [];
    }
  }

  // ========== ★ 统一：RPC 封装 ==========

  /// 使用 featured/search 券：调用后端 RPC，一次完成【搜索置顶 + Popular 注入】并标记券已用
  static Future<bool> _redeemSearchPopularViaRpc({
    required String couponId,
    required String listingId,
  }) async {
    try {
      final res = await EdgeFunctionsClient.instance.rpcProxy('redeem_search_popular_coupon', params: {
        'in_coupon_id': couponId,
        'in_listing_id': listingId,
      });

      // ✅【关键修复】兼容 bool=true
      final ok = _rpcOk(res);
      return ok;
    } catch (e) {
      _debugPrint('RPC redeem_search_popular_coupon failed: $e');
      return false;
    }
  }

  /// ✅ 统一：use_coupon_for_pinning 使用 in_* 参数名；null/bool/map 视为成功；兼容 ok 和 success 字段
  static Future<bool> useCouponUnified({
    required String couponId,
    required String listingId,
    String note = 'app',
  }) async {
    final key = _pinKey(couponId, listingId);
    if (_pinInflightKeys.contains(key)) return false; // Concurrency lock
    _pinInflightKeys.add(key);

    try {
      final res = await EdgeFunctionsClient.instance.rpcProxy('use_coupon_for_pinning', params: {
        // ❗ 修正：使用 in_* 参数名，和后端函数签名一致
        'in_coupon_id': couponId,
        'in_listing_id': listingId,
        'in_note': note,
      });
      _debugPrint('use_coupon_for_pinning -> $res');

      final ok = _rpcOk(res);
      if (!ok) {
        throw Exception(_rpcMsg(res));
      }

      clearCache();
      return true;
    } catch (e) {
      _debugPrint('useCouponUnified failed: $e');
      return false;
    } finally {
      _pinInflightKeys.remove(key); // Unlock
    }
  }

  // ========== 1. Basic Coupon Operations ==========

  /// Create coupon (General method)
  static Future<CouponModel?> createCoupon({
    required String userId,
    required CouponType type,
    required String title,
    required String description,
    required int durationDays,
    int maxUses = 1,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _debugPrint('Creating coupon: $userId, $type, $title');

      final code = _generateCouponCode();
      final now = DateTime.now();
      final expiresAt = now.add(Duration(days: durationDays));

      final (category, source) = _categoryAndSourceForType(type);

      final couponData = {
        'code': code,
        'user_id': userId,
        'type': type.value,
        'status': CouponStatus.active.value,
        'category': category,
        'source': source,
        'title': title,
        'description': description,
        'pin_days': durationDays, // ✅ 与表字段一致
        'max_uses': maxUses,
        'used_count': 0,
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'metadata': metadata,
      };

      final response =
          await _client.from('coupons').insert(couponData).select().single();

      final coupon = _safeParseCoupon(response);
      if (coupon != null) {
        _debugPrint('Coupon created successfully: ${coupon.code}');
      }
      return coupon;
    } catch (e) {
      _debugPrint('Failed to create coupon: $e');
      return null;
    }
  }

  /// Get single coupon details（非缓存）
  static Future<CouponModel?> getCoupon(String couponId) async {
    try {
      _debugPrint('Getting coupon details: $couponId');

      final response = await _client
          .from('coupons')
          .select('*')
          .eq('id', couponId)
          .maybeSingle();

      if (response == null) {
        _debugPrint('Coupon not found: $couponId');
        return null;
      }

      return _safeParseCoupon(response);
    } catch (e) {
      _debugPrint('Failed to get coupon details: $e');
      return null;
    }
  }

  /// Revoke coupon（非缓存）
  static Future<bool> revokeCoupon(String couponId) async {
    try {
      _debugPrint('Revoking coupon: $couponId');

      await _client.from('coupons').update({
        'status': CouponStatus.revoked.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', couponId);

      _debugPrint('Coupon revoked successfully: $couponId');
      return true;
    } catch (e) {
      _debugPrint('Failed to revoke coupon: $e');
      return false;
    }
  }

  // ========== 2. 配额检查方法 ==========

  /// 检查 trending 置顶配额状态（最多 20）
  static Future<Map<String, dynamic>> getTrendingQuotaStatus(
      {String? city}) async {
    try {
      _debugPrint('检查 trending 置顶配额状态: city=$city');

      final nowIso = DateTime.now().toIso8601String();
      final rows = await _client
          .from('pinned_ads')
          .select('id')
          .eq('status', 'active')
          .eq('pinning_type', 'trending')
          .gt('expires_at', nowIso);

      final usedCount = (rows as List).length;
      // v1.0.1: 移除容量限制，允许无限写入
      const maxTrendingSlots = 10000; // 象征性的大数字，表示无限

      return {
        'used_count': usedCount,
        'max_count': maxTrendingSlots,
        'available': true, // 总是可用
        'remaining': 10000, // 象征性的大数字
        'success': true,
      };
    } catch (e) {
      _debugPrint('获取 trending 配额状态失败: $e');
      return {
        'used_count': 0,
        'max_count': 10000,
        'available': true,
        'remaining': 10000,
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ====================== 拉券（缓存 30s + 并发去重）======================

  static String _couponKey({
    required String userId,
    CouponStatus? status,
    CouponType? type,
    int? limit,
  }) =>
      '$userId|${status?.name}|${type?.name}|${limit ?? -1}';

  /// Get user's coupon list - 30s 缓存 + 并发去重版本
  static Future<List<CouponModel>> getUserCoupons({
    required String userId,
    CouponStatus? status,
    CouponType? type,
    int? limit,
  }) async {
    final key =
        _couponKey(userId: userId, status: status, type: type, limit: limit);

    // 命中 TTL 缓存
    final hit = _couponCache[key];
    if (hit != null && hit.valid) {
      if (kDebugMode && _kLogCacheHit) {
        debugPrint('[CouponService] cache HIT getUserCoupons key=$key');
      }
      return hit.data;
    }

    // 并发去重：已在飞中的请求，直接复用
    final running = _couponInflight[key];
    if (running != null) {
      if (kDebugMode && _kLogCacheHit) {
        debugPrint('[CouponService] join inflight getUserCoupons key=$key');
      }
      return await running;
    }

    // 真正发请求
    final future =
        _fetchCoupons(userId: userId, status: status, type: type, limit: limit);
    _couponInflight[key] = future;
    try {
      final data = await future;
      _couponCache[key] = _CacheEntry(DateTime.now(), data);
      return data;
    } finally {
      _couponInflight.remove(key);
    }
  }

  static Future<List<CouponModel>> _fetchCoupons({
    required String userId,
    CouponStatus? status,
    CouponType? type,
    int? limit,
  }) async {
    try {
      if (kDebugMode && _kLogCacheHit) {
        debugPrint(
            '[CouponService] FETCH user coupons -> user=$userId, status=$status, type=$type');
      }

      final queryBuilder =
          _client.from('coupons').select('*').eq('user_id', userId);

      if (status != null) {
        queryBuilder.eq('status', status.value);
      }
      if (type != null) {
        queryBuilder.eq('type', type.value);
      }

      queryBuilder.order('created_at', ascending: false);
      queryBuilder.limit(limit ?? 100);

      final response = await queryBuilder;
      final responseList = response;

      final coupons = <CouponModel>[];
      for (final data in responseList) {
        final coupon = _safeParseCoupon(data);
        if (coupon != null) {
          // 保险起见：过滤已过期的 active
          final isNotExpired = !coupon.isExpired;
          final isActive = coupon.status == CouponStatus.active;
          if (status == CouponStatus.active) {
            if (isActive && isNotExpired) coupons.add(coupon);
          } else {
            coupons.add(coupon);
          }
        }
      }

      if (kDebugMode && _kLogCacheHit) {
        debugPrint('[CouponService] FETCH done -> ${coupons.length} items');
      }
      return coupons;
    } catch (e) {
      _debugPrint('Failed to get user coupons: $e');
      return [];
    }
  }

  // ========== 3. 使用优惠券置顶（统一：featured/search → redeem RPC；其余 → use_coupon_for_pinning RPC） ==========

  /// 使用券置顶广告（统一走 RPC；featured/search 走 redeem_*，其余走 use_coupon_for_pinning）
  static Future<void> useCouponToPinListing({
    required String couponId,
    required String listingId,
    required String userId,
  }) async {
    final key = _pinKey(couponId, listingId);
    if (_pinInflightKeys.contains(key)) return; // Concurrency lock
    _pinInflightKeys.add(key);

    try {
      _debugPrint(
          'Using coupon to pin listing (unified RPC): $couponId -> $listingId');

      // 读原始券，做基本校验
      final couponData = await _client
          .from('coupons')
          .select('*')
          .eq('id', couponId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (couponData == null) throw Exception('Coupon not found or not usable');

      // 过期校验
      final expStr = _safeString(couponData['expires_at']);
      if (expStr.isNotEmpty) {
        final exp = DateTime.tryParse(expStr);
        if (exp != null && DateTime.now().isAfter(exp)) {
          throw Exception('Coupon has expired');
        }
      }

      final typeStr = _safeString(couponData['type']).toLowerCase();
      final pinScopeStr = _safeString(couponData['pin_scope']).toLowerCase();
      final isSearchPopular = typeStr == 'featured' && pinScopeStr == 'search';

      bool ok = false;
      if (isSearchPopular) {
        final res = await EdgeFunctionsClient.instance.rpcProxy('redeem_search_popular_coupon', params: {
          'in_coupon_id': couponId,
          'in_listing_id': listingId,
        });
        ok = _rpcOk(res);
        _debugPrint('redeem_search_popular_coupon => $res');
      } else {
        final res = await EdgeFunctionsClient.instance.rpcProxy('use_coupon_for_pinning', params: {
          'in_coupon_id': couponId,
          'in_listing_id': listingId,
          'in_note': 'app',
        });
        ok = _rpcOk(res);
        _debugPrint('use_coupon_for_pinning => $res');
      }

      if (!ok) throw Exception('RPC redeem/use failed');

      clearCache();
      _debugPrint('Coupon used via RPC successfully.');
      return;
    } catch (e) {
      _debugPrint('useCouponToPinListing failed: $e');
      rethrow; // 不再走旧的前端插表兜底，避免"无限使用"
    } finally {
      _pinInflightKeys.remove(key); // Unlock
    }
  }

  /// ✅ 兼容旧入口：内部同样统一走 RPC；成功返回 true（增强版日志 + 修复响应字段检查）
  static Future<bool> useCouponForPinning({
    required String couponId,
    required String listingId,
  }) async {
    try {
      _debugPrint(
          '🎫 Using coupon for pinning (legacy wrapper -> unified RPC)');
      _debugPrint('   Coupon ID: $couponId');
      _debugPrint('   Listing ID: $listingId');

      // 1️⃣ 获取券信息
      _debugPrint('📋 Step 1: Fetching coupon data...');
      final couponData = await _client
          .from('coupons')
          .select('*')
          .eq('id', couponId)
          .maybeSingle();

      if (couponData == null) {
        _debugPrint('❌ Coupon not found: $couponId');
        return false;
      }

      // 2️⃣ 检查券状态
      _debugPrint('📋 Step 2: Validating coupon status...');
      final status = _safeString(couponData['status']).toLowerCase();
      if (status != 'active') {
        _debugPrint('❌ Coupon not active: status=$status');
        return false;
      }

      // 3️⃣ 检查过期时间
      _debugPrint('📋 Step 3: Checking expiration...');
      final expStr = _safeString(couponData['expires_at']);
      if (expStr.isNotEmpty) {
        final exp = DateTime.tryParse(expStr);
        if (exp != null && DateTime.now().isAfter(exp)) {
          _debugPrint('❌ Coupon expired: $expStr');
          return false;
        }
        _debugPrint('✅ Coupon valid until: $expStr');
      }

      // 4️⃣ 确定券类型
      final typeStr = _safeString(couponData['type']).toLowerCase();
      final pinScopeStr = _safeString(couponData['pin_scope']).toLowerCase();
      final isSearchPopular = typeStr == 'featured' && pinScopeStr == 'search';

      _debugPrint('📊 Coupon details:');
      _debugPrint('   Type: $typeStr');
      _debugPrint('   Pin Scope: $pinScopeStr');
      _debugPrint('   Is Search/Popular: $isSearchPopular');

      // 5️⃣ 调用相应的 RPC
      if (isSearchPopular) {
        _debugPrint('🚀 Step 4: Calling redeem_search_popular_coupon RPC...');

        final res = await EdgeFunctionsClient.instance.rpcProxy('redeem_search_popular_coupon', params: {
          'in_coupon_id': couponId,
          'in_listing_id': listingId,
        });

        _debugPrint('📥 RPC Response: $res');
        _debugPrint('📥 Response type: ${res.runtimeType}');

        // ✅【关键修复】bool true 也算成功
        final ok = _rpcOk(res);

        if (ok) {
          _debugPrint('✅ Search/Popular pinning successful!');
          clearCache();
          return true;
        } else {
          final msg = _rpcMsg(res);
          _debugPrint('❌ Search/Popular pinning failed: $msg');
          return false;
        }
      } else {
        _debugPrint('🚀 Step 4: Calling use_coupon_for_pinning RPC...');

        final res = await EdgeFunctionsClient.instance.rpcProxy('use_coupon_for_pinning', params: {
          'in_coupon_id': couponId,
          'in_listing_id': listingId,
          'in_note': 'app',
        });

        _debugPrint('📥 RPC Response: $res');
        _debugPrint('📥 Response type: ${res.runtimeType}');

        final ok = _rpcOk(res);

        if (ok) {
          _debugPrint('✅ Pinning successful!');
          clearCache();
          return true;
        } else {
          final msg = _rpcMsg(res);
          _debugPrint('❌ Pinning failed: $msg');
          return false;
        }
      }
    } catch (e, stack) {
      _debugPrint('❌ Exception in useCouponForPinning: $e');
      _debugPrint('Stack trace: $stack');
      return false;
    }
  }

  // ========== 4. 置顶查询（首页热门置顶 30s 缓存 + 并发去重） ==========

  static String _trendingKey({String? city, required int limit}) =>
      '${city ?? ''}|$limit';

  /// 获取首页热门置顶广告（仅 trending；最多 20）—— 带 30s 缓存
  /// ✅ "随机洗牌"逻辑 + DB 上限（避免全表扫描）
  static Future<List<Map<String, dynamic>>> getTrendingPinnedAds(
      {String? city, int limit = 20}) async {
    // 规范 limit
    final int effectiveLimit = limit.clamp(1, 20).toInt();

    // 缓存 key
    final key = _trendingKey(city: city, limit: effectiveLimit);

    // 命中缓存
    final hit = _trendingCache[key];
    if (hit != null && hit.valid) {
      if (kDebugMode && _kLogCacheHit) {
        debugPrint('[CouponService] cache HIT getTrendingPinnedAds key=$key');
      }
      return hit.data;
    }

    // 并发去重
    final running = _trendingInflight[key];
    if (running != null) {
      if (kDebugMode && _kLogCacheHit) {
        debugPrint(
            '[CouponService] join inflight getTrendingPinnedAds key=$key');
      }
      return await running;
    }

    if (kDebugMode && _kLogCacheHit) {
      _debugPrint(
          '[CouponService] 获取首页热门置顶广告: city=$city, limit=$effectiveLimit');
    }

    final future = () async {
      try {
        // v1.0.1: 使用优化后的 RPC 函数 get_random_trending_ads（已包含JOIN数据）
        _debugPrint('调用优化版 RPC get_random_trending_ads，limit=$effectiveLimit');
        
        // 通过优化后的RPC获取随机置顶广告（已包含关联的listings和coupons数据）
        // ✅ 弱网重试逻辑：遇到网络异常自动重试1次
        List<dynamic> ads = [];
        bool rpcSuccess = false;
        String lastError = '';
        
        for (int attempt = 1; attempt <= 2; attempt++) {
          try {
            _debugPrint('RPC调用尝试 $attempt/2: get_random_trending_ads, limit=$effectiveLimit');
            ads = await _client.rpc('get_random_trending_ads', params: {
              'limit_count': effectiveLimit,
            }) as List<dynamic>;
            rpcSuccess = true;
            _debugPrint('RPC调用成功，返回 ${ads.length} 条置顶广告记录');
            break;
          } catch (e) {
            lastError = e.toString();
            _debugPrint('RPC调用失败 (尝试 $attempt/2): $e');
            
            // 仅对网络相关异常重试
            final errorStr = e.toString();
            final isNetworkError = errorStr.contains('SocketException') ||
                                  errorStr.contains('TimeoutException') ||
                                  errorStr.contains('HandshakeException') ||
                                  errorStr.contains('Connection') ||
                                  errorStr.contains('network');
            
            if (attempt < 2 && isNetworkError) {
              _debugPrint('网络异常，等待500ms后重试...');
              await Future.delayed(const Duration(milliseconds: 500));
              continue;
            } else {
              _debugPrint('不再重试: ${isNetworkError ? '已达最大重试次数' : '非网络异常'}');
              break;
            }
          }
        }
        
        if (!rpcSuccess) {
          _debugPrint('RPC调用完全失败: $lastError');
          return <Map<String, dynamic>>[];
        }
        
        _debugPrint('优化版RPC 返回 ${ads.length} 条置顶广告记录（已包含完整关联数据）');
        
        final enrichedAds = <Map<String, dynamic>>[];
        for (final ad in ads) {
          final adMap = Map<String, dynamic>.from(ad);
          
          // ✅ 直接从RPC返回的扁平字段构建listing对象
          final listingTitle = adMap['listing_title']?.toString();
          final listingId = adMap['listing_id']?.toString();
          final couponId = adMap['coupon_id']?.toString();
          
          // 城市过滤：使用RPC返回的city字段（来自pinned_ads表）
          if (city != null && city.isNotEmpty) {
            final adCity = adMap['city']?.toString();
            if (adCity == null || adCity != city) continue;
          }
          
          // 构建listing对象（使用RPC返回的扁平字段）
          final Map<String, dynamic> listing = {
            'id': listingId,
            'title': listingTitle ?? 'Product',
            'price': adMap['listing_price'] ?? 0,
            'city': adMap['city'] ?? 'Unknown', // 使用pinned_ads的city
            'category': adMap['category'] ?? 'general',
            // 处理images字段：RPC返回的是listing_images数组
            'images': adMap['listing_images'] ?? [],
            'image_urls': adMap['listing_images'] ?? [], // 兼容性
            'description': adMap['listing_description'] ?? '',
            'phone': adMap['listing_phone'] ?? '',
            'name': adMap['listing_name'] ?? '',
            // 标记数据来源（用于调试）
            'from_optimized_rpc': true,
          };
          
          // 构建coupon对象（如果存在）
          final Map<String, dynamic>? coupon = couponId != null ? {
            'id': couponId,
            'code': adMap['coupon_code']?.toString() ?? '',
            'type': adMap['coupon_type']?.toString() ?? '',
            'title': adMap['coupon_title']?.toString() ?? '',
          } : null;
          
          // 构建最终返回结构（保持与前端兼容）
          final enrichedAd = Map<String, dynamic>.from(adMap);
          enrichedAd['listings'] = listing;
          if (coupon != null) enrichedAd['coupons'] = coupon;
          
          enrichedAds.add(enrichedAd);
        }
        
        if (kDebugMode && _kLogCacheHit) {
          debugPrint(
              '[CouponService] 成功获取 ${enrichedAds.length} 个首页热门置顶广告（优化版RPC，零N+1查询）');
        }
        return enrichedAds;
      } catch (e) {
        _debugPrint('获取首页热门置顶广告失败: $e');
        return <Map<String, dynamic>>[];
      }
    }();

    _trendingInflight[key] = future;
    try {
      final data = await future;
      _trendingCache[key] = _CacheEntry(DateTime.now(), data);
      return data;
    } finally {
      _trendingInflight.remove(key);
    }
  }

  /// 【兼容外部调用】getHomeTrendingPinnedAds = getTrendingPinnedAds（同样 30s 缓存）
  static Future<List<Map<String, dynamic>>> getHomeTrendingPinnedAds(
      {String? city, int limit = 20}) {
    return getTrendingPinnedAds(city: city, limit: limit);
  }

  /// 获取分类页面置顶广告（仅 category）（非缓存）
  static Future<List<Map<String, dynamic>>> getCategoryPinnedAds({
    required String category,
    String? city,
    int? limit = 20, // v1.0.1: 默认改为20，实现无限池轮播
  }) async {
    try {
      _debugPrint('获取分类置顶广告: category=$category, city=$city, limit=$limit');

      // v1.0.1: 使用 RPC 函数 get_random_category_ads 实现真正的数据库随机
      final effectiveLimit = limit ?? 20;
      _debugPrint('调用 RPC get_random_category_ads，category=$category, limit=$effectiveLimit');
      
      // 1. 通过 RPC 获取随机 pinned_ads 记录
      // ✅ 弱网重试逻辑：遇到网络异常自动重试1次
      List<dynamic> ads = [];
      bool rpcSuccess = false;
      String lastError = '';
      
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          _debugPrint('RPC调用尝试 $attempt/2: get_random_category_ads, category=$category, limit=$effectiveLimit');
          ads = await _client.rpc('get_random_category_ads', params: {
            'target_category': category,
            'limit_count': effectiveLimit,
          }) as List<dynamic>;
          rpcSuccess = true;
          _debugPrint('RPC调用成功，返回 ${ads.length} 条分类 $category 的置顶广告记录');
          break;
        } catch (e) {
          lastError = e.toString();
          _debugPrint('RPC调用失败 (尝试 $attempt/2): $e');
          
          // 仅对网络相关异常重试
          final errorStr = e.toString();
          final isNetworkError = errorStr.contains('SocketException') ||
                                errorStr.contains('TimeoutException') ||
                                errorStr.contains('HandshakeException') ||
                                errorStr.contains('Connection') ||
                                errorStr.contains('network');
          
          if (attempt < 2 && isNetworkError) {
            _debugPrint('网络异常，等待500ms后重试...');
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          } else {
            _debugPrint('不再重试: ${isNetworkError ? '已达最大重试次数' : '非网络异常'}');
            break;
          }
        }
      }
      
      if (!rpcSuccess) {
        _debugPrint('RPC调用完全失败: $lastError');
        return [];
      }
      
      _debugPrint('RPC 返回 ${ads.length} 条分类 $category 的 pinned_ads 记录');
      
      // 2. 使用优化版RPC返回的扁平数据（已包含关联的listings和coupons）
      final enrichedAds = <Map<String, dynamic>>[];
      for (final ad in ads) {
        final adMap = Map<String, dynamic>.from(ad);
        final listingId = adMap['listing_id']?.toString();
        final couponId = adMap['coupon_id']?.toString();
        
        // ✅ 直接从RPC返回的扁平字段构建listing对象
        final listingTitle = adMap['listing_title']?.toString();
        
        // 城市过滤：使用RPC返回的city字段
        if (city != null && city.isNotEmpty) {
          final adCity = adMap['city']?.toString();
          if (adCity == null || adCity != city) continue;
        }
        
        // 构建listing对象（使用RPC返回的扁平字段）
        final Map<String, dynamic> listing = {
          'id': listingId,
          'title': listingTitle ?? 'Product',
          'price': adMap['listing_price'] ?? 0,
          'city': adMap['city'] ?? 'Unknown',
          'category': adMap['category'] ?? category,
          // 处理images字段：RPC返回的是listing_images数组
          'images': adMap['listing_images'] ?? [],
          'image_urls': adMap['listing_images'] ?? [], // 兼容性
          'description': adMap['listing_description'] ?? '',
          'phone': adMap['listing_phone'] ?? '',
          'name': adMap['listing_name'] ?? '',
          // 标记数据来源（用于调试）
          'from_optimized_rpc': true,
        };
        
        // 构建coupon对象（如果存在）
        final Map<String, dynamic>? coupon = couponId != null ? {
          'id': couponId,
          'code': adMap['coupon_code']?.toString() ?? '',
          'type': adMap['coupon_type']?.toString() ?? '',
          'title': adMap['coupon_title']?.toString() ?? '',
        } : null;
        
        // 构建最终返回结构（保持与前端兼容）
        final enrichedAd = Map<String, dynamic>.from(adMap);
        enrichedAd['listings'] = listing;
        if (coupon != null) enrichedAd['coupons'] = coupon;
        
        enrichedAds.add(enrichedAd);
      }
      
      _debugPrint('成功获取 ${enrichedAds.length} 个分类 $category 的置顶广告（优化版RPC，零N+1查询）');
      return enrichedAds;
    } catch (e) {
      _debugPrint('获取分类置顶广告失败: $e');
      return [];
    }
  }

  /// 通用查询（兼容旧代码）
  @Deprecated('请使用 getTrendingPinnedAds 或 getCategoryPinnedAds')
  static Future<List<Map<String, dynamic>>> getPinnedAds({
    String? category,
    String? city,
    int? limit,
  }) async {
    if (category != null && category.isNotEmpty) {
      return getCategoryPinnedAds(category: category, city: city, limit: limit);
    }
    return getTrendingPinnedAds(
        city: city, limit: (limit ?? 20).clamp(1, 20).toInt());
  }

  // ========== 5. 其它辅助 ==========

  /// Check pinning eligibility
  static Future<Map<String, dynamic>> checkPinningEligibility({
    required String listingId,
    required String couponType,
  }) async {
    try {
      _debugPrint('Checking pinning eligibility: $listingId, $couponType');

      final existingPin = await _client
          .from('pinned_ads')
          .select('*')
          .eq('listing_id', listingId)
          .eq('status', 'active')
          .maybeSingle();

      if (existingPin != null) {
        return {
          'eligible': false,
          'reason': 'Item is already pinned',
          'existing_pinning_type': existingPin['pinning_type'],
        };
      }

      final pinningType = _getPinningTypeFromCouponType(couponType);

      // v1.0.1: 移除容量限制，允许无限写入
      // trending 和 category 都不再检查配额
      // if (pinningType == 'trending') { ... }
      // if (pinningType == 'category') { ... }

      if (pinningType == 'boost') {
        return {
          'eligible': false,
          'reason': 'Boost coupon cannot create a pin',
        };
      }

      return {
        'eligible': true,
        'pinning_type': pinningType,
      };
    } catch (e) {
      _debugPrint('Failed to check pinning eligibility: $e');
      return {
        'eligible': false,
        'reason': 'Error checking eligibility: $e',
      };
    }
  }

  /// Create pinned coupons (legacy admin helper)
  static Future<List<CouponModel>> createPinnedCoupons({
    required List<String> userIds,
    required int durationDays,
  }) async {
    try {
      _debugPrint('Creating pinned coupons for ${userIds.length} users');

      final results = <CouponModel>[];

      for (final userId in userIds) {
        try {
          final coupon = await createCoupon(
            userId: userId,
            type: CouponType.category,
            title: 'Admin Category Pin Coupon',
            description: 'Special category pinning coupon from admin',
            durationDays: durationDays,
            metadata: {
              'source': 'admin_grant',
              'batch_created': true,
              'granted_at': DateTime.now().toIso8601String(),
            },
          );

          if (coupon != null) results.add(coupon);
        } catch (e) {
          _debugPrint('Failed to create coupon for user $userId: $e');
          continue;
        }
      }

      _debugPrint('Created ${results.length} pinned coupons');
      return results;
    } catch (e) {
      _debugPrint('Failed to create pinned coupons: $e');
      return [];
    }
  }

  /// Clean up expired coupons
  static Future<int> cleanupExpiredCoupons() async {
    try {
      _debugPrint('Starting expired coupon cleanup');

      final now = DateTime.now().toIso8601String();
      final expiredCoupons = await _client
          .from('coupons')
          .update({'status': 'expired'})
          .lt('expires_at', now)
          .eq('status', 'active')
          .select('id');

      int expiredCount = 0;
      expiredCount = expiredCoupons.length;

      _debugPrint('Cleaned up $expiredCount expired coupons');
      return expiredCount;
    } catch (e) {
      _debugPrint('Failed to cleanup expired coupons: $e');
      return 0;
    }
  }

  /// Clean up expired pinned ads
  static Future<int> cleanupExpiredPinnedAds() async {
    try {
      _debugPrint('Starting expired pinned ads cleanup');

      final now = DateTime.now().toIso8601String();
      final expiredAds = await _client
          .from('pinned_ads')
          .update({'status': 'expired'})
          .lt('expires_at', now)
          .eq('status', 'active')
          .select('id');

      int expiredCount = 0;
      expiredCount = expiredAds.length;

      _debugPrint('Cleaned up $expiredCount expired pinned ads');
      return expiredCount;
    } catch (e) {
      _debugPrint('Failed to cleanup expired pinned ads: $e');
      return 0;
    }
  }

  // ========== 8. 统计 & 查询 ==========

  /// Get coupon statistics (simple grouping)
  static Future<Map<String, dynamic>> getCouponStatistics({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      _debugPrint('Getting coupon statistics');

      final queryBuilder =
          _client.from('coupons').select('type, status, created_at');
      if (userId != null) queryBuilder.eq('user_id', userId);
      if (startDate != null) {
        queryBuilder.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        queryBuilder.lte('created_at', endDate.toIso8601String());
      }

      final response = await queryBuilder;

      List<dynamic> coupons = [];
      coupons = response;

      final typeCounts = <String, int>{};
      final statusCounts = <String, int>{};

      for (final coupon in coupons) {
        try {
          final data = Map<String, dynamic>.from(coupon);
          final type = data['type']?.toString() ?? 'unknown';
          final status = data['status']?.toString() ?? 'unknown';
          typeCounts[type] = (typeCounts[type] ?? 0) + 1;
          statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        } catch (_) {}
      }

      return {
        'total_coupons': coupons.length,
        'by_type': typeCounts,
        'by_status': statusCounts,
      };
    } catch (e) {
      _debugPrint('Failed to get coupon statistics: $e');
      return {
        'total_coupons': 0,
        'by_type': <String, int>{},
        'by_status': <String, int>{},
      };
    }
  }

  /// Get active pinned ads（非缓存）
  static Future<List<Map<String, dynamic>>> getActivePinnedAds({
    String? pinningType,
    String? userId,
  }) async {
    try {
      _debugPrint('Getting active pinned ads: type=$pinningType, user=$userId');

      final queryBuilder = _client.from('pinned_ads').select('''
            *,
            listings:listing_id (
              id,
              title,
              category
            ),
            coupons:coupon_id (
              id,
              code,
              type
            )
          ''').eq('status', 'active');

      if (pinningType != null) queryBuilder.eq('pinning_type', pinningType);
      if (userId != null) queryBuilder.eq('user_id', userId);

      queryBuilder.order('created_at', ascending: false);
      final response = await queryBuilder;

      List<dynamic> ads = [];
      ads = response;

      return ads
          .map<Map<String, dynamic>>((ad) {
            try {
              return Map<String, dynamic>.from(ad);
            } catch (e) {
              _debugPrint('Error processing pinned ad: $e');
              return <String, dynamic>{};
            }
          })
          .where((ad) => ad.isNotEmpty)
          .toList();
    } catch (e) {
      _debugPrint('Failed to get active pinned ads: $e');
      return [];
    }
  }

  /// Health check（非缓存）
  static Future<bool> healthCheck() async {
    try {
      final response = await _client.from('coupons').select('id').limit(1);
      return response is List; // ✅ 能正常返回列表即健康
    } catch (e) {
      _debugPrint('Health check failed: $e');
      return false;
    }
  }

  // ========== 9. 校验 & 辅助 ==========

  /// Validate coupon usage（非缓存）
  static Future<Map<String, dynamic>> validateCouponUsage({
    required String couponId,
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('Validating coupon usage: $couponId');

      final coupon = await getCoupon(couponId);
      if (coupon == null) {
        return {'valid': false, 'error': 'Coupon not found'};
      }

      if (coupon.userId != userId) {
        return {'valid': false, 'error': 'Coupon does not belong to user'};
      }

      if (!coupon.isUsable) {
        return {
          'valid': false,
          'error': 'Coupon is not usable: ${coupon.statusDescription}'
        };
      }

      // ★ 对 featured/search 的特殊处理：不经过 pinned_ads 限额校验，直接允许
      final isSearchPopular = (coupon.type.value == 'featured') &&
          ((coupon.pinScope?.toLowerCase() ?? '') == 'search');

      if (isSearchPopular) {
        return {
          'valid': true,
          'coupon': coupon,
          'pinning_type': 'search',
        };
      }

      final eligibility = await checkPinningEligibility(
        listingId: listingId,
        couponType: coupon.type.value,
      );

      if (!(eligibility['eligible'] as bool? ?? false)) {
        return {
          'valid': false,
          'error': eligibility['reason'] ?? 'Pinning not eligible'
        };
      }

      return {
        'valid': true,
        'coupon': coupon,
        'pinning_type': eligibility['pinning_type'],
      };
    } catch (e) {
      _debugPrint('Failed to validate coupon usage: $e');
      return {'valid': false, 'error': 'Validation error: $e'};
    }
  }

  /// Get user's pinned items（非缓存）
  static Future<List<Map<String, dynamic>>> getUserPinnedItems(
      String userId) async {
    try {
      _debugPrint('Getting user pinned items: $userId');

      final response = await _client.from('pinned_ads').select('''
            *,
            listings:listing_id (
              id,
              title,
              category,
              price,
              images
            ),
            coupons:coupon_id (
              id,
              code,
              type,
              title
            )
          ''').eq('user_id', userId).order('created_at', ascending: false);

      List<dynamic> pinnedItems = [];
      pinnedItems = response;

      return pinnedItems
          .map<Map<String, dynamic>>((item) {
            try {
              return Map<String, dynamic>.from(item);
            } catch (e) {
              _debugPrint('Error processing pinned item: $e');
              return <String, dynamic>{};
            }
          })
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (e) {
      _debugPrint('Failed to get user pinned items: $e');
      return [];
    }
  }

  // ========== 10. 价格处理帮助方法 ==========

  static String formatPrice(dynamic priceValue) {
    if (priceValue == null) return '';
    try {
      if (priceValue is num) {
        return '\$${priceValue.toStringAsFixed(0)}';
      }
      if (priceValue is String) {
        final cleanedString = priceValue.replaceAll(RegExp(r'[^\d.]'), '');
        if (cleanedString.isEmpty) return priceValue;
        final parsedValue = double.tryParse(cleanedString);
        if (parsedValue != null) {
          return '\$${parsedValue.toStringAsFixed(0)}';
        }
      }
      return priceValue.toString();
    } catch (e) {
      _debugPrint('Error formatting price: $priceValue, error: $e');
      return priceValue?.toString() ?? '';
    }
  }

  static Map<String, dynamic> processListingData(
      Map<String, dynamic> listingData) {
    final processedData = Map<String, dynamic>.from(listingData);
    if (processedData.containsKey('price')) {
      processedData['formatted_price'] = formatPrice(processedData['price']);
    }
    return processedData;
  }

  // ========== 11. 扩展功能 ==========

  /// Get trending quota usage statistics（非缓存）
  static Future<Map<String, dynamic>> getTrendingQuotaStats() async {
    try {
      final quotaStatus = await getTrendingQuotaStatus();
      final usedCount = quotaStatus['used_count'] as int? ?? 0;
      final maxCount = quotaStatus['max_count'] as int? ?? 20;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final todayPins = await _client
          .from('pinned_ads')
          .select('created_at')
          .eq('pinning_type', 'trending')
          .eq('status', 'active')
          .gte('created_at', todayStart.toIso8601String());

      final pins = todayPins;

      final hourlyUsage = <int, int>{};
      for (final pin in pins) {
        try {
          final createdAtStr = pin['created_at']?.toString();
          if (createdAtStr != null) {
            final createdAt = DateTime.tryParse(createdAtStr);
            if (createdAt != null) {
              hourlyUsage[createdAt.hour] =
                  (hourlyUsage[createdAt.hour] ?? 0) + 1;
            }
          }
        } catch (_) {}
      }

      return {
        'quota_status': quotaStatus,
        'usage_percentage': ((usedCount / maxCount) * 100).round(),
        'hourly_usage': hourlyUsage,
        'peak_hour': hourlyUsage.entries.isNotEmpty
            ? hourlyUsage.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key
            : null,
      };
    } catch (e) {
      _debugPrint('Failed to get trending quota stats: $e');
      return {
        'quota_status': {'used_count': 0, 'max_count': 20, 'available': true},
        'usage_percentage': 0,
        'hourly_usage': <int, int>{},
        'peak_hour': null,
      };
    }
  }

  /// Batch operations for admin（非缓存）
  static Future<Map<String, dynamic>> batchOperations({
    required String operation,
    required Map<String, dynamic> parameters,
  }) async {
    try {
      _debugPrint('Executing batch operation: $operation');

      switch (operation) {
        case 'cleanup_expired':
          final expiredCoupons = await cleanupExpiredCoupons();
          final expiredAds = await cleanupExpiredPinnedAds();
          return {
            'success': true,
            'expired_coupons': expiredCoupons,
            'expired_ads': expiredAds,
          };
        case 'reset_trending_quota':
          await _client
              .from('pinned_ads')
              .update({'status': 'expired'})
              .eq('pinning_type', 'trending')
              .eq('status', 'active');
          return {'success': true, 'message': 'Trending quota reset'};
        default:
          return {'success': false, 'error': 'Unknown operation: $operation'};
      }
    } catch (e) {
      _debugPrint('Batch operation failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Advanced search for coupons（非缓存）
  static Future<List<CouponModel>> searchCoupons({
    String? userId,
    String? keyword,
    List<CouponType>? types,
    List<CouponStatus>? statuses,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      _debugPrint('Searching coupons with filters');

      final queryBuilder = _client.from('coupons').select('*');

      if (userId != null) {
        queryBuilder.eq('user_id', userId);
      }
      if (keyword != null && keyword.isNotEmpty) {
        queryBuilder.or(
            'title.ilike.%$keyword%,description.ilike.%$keyword%,code.ilike.%$keyword%');
      }
      if (types != null && types.isNotEmpty) {
        final typeValues = types.map((t) => t.value).toList();
        final typeConditions = typeValues.map((t) => 'type.eq.$t').join(',');
        queryBuilder.or(typeConditions);
      }
      if (statuses != null && statuses.isNotEmpty) {
        final statusValues = statuses.map((s) => s.value).toList();
        final statusConditions =
            statusValues.map((s) => 'status.eq.$s').join(',');
        queryBuilder.or(statusConditions);
      }
      if (fromDate != null) {
        queryBuilder.gte('created_at', fromDate.toIso8601String());
      }
      if (toDate != null) {
        queryBuilder.lte('created_at', toDate.toIso8601String());
      }

      queryBuilder
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final response = await queryBuilder;
      final responseList = response;

      return responseList
          .map((data) => _safeParseCoupon(data))
          .where((c) => c != null)
          .cast<CouponModel>()
          .toList();
    } catch (e) {
      _debugPrint('Failed to search coupons: $e');
      return [];
    }
  }

  /// Get coupon stats（简洁版聚合）
  static Future<CouponStats> getCouponStats(String userId) async {
    try {
      _debugPrint('Getting coupon stats for user: $userId');

      final response = await _client
          .from('coupons')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final responseList = response;
      final coupons = <CouponModel>[];
      final now = DateTime.now();

      for (final data in responseList) {
        final coupon = _safeParseCoupon(data);
        if (coupon != null) coupons.add(coupon);
      }

      int available = 0, used = 0, expired = 0;
      final all = coupons.length;

      for (final c in coupons) {
        if (c.status == CouponStatus.used) {
          used++;
        } else if (c.status == CouponStatus.active) {
          if (c.expiresAt.isBefore(now)) {
            expired++;
          } else {
            available++;
          }
        } else {
          expired++; // revoked 等其它状态归类为过期
        }
      }

      _debugPrint(
          'Coupon stats: All=$all, Available=$available, Used=$used, Expired=$expired');

      return CouponStats(
        totalCoupons: all,
        activeCoupons: available,
        usedCoupons: used,
        expiredCoupons: expired,
        revokedCoupons: 0,
        couponsByType: {},
        usageRate: all > 0 ? used / all : 0.0,
      );
    } catch (e) {
      _debugPrint('Failed to get coupon stats: $e');
      return CouponStats.fromCoupons([]);
    }
  }
}

class _CacheEntry<T> {
  final DateTime ts;
  final T data;
  _CacheEntry(this.ts, this.data);

  /// 是否仍在有效期（与 CouponService._ttl 同步）
  bool get valid => DateTime.now().difference(ts) < CouponService._ttl;
}
