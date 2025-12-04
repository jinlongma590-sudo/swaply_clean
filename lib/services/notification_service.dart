// lib/services/notification_service.dart
// 单例 + 全局广播流；“收藏后通知”走 RPC（notify_favorite）以绕过 RLS。

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationEventCallback = void Function(
    Map<String, dynamic> notification,
    );

enum NotificationType {
  offer('offer'),
  wishlist('wishlist'),
  system('system'),
  message('message'),
  purchase('purchase'),
  priceDrop('price_drop');

  const NotificationType(this.value);
  final String value;
}

class NotificationService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _tableName = 'notifications';

  // ======= ✅ 新增：统一深链 payload 构造器 =======
  /// 报价通知 → 直达 OfferDetailPage
  static String buildOfferPayload({
    required String offerId,
    required String listingId,
  }) =>
      'swaply://offer?offer_id=$offerId&listing_id=$listingId';

  /// 商品通知 / 收藏 / 点赞 → 直达 ProductDetailPage
  static String buildListingPayload({
    required String listingId,
  }) =>
      'swaply://listing?listing_id=$listingId';

  // 可选：从一条通知记录里尽最大可能推导 payload（没有就返回 null）
  static String? derivePayloadFromRecord(Map<String, dynamic> record) {
    try {
      final type = (record['type'] ?? '').toString();
      final meta = (record['metadata'] ?? {}) as Map<String, dynamic>;
      final fromMeta = (meta['payload'] ??
          meta['deep_link'] ??
          meta['deeplink'] ??
          meta['link'])
          ?.toString();

      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;

      final listingId = (record['listing_id'] ?? meta['listing_id'])?.toString();
      final offerId = (record['offer_id'] ?? meta['offer_id'])?.toString();

      if (type == 'offer' && offerId != null && listingId != null) {
        return buildOfferPayload(offerId: offerId, listingId: listingId);
      }
      if (listingId != null) {
        return buildListingPayload(listingId: listingId);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
  // ==============================================

  // ===== Realtime 通道状态 =====
  static String? _currentUserId;
  static RealtimeChannel? _channel;

  static bool get isSubscribed => _channel != null && _currentUserId != null;

  // ===== 全局广播流 =====
  static final StreamController<Map<String, dynamic>> _controller =
  StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  // 简单去重，避免同一通知重复推送
  static final Set<String> _seenIds = <String>{};

  static void _debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NotificationService] $message');
    }
  }

  /// 订阅当前用户的通知（幂等）
  static Future<void> subscribeUser(
      String userId, {
        NotificationEventCallback? onEvent,
      }) async {
    if (_currentUserId == userId && _channel != null) {
      _debugPrint('Already subscribed for user: $userId');
      return;
    }

    await unsubscribe();

    _currentUserId = userId;
    final ch = _client.channel('notifications:user:$userId');

    // INSERT：新通知
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: _tableName,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: userId,
      ),
      callback: (payload) {
        final data = Map<String, dynamic>.from(payload.newRecord);

        final id = (data['id'] ?? '').toString();
        if (id.isNotEmpty) {
          if (_seenIds.contains(id)) return;
          _seenIds.add(id);
        }

        _debugPrint('New notification received: $data');

        if (onEvent != null) onEvent(data);
        _controller.add(data); // 全局广播
      },
    );

    // UPDATE：如 is_read 变化时
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: _tableName,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: userId,
      ),
      callback: (payload) {
        final data = Map<String, dynamic>.from(payload.newRecord);
        _controller.add(data);
      },
    );

    ch.subscribe(); // 某些 SDK 不是 Future
    _channel = ch;
    _debugPrint('Subscribed to notifications for user: $userId');
  }

  /// 取消订阅（幂等）
  static Future<void> unsubscribe() async {
    final ch = _channel;
    _channel = null;
    _currentUserId = null;
    _seenIds.clear();

    if (ch != null) {
      try {
        try {
          ch.unsubscribe();
        } catch (_) {}
        try {
          _client.removeChannel(ch);
        } catch (_) {}
        _debugPrint('Unsubscribed from notifications');
      } catch (_) {}
    }
  }

  // ========== ✅ 安全 RPC：收藏后通知（命名参数版） ==========
  /// 使用后端 security definer 函数：public.notify_favorite(...)
  /// 期望的函数参数（推荐）：
  ///   p_recipient_id uuid,
  ///   p_type text,
  ///   p_title text,
  ///   p_message text,
  ///   p_listing_id uuid,
  ///   p_liker_id uuid,
  ///   p_liker_name text,
  ///   p_metadata jsonb
  ///
  /// 如你的后端暂时仍是 `notify_favorite(uuid)`，需要先按上述签名升级函数。
  static Future<bool> notifyFavorite({
    required String sellerId, // 被通知的卖家
    required String listingId, // 商品ID
    required String listingTitle, // 商品标题
    String? likerId, // 收藏者 ID
    String? likerName, // 收藏者显示名
  }) async {
    try {
      final currentUser = _client.auth.currentUser;

      final safeName = (likerName?.trim().isNotEmpty == true)
          ? likerName!.trim()
          : (currentUser?.userMetadata?['full_name'] as String?) ??
          (currentUser?.email ?? 'Someone');

      // 自己收藏自己就不发
      if (sellerId == (likerId ?? currentUser?.id)) {
        _debugPrint('skip self favorite notification');
        return true;
      }

      // ✅ 将深链一并写入 metadata（payload / deep_link 两个 key 都写）
      final String payload = buildListingPayload(listingId: listingId);

      final res = await _client.rpc(
        'notify_favorite',
        params: {
          'p_recipient_id': sellerId,
          'p_type': 'wishlist',
          'p_title': 'Item Added to Wishlist',
          'p_message': '$safeName added your $listingTitle to their wishlist',
          'p_listing_id': listingId,
          'p_liker_id': likerId ?? currentUser?.id,
          'p_liker_name': safeName,
          'p_metadata': {
            'listing_title': listingTitle,
            'liker_name': safeName,
            'payload': payload, // ← 本地通知/点击可直接使用
            'deep_link': payload, // ← 备用字段，便于前端读取
          },
        },
      );

      final ok = res != null;
      if (kDebugMode) {
        // ignore: avoid_print
        print(ok
            ? '[NotificationService] Favorite RPC sent: $listingId -> $sellerId (payload=$payload)'
            : '[NotificationService] Favorite RPC failed (returned null/false)');
      }
      return ok;
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NotificationService] Favorite RPC error: $e\n$st');
      }
      return false;
    }
  }

  // ========== （Legacy）直插入方法占位 ==========
  // 注意：由于 RLS，客户端对 notifications 的 insert 会被拒绝。
  // 因此保留该方法仅作占位，避免旧代码调用时报错；不再执行直插入。
  static Future<Map<String, dynamic>?> createNotification({
    required String recipientId,
    String? senderId,
    required NotificationType type,
    required String title,
    required String message,
    String? listingId,
    String? offerId,
    Map<String, dynamic>? metadata,
  }) async {
    _debugPrint(
        'createNotification skipped for type=${type.value} (use RPC per type)');
    return null;
  }

  // ========== 业务封装：消息 / 出价 / 收藏 / 系统 ==========
  static Future<bool> createMessageNotification({
    required String recipientId,
    required String senderId,
    required String offerId,
    required String senderName,
    required String messageContent,
  }) async {
    // 需要时可新增 notify_message RPC
    _debugPrint('createMessageNotification skipped (RPC not implemented)');
    return true;
  }

  static Future<bool> createOfferNotification({
    required String sellerId,
    required String buyerId,
    required String listingId,
    required double offerAmount,
    required String listingTitle,
    String? buyerName,
    String? buyerPhone,
    String? message,
  }) async {
    // 需要时可新增 notify_offer RPC
    // 提示：若你在别处弹本地通知，请用：
    // final payload = buildOfferPayload(offerId: '<O_ID>', listingId: listingId);
    // 然后把 payload 传给 flutter_local_notifications 的 show(..., payload: payload)
    _debugPrint('createOfferNotification skipped (RPC not implemented)');
    return true;
  }

  static Future<bool> createWishlistNotification({
    required String sellerId,
    required String likerId,
    required String listingId,
    required String listingTitle,
    String? likerName,
  }) async {
    // ✅ 走 RPC，避免 42501
    return await notifyFavorite(
      sellerId: sellerId,
      listingId: listingId,
      listingTitle: listingTitle,
      likerId: likerId,
      likerName: likerName,
    );
  }

  static Future<bool> createSystemNotification({
    required String recipientId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    // 需要时可新增 notify_system RPC
    _debugPrint('createSystemNotification skipped (RPC not implemented)');
    return true;
  }

  // ========== 查询 / 标记 ==========
  static Future<List<Map<String, dynamic>>> getUserNotifications({
    String? userId,
    int limit = 50,
    int offset = 0,
    bool includeRead = true,
  }) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) {
        _debugPrint('No user ID provided');
        return [];
      }

      _debugPrint('Fetching notifications for user: $targetUserId');

      var query = _client
          .from(_tableName)
          .select('*')
          .eq('recipient_id', targetUserId)
          .eq('is_deleted', false);

      if (!includeRead) {
        query = query.eq('is_read', false);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(
        data.map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (e) {
      _debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  static Future<int> getUnreadNotificationsCount({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return 0;

      final data = await _client
          .from(_tableName)
          .select('id')
          .eq('recipient_id', targetUserId)
          .eq('is_read', false)
          .eq('is_deleted', false);

      return (data as List).length;
    } catch (e) {
      _debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  static Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId.isEmpty) return false;

      _debugPrint('Marking notification as read: $notificationId');

      await _client
          .from(_tableName)
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('id', notificationId)
          .eq('recipient_id', currentUserId);

      return true;
    } catch (e) {
      _debugPrint('Error marking notification as read: $e');
      return false;
    }
  }

  static Future<bool> markAllNotificationsAsRead({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return false;

      _debugPrint('Marking all notifications as read for user: $targetUserId');

      await _client
          .from(_tableName)
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('recipient_id', targetUserId)
          .eq('is_read', false);

      return true;
    } catch (e) {
      _debugPrint('Error marking all notifications as read: $e');
      return false;
    }
  }

  static Future<bool> deleteNotification(String notificationId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId.isEmpty) return false;

      _debugPrint('Deleting notification: $notificationId');

      await _client
          .from(_tableName)
          .update({'is_deleted': true})
          .eq('id', notificationId)
          .eq('recipient_id', currentUserId);

      return true;
    } catch (e) {
      _debugPrint('Error deleting notification: $e');
      return false;
    }
  }

  static Future<bool> clearAllNotifications({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return false;

      _debugPrint('Clearing all notifications for user: $targetUserId');

      await _client
          .from(_tableName)
          .update({'is_deleted': true}).eq('recipient_id', targetUserId);

      return true;
    } catch (e) {
      _debugPrint('Error clearing all notifications: $e');
      return false;
    }
  }

  // ========== 辅助 ==========
  static String getNotificationIcon(String type) {
    switch (type) {
      case 'offer':
        return '💰';
      case 'wishlist':
        return '❤️';
      case 'purchase':
        return '🛒';
      case 'message':
        return '💬';
      case 'price_drop':
        return '📉';
      case 'system':
      default:
        return '🔔';
    }
  }

  static int getNotificationColor(String type) {
    switch (type) {
      case 'offer':
        return 0xFF4CAF50;
      case 'wishlist':
        return 0xFFE91E63;
      case 'purchase':
        return 0xFF2196F3;
      case 'message':
        return 0xFFFF9800;
      case 'price_drop':
        return 0xFF9C27B0;
      case 'system':
      default:
        return 0xFF607D8B;
    }
  }

  static String formatNotificationTime(String createdAt) {
    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  static Future<bool> sendWelcomeNotification(String userId) async {
    // 欢迎礼已由 Reward/WelcomeDialog 接管
    _debugPrint('sendWelcomeNotification skipped (use RewardService)');
    return true;
  }

  static Future<bool> testConnection() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return false;
      await getUnreadNotificationsCount(userId: userId);
      return true;
    } catch (e) {
      _debugPrint('Connection test failed: $e');
      return false;
    }
  }
}
