// lib/services/favorites_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class FavoritesService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _tableName = 'favorites';

  static void _debugPrint(String message) {
    if (kDebugMode) {
      print('[FavoritesService] $message');
    }
  }

  /// 添加商品到收藏
  static Future<bool> addToFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('Adding to favorites: userId=$userId, listingId=$listingId');

      // 检查是否已经在收藏中
      final existing = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      if (existing != null) {
        _debugPrint('Item already in favorites');
        return false;
      }

      // 添加到收藏
      final result = await _client.from(_tableName).insert({
        'user_id': userId,
        'listing_id': listingId,
        'created_at': DateTime.now().toIso8601String(),
      }).select();

      _debugPrint('Insert result: $result');
      return result.isNotEmpty;
    } catch (e) {
      _debugPrint('Error adding to favorites: $e');
      return false;
    }
  }

  /// 从收藏中移除商品
  static Future<bool> removeFromFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint(
          'Removing from favorites: userId=$userId, listingId=$listingId');

      await _client
          .from(_tableName)
          .delete()
          .eq('user_id', userId)
          .eq('listing_id', listingId);

      _debugPrint('Successfully removed from favorites');
      return true;
    } catch (e) {
      _debugPrint('Error removing from favorites: $e');
      return false;
    }
  }

  /// 检查商品是否在收藏中
  static Future<bool> isInFavorites({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint(
          'Checking favorites status: userId=$userId, listingId=$listingId');

      final result = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      final isInFavorites = result != null;
      _debugPrint('Is in favorites: $isInFavorites');
      return isInFavorites;
    } catch (e) {
      _debugPrint('Error checking favorites: $e');
      return false;
    }
  }

  /// 获取用户的收藏数量
  static Future<int> getFavoritesCount({required String userId}) async {
    try {
      _debugPrint('Getting favorites count for user: $userId');

      final data =
          await _client.from(_tableName).select('id').eq('user_id', userId);

      final count = (data as List).length;
      _debugPrint('Favorites count: $count');
      return count;
    } catch (e) {
      _debugPrint('Error getting favorites count: $e');
      return 0;
    }
  }

  /// 获取用户的收藏商品列表（带商品详情）
  static Future<List<Map<String, dynamic>>> getUserFavorites({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      _debugPrint(
          'Getting user favorites: userId=$userId, limit=$limit, offset=$offset');

      // 先获取收藏记录
      final favoritesData = await _client
          .from(_tableName)
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _debugPrint('Favorites raw data: $favoritesData');

      if (favoritesData.isEmpty) {
        _debugPrint('No favorites found');
        return [];
      }

      // 为每个收藏项目单独获取商品信息
      final result = <Map<String, dynamic>>[];
      for (final favoriteItem in favoritesData) {
        final listingId = favoriteItem['listing_id'];
        if (listingId != null) {
          try {
            final listing = await _client
                .from('listings')
                .select(
                    'id, title, price, city, images, image_urls, status, is_active, seller_name, category, description, created_at')
                .eq('id', listingId)
                .eq('is_active', true)
                .maybeSingle();

            if (listing != null) {
              result.add({
                'id': favoriteItem['id'],
                'created_at': favoriteItem['created_at'],
                'listing_id': listingId,
                'listing': listing,
              });
              _debugPrint(
                  'Successfully loaded listing data for item $listingId');
            }
          } catch (e) {
            _debugPrint('Error fetching listing $listingId: $e');
          }
        }
      }

      _debugPrint('Final result: ${result.length} items');
      return result;
    } catch (e) {
      _debugPrint('Error getting user favorites: $e');
      return [];
    }
  }

  /// 切换收藏状态（添加或移除）
  static Future<bool> toggleFavorite({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('Toggling favorite: userId=$userId, listingId=$listingId');

      // 先检查当前状态
      final isCurrentlyInFavorites = await isInFavorites(
        userId: userId,
        listingId: listingId,
      );

      _debugPrint('Currently in favorites: $isCurrentlyInFavorites');

      bool success;
      if (isCurrentlyInFavorites) {
        // 如果已在收藏中，则移除
        success = await removeFromFavorites(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('Remove operation success: $success');
        return success ? false : isCurrentlyInFavorites; // 成功移除返回false
      } else {
        // 如果不在收藏中，则添加
        success = await addToFavorites(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('Add operation success: $success');
        return success ? true : isCurrentlyInFavorites; // 成功添加返回true
      }
    } catch (e) {
      _debugPrint('Error toggling favorite: $e');
      // 如果出错，返回当前状态不变
      return await isInFavorites(userId: userId, listingId: listingId);
    }
  }

  /// 批量删除用户的收藏项（可选功能）
  static Future<bool> clearUserFavorites({required String userId}) async {
    try {
      _debugPrint('Clearing favorites for user: $userId');

      await _client.from(_tableName).delete().eq('user_id', userId);

      _debugPrint('Successfully cleared favorites');
      return true;
    } catch (e) {
      _debugPrint('Error clearing favorites: $e');
      return false;
    }
  }

  /// 测试数据库连接和权限
  static Future<bool> testConnection({required String userId}) async {
    try {
      _debugPrint('Testing favorites database connection...');

      // 尝试读取用户的收藏
      final data = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .limit(1);

      _debugPrint('Connection test successful');
      return true;
    } catch (e) {
      _debugPrint('Connection test failed: $e');
      return false;
    }
  }

  /// 获取用户收藏的商品ID列表（用于商品详情页检查状态）
  static Future<Set<String>> getUserFavoriteListingIds({
    required String userId,
  }) async {
    try {
      _debugPrint('Getting user favorite listing IDs for user: $userId');

      final data = await _client
          .from(_tableName)
          .select('listing_id')
          .eq('user_id', userId);

      final listingIds = <String>{};
      for (final item in data) {
        final listingId = item['listing_id']?.toString();
        if (listingId != null) {
          listingIds.add(listingId);
        }
      }

      _debugPrint('Found ${listingIds.length} favorite listing IDs');
      return listingIds;
    } catch (e) {
      _debugPrint('Error getting favorite listing IDs: $e');
      return <String>{};
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
      _debugPrint('Error formatting time: $e');
      return 'Recently';
    }
  }
}
