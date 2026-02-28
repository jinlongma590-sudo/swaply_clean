// lib/services/dual_favorites_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ✅ 使用 RPC 发送通知
import 'package:swaply/services/notification_service.dart';

/// 修复版双重收藏服务 - 同时管理 favorites 和 wishlists 表（带缓存和去重）
/// ✅ [修复] UUID 查询语法错误
/// ✅ [修复] 无限重试循环保护
class DualFavoritesService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _favoritesTable = 'favorites';
  static const String _wishlistsTable = 'wishlists';

  // ===== 8s TTL 缓存 + 并发去重 =====
  static const _ttl = Duration(seconds: 8);
  static final Map<String, _FavCache> _cache = {};
  static final Map<String, Future<List<Map<String, dynamic>>>> _inflight = {};
  // ✅ 紧急修复：防止死循环 - 请求频率限制
  static final Map<String, DateTime> _lastRequestTime = {};
  static const _minRequestInterval = Duration(milliseconds: 500);

  // ===== ✅ [新增] 失败查询保护（防止无限重试） =====
  static final Map<String, _FailureRecord> _failures = {};
  static const _failureRetryDelay = Duration(seconds: 30); // 失败后 30 秒内不重试
  static const _maxConsecutiveFailures = 3; // 连续失败 3 次后延长延迟

  // ===== 全局内存缓存（解决N+1查询问题） =====
  static final Map<String, Set<String>> _userFavoritesCache = {}; // userId -> Set<listingId>
  static final Map<String, Set<String>> _userWishlistsCache = {}; // userId -> Set<listingId>
  static final Map<String, Future<void>> _cacheLoadingInflight = {};

  static String _key(String userId, int limit, int offset, String kind) =>
      '$userId|$limit|$offset|$kind';

  static void _debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[DualFavoritesService] $message');
    }
  }

  /// 对外暴露的清缓存方法（登出时可调用）
  static void clearCache() {
    _cache.clear();
    _inflight.clear();
    _failures.clear(); // ✅ 同时清除失败记录
    _userFavoritesCache.clear();
    _userWishlistsCache.clear();
    _cacheLoadingInflight.clear();
    _debugPrint('缓存、并发去重池、失败记录、全局收藏缓存已清空');
  }

  // ✅ [新增] 初始化用户收藏缓存（App启动或用户登录时调用）
  static Future<void> initUserCache({required String userId}) async {
    try {
      _debugPrint('=== 初始化用户收藏缓存 ===');
      _debugPrint('用户ID: $userId');
      
      if (_cacheLoadingInflight.containsKey(userId)) {
        _debugPrint('🔄 缓存加载已在进行中，等待完成...');
        await _cacheLoadingInflight[userId];
        return;
      }
      
      final future = _loadUserCacheInternal(userId);
      _cacheLoadingInflight[userId] = future;
      
      try {
        await future;
      } finally {
        _cacheLoadingInflight.remove(userId);
      }
      
      _debugPrint('✅ 用户收藏缓存初始化完成');
      _debugPrint('  - 收藏数量: ${_userFavoritesCache[userId]?.length ?? 0}');
      _debugPrint('  - 心愿单数量: ${_userWishlistsCache[userId]?.length ?? 0}');
    } catch (e) {
      _debugPrint('❌ 初始化用户收藏缓存失败: $e');
      // 失败时清空缓存，避免脏数据
      _userFavoritesCache.remove(userId);
      _userWishlistsCache.remove(userId);
    }
  }
  
  static Future<void> _loadUserCacheInternal(String userId) async {
    _debugPrint('正在加载用户收藏数据...');
    
    // 并行加载收藏和心愿单
    final favoritesFuture = _client
        .from(_favoritesTable)
        .select('listing_id')
        .eq('user_id', userId);
    
    final wishlistsFuture = _client
        .from(_wishlistsTable)
        .select('listing_id')
        .eq('user_id', userId);
    
    final results = await Future.wait([favoritesFuture, wishlistsFuture]);
    
    final favorites = results[0] as List<dynamic>;
    final wishlists = results[1] as List<dynamic>;
    
    // 转换为Set
    final favoritesSet = <String>{};
    for (final item in favorites) {
      final listingId = item['listing_id']?.toString();
      if (listingId != null && listingId.isNotEmpty) {
        favoritesSet.add(listingId);
      }
    }
    
    final wishlistsSet = <String>{};
    for (final item in wishlists) {
      final listingId = item['listing_id']?.toString();
      if (listingId != null && listingId.isNotEmpty) {
        wishlistsSet.add(listingId);
      }
    }
    
    _userFavoritesCache[userId] = favoritesSet;
    _userWishlistsCache[userId] = wishlistsSet;
    
    _debugPrint('缓存加载完成: ${favoritesSet.length} 收藏, ${wishlistsSet.length} 心愿单');
  }
  
  // ✅ [新增] 同步检查方法（避免网络请求）
  static bool isInFavoritesSync({required String userId, required String listingId}) {
    final favoritesSet = _userFavoritesCache[userId];
    final wishlistsSet = _userWishlistsCache[userId];
    
    final inFavorites = favoritesSet?.contains(listingId) ?? false;
    final inWishlist = wishlistsSet?.contains(listingId) ?? false;
    
    if (kDebugMode && (inFavorites || inWishlist)) {
      _debugPrint('🔄 同步检查: 用户 $userId, 商品 $listingId');
      _debugPrint('  - 在收藏中: $inFavorites');
      _debugPrint('  - 在心愿单中: $inWishlist');
    }
    
    return inFavorites || inWishlist;
  }
  
  // ✅ [新增] 检查是否需要初始化缓存
  static bool _isCacheInitialized(String userId) {
    return _userFavoritesCache.containsKey(userId) && 
           _userWishlistsCache.containsKey(userId);
  }

  // ✅ [新增] 检查是否应该跳过查询（防重试循环）
  static bool _shouldSkipQuery(String key) {
    final failure = _failures[key];
    if (failure == null) return false;

    final now = DateTime.now();
    final delay = failure.count >= _maxConsecutiveFailures
        ? _failureRetryDelay * 3 // 多次失败后延长到 90 秒
        : _failureRetryDelay;

    if (now.difference(failure.lastAttempt) < delay) {
      _debugPrint('⏭️ 跳过查询 $key（失败 ${failure.count} 次，等待 ${delay.inSeconds}s）');
      return true;
    }

    return false;
  }

  // ✅ [新增] 记录查询失败
  static void _recordFailure(String key) {
    final existing = _failures[key];
    if (existing == null) {
      _failures[key] = _FailureRecord(DateTime.now(), 1);
    } else {
      _failures[key] = _FailureRecord(DateTime.now(), existing.count + 1);
    }
    _debugPrint('❌ 记录失败：$key（共 ${_failures[key]!.count} 次）');
  }

  // ✅ [新增] 清除失败记录（查询成功时）
  static void _clearFailure(String key) {
    if (_failures.containsKey(key)) {
      _failures.remove(key);
      _debugPrint('✅ 清除失败记录：$key');
    }
  }

  // ======== 安全类型转换 ========
  static Map<String, dynamic> _safeMapConvert(dynamic input) {
    if (input == null) return <String, dynamic>{};

    if (input is Map<String, dynamic>) {
      return input;
    } else if (input is Map) {
      try {
        return Map<String, dynamic>.from(input);
      } catch (e) {
        _debugPrint('类型转换失败: $e');
        return <String, dynamic>{};
      }
    }

    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _safeListConvert(dynamic input) {
    if (input == null) return [];

    if (input is List<Map<String, dynamic>>) {
      return input;
    } else if (input is List) {
      try {
        return input.map((item) => _safeMapConvert(item)).toList();
      } catch (e) {
        _debugPrint('列表转换失败: $e');
        return [];
      }
    }

    return [];
  }

  // ======== 写操作 ========
  /// 同时添加到收藏和心愿单 - 幂等容错
  static Future<bool> addToFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('=== 开始添加收藏 ===');
      _debugPrint('用户ID: $userId');
      _debugPrint('商品ID: $listingId');

      // 1) 已存在直接返回（不再发送通知）
      final existingFavorite = await _client
          .from(_favoritesTable)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      if (existingFavorite != null) {
        _debugPrint('商品已在收藏中（跳过插入 & 通知）');
        return false;
      }

      final now = DateTime.now().toIso8601String();
      bool favoritesSuccess = false;
      bool wishlistSuccess = false;

      // 2) 插入 favorites
      try {
        _debugPrint('正在插入到 Favorites 表...');
        final favoriteData = {
          'user_id': userId,
          'listing_id': listingId,
          'created_at': now,
          'updated_at': now, // 明确提供 updated_at 字段
        };
        _debugPrint('准备插入收藏数据: $favoriteData');

        final favoriteResult =
            await _client.from(_favoritesTable).insert(favoriteData).select();

        _debugPrint('Favorites 表插入结果: $favoriteResult');
        favoritesSuccess =
            (favoriteResult is List) && favoriteResult.isNotEmpty;

        if (favoritesSuccess) {
          _debugPrint('✅ Favorites 表插入成功');
        }
      } catch (e) {
        _debugPrint('❌ Favorites 表插入失败: $e');

        // 尝试让数据库自动处理 updated_at
        try {
          _debugPrint('尝试让数据库自动处理 updated_at...');
          final favoriteDataAuto = {
            'user_id': userId,
            'listing_id': listingId,
            'created_at': now,
          };

          final favoriteResult = await _client
              .from(_favoritesTable)
              .insert(favoriteDataAuto)
              .select();

          favoritesSuccess =
              (favoriteResult is List) && favoriteResult.isNotEmpty;
          _debugPrint('Favorites 表自动处理结果: $favoriteResult');
        } catch (e2) {
          _debugPrint('自动处理也失败: $e2');
          if (e2.toString().contains('duplicate key')) {
            favoritesSuccess = true;
          }
        }
      }

      // 3) 插入 wishlists
      try {
        _debugPrint('正在插入到 Wishlists 表...');
        final wishlistData = {
          'user_id': userId,
          'listing_id': listingId,
          'created_at': now,
        };

        final wishlistResult =
            await _client.from(_wishlistsTable).insert(wishlistData).select();

        wishlistSuccess = (wishlistResult is List) && wishlistResult.isNotEmpty;

        if (wishlistSuccess) {
          _debugPrint('✅ Wishlists 表插入成功');
        }
      } catch (e) {
        _debugPrint('❌ Wishlists 表插入失败: $e');
        if (e.toString().contains('duplicate key')) {
          wishlistSuccess = true;
        }
      }

      final success = favoritesSuccess || wishlistSuccess;
      _debugPrint(
          '最终结果: $success (Favorites: $favoritesSuccess, Wishlist: $wishlistSuccess)');

      if (success) {
        // === ⚠️ 不再需要前端发送通知，依赖数据库触发器 create_wishlist_notification ===
        // 当 wishlists 表插入成功时，PostgreSQL 触发器会自动创建 wishlist 类型的通知
        // 避免重复推送（之前是前端 + 触发器 = 两条推送）
        try {
          // 仅记录日志，验证卖家信息（用于调试）
          final listingRow = await _client
              .from('listings')
              .select('user_id, title')
              .eq('id', listingId)
              .maybeSingle();

          final sellerId = listingRow?['user_id'] as String?;
          final listingTitleRaw = listingRow?['title'];
          final safeTitle =
              (listingTitleRaw is String && listingTitleRaw.trim().isNotEmpty)
                  ? listingTitleRaw
                  : 'your item';

          if (sellerId != null && sellerId.isNotEmpty && sellerId != userId) {
            _debugPrint(
              '✅ 收藏成功，数据库触发器将自动创建 wishlist 通知: $listingId -> $sellerId',
            );
          } else {
            _debugPrint('未发送通知：sellerId 无效或自己收藏自己');
          }
        } catch (e) {
          _debugPrint('验证卖家信息时异常（不影响收藏）: $e');
        }
      }

      if (favoritesSuccess && wishlistSuccess) {
        _debugPrint('🟟 完美！同时添加到收藏和心愿单');
      } else if (wishlistSuccess) {
        _debugPrint('⚠️ 仅添加到心愿单，收藏表配置可能有问题');
      }

      // ✅ 更新本地缓存
      if (success) {
        if (favoritesSuccess) {
          _updateLocalCache(
            userId: userId,
            listingId: listingId,
            isAdd: true,
            isFavorite: true,
          );
        }
        if (wishlistSuccess) {
          _updateLocalCache(
            userId: userId,
            listingId: listingId,
            isAdd: true,
            isFavorite: false,
          );
        }
      }
      
      return success;
    } catch (e) {
      _debugPrint('添加收藏时出现异常: $e');
      return false;
    }
  }

  /// 同时从收藏和心愿单中移除
  static Future<bool> removeFromFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('=== 开始移除收藏 ===');
      _debugPrint('用户ID: $userId, 商品ID: $listingId');

      bool favoritesSuccess = false;
      bool wishlistSuccess = false;

      // favorites
      try {
        await _client
            .from(_favoritesTable)
            .delete()
            .eq('user_id', userId)
            .eq('listing_id', listingId);
        _debugPrint('已从 favorites 表删除');
        favoritesSuccess = true;
      } catch (e) {
        _debugPrint('从 favorites 表删除失败: $e');
      }

      // wishlists
      try {
        await _client
            .from(_wishlistsTable)
            .delete()
            .eq('user_id', userId)
            .eq('listing_id', listingId);
        _debugPrint('已从 wishlists 表删除');
        wishlistSuccess = true;
      } catch (e) {
        _debugPrint('从 wishlists 表删除失败: $e');
      }

      final success = favoritesSuccess || wishlistSuccess;
      
      // ✅ 更新本地缓存
      if (success) {
        if (favoritesSuccess) {
          _updateLocalCache(
            userId: userId,
            listingId: listingId,
            isAdd: false,
            isFavorite: true,
          );
        }
        if (wishlistSuccess) {
          _updateLocalCache(
            userId: userId,
            listingId: listingId,
            isAdd: false,
            isFavorite: false,
          );
        }
      }
      
      return success;
    } catch (e) {
      _debugPrint('移除收藏时出现异常: $e');
      return false;
    }
  }

  /// 检查是否在收藏中（任一表存在即视为已收藏）
  static Future<bool> isInFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('检查收藏状态 - 用户: $userId, 商品: $listingId');
      
      // ✅ 优先使用同步缓存检查（避免网络请求）
      if (_isCacheInitialized(userId)) {
        final cachedResult = isInFavoritesSync(userId: userId, listingId: listingId);
        if (kDebugMode) {
          _debugPrint('✅ 使用缓存检查结果: $cachedResult');
        }
        return cachedResult;
      }
      
      // ✅ 缓存正在加载中，等待加载完成
      if (_cacheLoadingInflight.containsKey(userId)) {
        _debugPrint('⏳ 缓存正在加载中，等待完成...');
        try {
          await _cacheLoadingInflight[userId];
          // 加载完成后再次检查缓存
          if (_isCacheInitialized(userId)) {
            final cachedResult = isInFavoritesSync(userId: userId, listingId: listingId);
            _debugPrint('✅ 缓存加载完成，使用缓存结果: $cachedResult');
            return cachedResult;
          }
        } catch (e) {
          _debugPrint('等待缓存加载时出错: $e');
          // 继续执行网络查询
        }
      }
      
      // ✅ 缓存未初始化，触发后台初始化（避免后续N+1）
      _debugPrint('⚠️ 缓存未初始化，触发后台初始化...');
      unawaited(initUserCache(userId: userId));
      
      // 回退到原始网络查询（仅限首次）
      _debugPrint('🔄 回退到网络查询...');

      final favoriteResult = await _client
          .from(_favoritesTable)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      final wishlistResult = await _client
          .from(_wishlistsTable)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      final isInFavorites = favoriteResult != null;
      final isInWishlist = wishlistResult != null;

      _debugPrint('检查结果 - Favorite: $isInFavorites, Wishlist: $isInWishlist');
      return isInFavorites || isInWishlist;
    } catch (e) {
      _debugPrint('检查收藏状态时出现异常: $e');
      return false;
    }
  }

  /// ✅ [新增] 更新本地缓存
  static void _updateLocalCache({
    required String userId,
    required String listingId,
    required bool isAdd, // true=添加, false=移除
    required bool isFavorite, // true=favorites表, false=wishlists表
  }) {
    if (isFavorite) {
      final cache = _userFavoritesCache[userId];
      if (cache != null) {
        if (isAdd) {
          cache.add(listingId);
          _debugPrint('✅ 更新favorites缓存: 添加 $listingId');
        } else {
          cache.remove(listingId);
          _debugPrint('✅ 更新favorites缓存: 移除 $listingId');
        }
      }
    } else {
      final cache = _userWishlistsCache[userId];
      if (cache != null) {
        if (isAdd) {
          cache.add(listingId);
          _debugPrint('✅ 更新wishlists缓存: 添加 $listingId');
        } else {
          cache.remove(listingId);
          _debugPrint('✅ 更新wishlists缓存: 移除 $listingId');
        }
      }
    }
  }

  /// 切换收藏状态（成功返回切换后的状态）
  static Future<bool> toggleFavorite({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('=== 切换收藏状态 ===');
      _debugPrint('用户ID: $userId, 商品ID: $listingId');

      final currentStatus = await isInFavorites(
        userId: userId,
        listingId: listingId,
      );
      _debugPrint('当前收藏状态: $currentStatus');

      if (currentStatus) {
        final success = await removeFromFavorites(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('移除操作结果: $success');
        return success ? false : currentStatus;
      } else {
        final success = await addToFavorites(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('添加操作结果: $success');
        return success ? true : currentStatus;
      }
    } catch (e) {
      _debugPrint('切换收藏状态时出现异常: $e');
      // 出错时返回当前数据库状态，尽量保证 UI 不错乱
      return await isInFavorites(userId: userId, listingId: listingId);
    }
  }

  // ======== 读操作：带缓存 + 并发去重 + 失败保护 ========
  /// 获取用户的收藏列表（favorites 表）- 带缓存
  static Future<List<Map<String, dynamic>>> getUserFavorites({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    final key = _key(userId, limit, offset, 'fav');
    final now = DateTime.now();

    // ✅ 紧急修复：防止死循环 - 请求频率限制
    final lastTime = _lastRequestTime[key];
    if (lastTime != null && now.difference(lastTime) < _minRequestInterval) {
      if (kDebugMode) debugPrint('[DualFavoritesService] 请求过于频繁，跳过 $key');
      // 返回缓存数据（如果有），否则返回空数组
      final cached = _cache[key];
      if (cached != null && now.difference(cached.at) < Duration(seconds: 30)) {
        return cached.data;
      }
      return [];
    }
    _lastRequestTime[key] = now;

    // ✅ [新增] 失败保护：跳过频繁失败的查询
    if (_shouldSkipQuery(key)) {
      return [];
    }

    // 命中缓存
    final c = _cache[key];
    if (c != null && now.difference(c.at) < _ttl) {
      if (kDebugMode) debugPrint('[DualFavoritesService] cache HIT $key');
      return c.data;
    }

    // 并发去重
    final f = _inflight[key];
    if (f != null) {
      if (kDebugMode) debugPrint('[DualFavoritesService] join inflight $key');
      return await f;
    }

    // 发起请求
    final future =
        _fetchFavorites(userId: userId, limit: limit, offset: offset);
    _inflight[key] = future;
    try {
      final data = await future;
      _cache[key] = _FavCache(now, data);
      _clearFailure(key); // ✅ 成功后清除失败记录
      return data;
    } catch (e) {
      _recordFailure(key); // ✅ 失败后记录
      rethrow;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchFavorites({
    required String userId,
    required int limit,
    required int offset,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
            '[DualFavoritesService] FETCH favorites $userId/$limit/$offset');
      }

      _debugPrint('=== 获取用户收藏列表 ===');
      _debugPrint('用户ID: $userId, 限制: $limit, 偏移: $offset');

      final rawFavoritesData = await _client
          .from(_favoritesTable)
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _debugPrint('收藏原始数据: $rawFavoritesData');

      if ((rawFavoritesData.isEmpty)) {
        _debugPrint('未找到收藏记录');
        return [];
      }

      final List<Map<String, dynamic>> favoritesData =
          _safeListConvert(rawFavoritesData);

      // ✅ [性能优化] 收集所有listing_id，一次性查询
      final listingIds = favoritesData
          .map((item) => item['listing_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      if (listingIds.isEmpty) {
        _debugPrint('没有有效的listing_id');
        return [];
      }

      _debugPrint('准备查询 ${listingIds.length} 个商品...');

      // ✅ [关键修复] 使用正确的 Supabase IN 查询语法
      // 不要手动添加引号！Supabase SDK 会自动处理
      final allListings = await _client
          .from('listings')
          .select(
              'id, title, price, city, images, image_urls, status, is_active, seller_name, category, description, created_at')
          .filter('id', 'in', '(${listingIds.join(',')})') // ← 修复：不添加引号
          .eq('is_active', true);

      _debugPrint('查询到 ${allListings.length} 个有效商品');

      // 创建Map以便快速查找
      final listingsMap = <String, Map<String, dynamic>>{
        for (var listing in allListings)
          listing['id'].toString(): _safeMapConvert(listing)
      };

      // 组装结果
      final result = <Map<String, dynamic>>[];
      for (final favoriteItem in favoritesData) {
        final listingId = favoriteItem['listing_id']?.toString();
        if (listingId != null) {
          final listing = listingsMap[listingId];
          if (listing != null) {
            result.add({
              'id': favoriteItem['id'],
              'created_at': favoriteItem['created_at'],
              'listing_id': listingId,
              'listing': listing, // 统一为 'listing'
            });
            _debugPrint('成功加载商品数据: $listingId');
          } else {
            _debugPrint('商品不存在或已停用: $listingId');
          }
        }
      }

      _debugPrint('最终收藏列表: ${result.length} 项');
      return result;
    } catch (e) {
      _debugPrint('获取用户收藏列表时出现异常: $e');
      return [];
    }
  }

  /// 获取用户的心愿单列表（wishlists 表）- 带缓存
  static Future<List<Map<String, dynamic>>> getUserWishlist({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    final key = _key(userId, limit, offset, 'wish');
    final now = DateTime.now();

    // ✅ 紧急修复：防止死循环 - 请求频率限制
    final lastTime = _lastRequestTime[key];
    if (lastTime != null && now.difference(lastTime) < _minRequestInterval) {
      if (kDebugMode) debugPrint('[DualFavoritesService] 请求过于频繁，跳过 $key');
      // 返回缓存数据（如果有），否则返回空数组
      final cached = _cache[key];
      if (cached != null && now.difference(cached.at) < Duration(seconds: 30)) {
        return cached.data;
      }
      return [];
    }
    _lastRequestTime[key] = now;

    // ✅ [新增] 失败保护：跳过频繁失败的查询
    if (_shouldSkipQuery(key)) {
      return [];
    }

    final c = _cache[key];
    if (c != null && now.difference(c.at) < _ttl) {
      if (kDebugMode) debugPrint('[DualFavoritesService] cache HIT $key');
      return c.data;
    }

    final f = _inflight[key];
    if (f != null) {
      if (kDebugMode) debugPrint('[DualFavoritesService] join inflight $key');
      return await f;
    }

    final future = _fetchWishlist(userId: userId, limit: limit, offset: offset);
    _inflight[key] = future;
    try {
      final data = await future;
      _cache[key] = _FavCache(now, data);
      _clearFailure(key); // ✅ 成功后清除失败记录
      return data;
    } catch (e) {
      _recordFailure(key); // ✅ 失败后记录
      rethrow;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchWishlist({
    required String userId,
    required int limit,
    required int offset,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
            '[DualFavoritesService] FETCH wishlist $userId/$limit/$offset');
      }

      _debugPrint('=== 获取用户心愿单列表 ===');
      _debugPrint('用户ID: $userId, 限制: $limit, 偏移: $offset');

      final rawWishlistData = await _client
          .from(_wishlistsTable)
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _debugPrint('心愿单原始数据: $rawWishlistData');

      if ((rawWishlistData.isEmpty)) {
        _debugPrint('未找到心愿单记录');
        return [];
      }

      final List<Map<String, dynamic>> wishlistData =
          _safeListConvert(rawWishlistData);

      // ✅ [性能优化] 收集所有listing_id，一次性查询
      final listingIds = wishlistData
          .map((item) => item['listing_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      if (listingIds.isEmpty) {
        _debugPrint('没有有效的listing_id');
        return [];
      }

      _debugPrint('准备查询 ${listingIds.length} 个心愿单商品...');

      // ✅ [关键修复] 使用正确的 Supabase IN 查询语法
      // 不要手动添加引号！Supabase SDK 会自动处理
      final allListings = await _client
          .from('listings')
          .select(
              'id, title, price, city, images, image_urls, status, is_active, seller_name, category, description, created_at')
          .filter('id', 'in', '(${listingIds.join(',')})') // ← 修复：不添加引号
          .eq('is_active', true);

      _debugPrint('查询到 ${allListings.length} 个有效心愿单商品');

      // 创建Map以便快速查找
      final listingsMap = <String, Map<String, dynamic>>{
        for (var listing in allListings)
          listing['id'].toString(): _safeMapConvert(listing)
      };

      // 组装结果
      final result = <Map<String, dynamic>>[];
      for (final wishlistItem in wishlistData) {
        final listingId = wishlistItem['listing_id']?.toString();
        if (listingId != null) {
          final listing = listingsMap[listingId];
          if (listing != null) {
            result.add({
              'id': wishlistItem['id'],
              'created_at': wishlistItem['created_at'],
              'listing_id': listingId,
              'listing': listing, // 统一为 'listing'
            });
            _debugPrint('成功加载心愿单商品数据: $listingId');
          } else {
            _debugPrint('心愿单商品不存在或已停用: $listingId');
          }
        }
      }

      _debugPrint('最终心愿单列表: ${result.length} 项');
      return result;
    } catch (e) {
      _debugPrint('获取用户心愿单列表时出现异常: $e');
      return [];
    }
  }

  /// 清空用户的所有收藏和心愿单
  static Future<bool> clearUserFavorites({required String userId}) async {
    try {
      _debugPrint('=== 清空用户所有收藏 ===');
      _debugPrint('用户ID: $userId');

      bool favoritesSuccess = false;
      bool wishlistSuccess = false;

      try {
        await _client.from(_favoritesTable).delete().eq('user_id', userId);
        _debugPrint('已清空 favorites 表');
        favoritesSuccess = true;
      } catch (e) {
        _debugPrint('清空 favorites 表失败: $e');
      }

      try {
        await _client.from(_wishlistsTable).delete().eq('user_id', userId);
        _debugPrint('已清空 wishlists 表');
        wishlistSuccess = true;
      } catch (e) {
        _debugPrint('清空 wishlists 表失败: $e');
      }

      return favoritesSuccess || wishlistSuccess;
    } catch (e) {
      _debugPrint('清空收藏时出现异常: $e');
      return false;
    }
  }

  /// 测试数据库连接
  static Future<bool> testConnection({required String userId}) async {
    try {
      _debugPrint('=== 测试数据库连接 ===');

      await _client
          .from(_favoritesTable)
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      _debugPrint('Favorites 表连接正常');

      await _client
          .from(_wishlistsTable)
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      _debugPrint('Wishlists 表连接正常');

      return true;
    } catch (e) {
      _debugPrint('数据库连接测试失败: $e');
      return false;
    }
  }

  /// 格式化保存时间
  static String formatSavedTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return 'Recently';

    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '${weeks}w ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      _debugPrint('格式化时间时出错: $e');
      return 'Recently';
    }
  }
}

// ===== 缓存数据结构 =====
class _FavCache {
  final DateTime at;
  final List<Map<String, dynamic>> data;
  _FavCache(this.at, this.data);
}

// ===== ✅ [新增] 失败记录数据结构 =====
class _FailureRecord {
  final DateTime lastAttempt;
  final int count;
  _FailureRecord(this.lastAttempt, this.count);
}
