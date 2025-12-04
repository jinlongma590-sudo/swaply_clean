// lib/services/wishlist_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class WishlistService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _tableName = 'wishlists';

  static void _debugPrint(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  /// æ·»åŠ å•†å“åˆ°wishlist
  static Future<bool> addToWishlist({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('Adding to wishlist: userId=$userId, listingId=$listingId');

      // æ£€æŸ¥æ˜¯å¦å·²ç»åœ¨wishlistä¸­
      final existing = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      if (existing != null) {
        _debugPrint('Item already in wishlist');
        return false;
      }

      // æ·»åŠ åˆ°wishlist
      final result = await _client.from(_tableName).insert({
        'user_id': userId,
        'listing_id': listingId,
        'created_at': DateTime.now().toIso8601String(),
      }).select();

      _debugPrint('Insert result: $result');
      return result.isNotEmpty;
    } catch (e) {
      _debugPrint('Error adding to wishlist: $e');
      return false;
    }
  }

  /// ä»Žwishlistä¸­ç§»é™¤å•†å“
  static Future<bool> removeFromWishlist({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint(
          'Removing from wishlist: userId=$userId, listingId=$listingId');

      await _client
          .from(_tableName)
          .delete()
          .eq('user_id', userId)
          .eq('listing_id', listingId);

      _debugPrint('Successfully removed from wishlist');
      return true;
    } catch (e) {
      _debugPrint('Error removing from wishlist: $e');
      return false;
    }
  }

  /// æ£€æŸ¥å•†å“æ˜¯å¦åœ¨wishlistä¸­
  static Future<bool> isInWishlist({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint(
          'Checking wishlist status: userId=$userId, listingId=$listingId');

      final result = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      final isInWishlist = result != null;
      _debugPrint('Is in wishlist: $isInWishlist');
      return isInWishlist;
    } catch (e) {
      _debugPrint('Error checking wishlist: $e');
      return false;
    }
  }

  /// èŽ·å–ç”¨æˆ·çš„wishlistæ•°é‡
  static Future<int> getWishlistCount({required String userId}) async {
    try {
      _debugPrint('Getting wishlist count for user: $userId');

      final data =
          await _client.from(_tableName).select('id').eq('user_id', userId);

      final count = (data as List).length;
      _debugPrint('Wishlist count: $count');
      return count;
    } catch (e) {
      _debugPrint('Error getting wishlist count: $e');
      return 0;
    }
  }

  /// èŽ·å–ç”¨æˆ·çš„wishlistå•†å“åˆ—è¡¨ï¼ˆç®€åŒ–ç‰ˆæœ¬ï¼‰
  static Future<List<Map<String, dynamic>>> getUserWishlist({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      _debugPrint(
          'Getting user wishlist: userId=$userId, limit=$limit, offset=$offset');

      // å…ˆèŽ·å–wishlistè®°å½•
      final wishlistData = await _client
          .from(_tableName)
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _debugPrint('Wishlist raw data: $wishlistData');

      if (wishlistData.isEmpty) {
        _debugPrint('No wishlist items found');
        return [];
      }

      // ä¸ºæ¯ä¸ªwishlisté¡¹ç›®å•ç‹¬èŽ·å–å•†å“ä¿¡æ¯
      final result = <Map<String, dynamic>>[];
      for (final wishlistItem in wishlistData) {
        final listingId = wishlistItem['listing_id'];
        if (listingId != null) {
          try {
            final listing = await _client
                .from('listings')
                .select(
                    'id, title, price, city, images, image_urls, status, is_active, seller_name, category, description')
                .eq('id', listingId)
                .eq('is_active', true)
                .maybeSingle();

            if (listing != null) {
              result.add({
                'id': wishlistItem['id'],
                'created_at': wishlistItem['created_at'],
                'listing_id': listingId,
                'listings': listing,
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
      _debugPrint('Error getting user wishlist: $e');
      return [];
    }
  }

  /// èŽ·å–ç”¨æˆ·çš„wishlistå•†å“åˆ—è¡¨ï¼ˆç®€å•ç‰ˆæœ¬ï¼Œä¸å…³è”æŸ¥è¯¢ï¼‰
  static Future<List<Map<String, dynamic>>> getUserWishlistSimple({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      _debugPrint(
          'Getting user wishlist simple: userId=$userId, limit=$limit, offset=$offset');

      final data = await _client
          .from(_tableName)
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final result = List<Map<String, dynamic>>.from(data);
      _debugPrint('Got ${result.length} wishlist items');
      return result;
    } catch (e) {
      _debugPrint('Error getting user wishlist simple: $e');
      return [];
    }
  }

  /// åˆ‡æ¢wishlistçŠ¶æ€ï¼ˆæ·»åŠ æˆ–ç§»é™¤ï¼‰
  static Future<bool> toggleWishlist({
    required String userId,
    required String listingId,
  }) async {
    try {
      _debugPrint('Toggling wishlist: userId=$userId, listingId=$listingId');

      // å…ˆæ£€æŸ¥å½“å‰çŠ¶æ€
      final isCurrentlyInWishlist = await isInWishlist(
        userId: userId,
        listingId: listingId,
      );

      _debugPrint('Currently in wishlist: $isCurrentlyInWishlist');

      bool success;
      if (isCurrentlyInWishlist) {
        // å¦‚æžœå·²åœ¨wishlistä¸­ï¼Œåˆ™ç§»é™¤
        success = await removeFromWishlist(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('Remove operation success: $success');
        return success
            ? false
            : isCurrentlyInWishlist; // æˆåŠŸç§»é™¤è¿”å›žfalse
      } else {
        // å¦‚æžœä¸åœ¨wishlistä¸­ï¼Œåˆ™æ·»åŠ
        success = await addToWishlist(
          userId: userId,
          listingId: listingId,
        );
        _debugPrint('Add operation success: $success');
        return success ? true : isCurrentlyInWishlist; // æˆåŠŸæ·»åŠ è¿”å›žtrue
      }
    } catch (e) {
      _debugPrint('Error toggling wishlist: $e');
      // å¦‚æžœå‡ºé”™ï¼Œè¿”å›žå½“å‰çŠ¶æ€ä¸å˜
      return await isInWishlist(userId: userId, listingId: listingId);
    }
  }

  /// èŽ·å–ç”¨æˆ·wishlistæ•°é‡çš„ä¾¿æ·æ–¹æ³•
  static Future<int> getUserWishlistCount(String userId) async {
    return await getWishlistCount(userId: userId);
  }

  /// æ‰¹é‡åˆ é™¤ç”¨æˆ·çš„wishlisté¡¹ï¼ˆå¯é€‰åŠŸèƒ½ï¼‰
  static Future<bool> clearUserWishlist({required String userId}) async {
    try {
      _debugPrint('Clearing wishlist for user: $userId');

      await _client.from(_tableName).delete().eq('user_id', userId);

      _debugPrint('Successfully cleared wishlist');
      return true;
    } catch (e) {
      _debugPrint('Error clearing wishlist: $e');
      return false;
    }
  }

  /// æµ‹è¯•æ•°æ®åº“è¿žæŽ¥å’Œæƒé™
  static Future<bool> testConnection({required String userId}) async {
    try {
      _debugPrint('Testing wishlist database connection...');

      // å°è¯•è¯»å–ç”¨æˆ·çš„wishlist
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
}
