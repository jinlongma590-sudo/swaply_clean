// lib/services/notification_service.dart - 修复版（Token 管理使用 upsert）
// ✅ [关键修复] 使用 upsert 避免 delete+insert 的竞态条件
// ✅ [推送通知] 集成 Firebase Cloud Messaging
// ✅ [自我通知过滤] 过滤自己发给自己的通知
// ✅ [Offer消息修复] 实现createOfferNotification以在通知中显示message

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  // ======= ✅ UI 单一数据源（页面只监听它） =======
  static final ValueNotifier<List<Map<String, dynamic>>> listNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(const []);

  static final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  static final ValueNotifier<bool> loadingNotifier = ValueNotifier<bool>(false);

  static void _setList(List<Map<String, dynamic>> list) {
    // 只保留未删除
    final filtered = list.where((e) => e['is_deleted'] != true).toList();
    listNotifier.value = List<Map<String, dynamic>>.unmodifiable(filtered);
    unreadCountNotifier.value =
        filtered.where((n) => n['is_read'] != true).length;
  }

  static void _upsertLocal(Map<String, dynamic> record,
      {bool bumpToTop = false}) {
    final id = (record['id'] ?? '').toString();
    if (id.isEmpty) return;

    // deleted => 移除
    if (record['is_deleted'] == true) {
      _removeLocalById(id);
      return;
    }

    final cur = List<Map<String, dynamic>>.from(listNotifier.value);
    final idx = cur.indexWhere((e) => (e['id'] ?? '').toString() == id);

    if (idx >= 0) {
      // 合并覆盖
      cur[idx] = {...cur[idx], ...record};
      if (bumpToTop && idx > 0) {
        final item = cur.removeAt(idx);
        cur.insert(0, item);
      }
    } else {
      cur.insert(0, record);
    }

    _setList(cur);
  }

  static void _removeLocalById(String id) {
    final cur = List<Map<String, dynamic>>.from(listNotifier.value);
    cur.removeWhere((e) => (e['id'] ?? '').toString() == id);
    _setDictUnread(cur);
  }

  static void _setDictUnread(List<Map<String, dynamic>> cur) {
    listNotifier.value = List<Map<String, dynamic>>.unmodifiable(cur);
    unreadCountNotifier.value = cur
        .where((n) => n['is_deleted'] != true && n['is_read'] != true)
        .length;
  }

  static Future<void> refresh({
    String? userId,
    int limit = 100,
    int offset = 0,
    bool includeRead = true,
  }) async {
    final uid = userId ?? _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    loadingNotifier.value = true;
    try {
      final list = await getUserNotifications(
        userId: uid,
        limit: limit,
        offset: offset,
        includeRead: includeRead,
      );
      _setList(list);
    } finally {
      loadingNotifier.value = false;
    }
  }

  // ======= ✅ 修改：统一深链 payload 构造器（改为 HTTPS） =======
  static String buildOfferPayload({
    required String offerId,
    required String listingId,
  }) =>
      'https://swaply.cc/offer?id=$offerId&listing_id=$listingId';

  static String buildListingPayload({
    required String listingId,
  }) =>
      'https://swaply.cc/listing?id=$listingId';

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

      final listingId =
          (record['listing_id'] ?? meta['listing_id'])?.toString();
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

  // ================================================
  // ✅ [Token 管理修复] FCM Token 管理
  // ✅ [关键修复] 使用 upsert 避免竞态条件
  // ================================================

  static Future<void> initializeFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final user = _client.auth.currentUser;
      if (user == null) {
        _debugPrint('FCM: 用户未登录，跳过 Token 保存');
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        _debugPrint('FCM: Token 为空（可能在模拟器上运行）');
        return;
      }

      _debugPrint('FCM: Token 获取成功，准备保存');

      await _saveFcmToken(token);

      messaging.onTokenRefresh.listen((newToken) {
        _debugPrint('FCM: Token 刷新: $newToken');
        _saveFcmToken(newToken);
      });

      _debugPrint('FCM: 初始化完成');
    } catch (e, st) {
      _debugPrint('FCM: 初始化失败: $e\n$st');
    }
  }

  /// ✅ [关键修复] 使用 upsert 避免竞态条件
  /// 确保一个 user_id + platform 组合只有一个 token
  static Future<void> _saveFcmToken(String token) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        _debugPrint('FCM: 无法保存 Token，用户未登录');
        return;
      }

      final platform = Platform.isIOS ? 'ios' : 'android';

      _debugPrint('FCM: 保存 Token 开始');
      _debugPrint('  用户: ${user.id}');
      _debugPrint('  平台: $platform');
      _debugPrint('  Token: ${token.substring(0, 20)}...');

      // ✅ 使用 upsert 自动处理冲突
      // onConflict 指定为 'user_id,platform'，匹配你的 unique constraint
      await _client.from('user_fcm_tokens').upsert(
        {
          'user_id': user.id,
          'fcm_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,platform', // 关键：指定冲突键
      );

      _debugPrint('FCM: ✅ Token 已保存/更新 (upsert)');
    } catch (e, st) {
      _debugPrint('FCM: ❌ Token 保存失败: $e\n$st');
    }
  }

  /// ✅ [修复] 删除当前用户的所有 token
  static Future<void> removeFcmToken() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        _debugPrint('FCM: 无法删除 Token，用户未登录');
        return;
      }

      final platform = Platform.isIOS ? 'ios' : 'android';

      _debugPrint('FCM: 删除 Token (user_id=${user.id}, platform=$platform)');

      // 删除当前用户 + 平台的 token
      await _client
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('platform', platform);

      _debugPrint('FCM: ✅ Token 已从 Supabase 删除');
    } catch (e, st) {
      _debugPrint('FCM: ❌ Token 删除失败: $e\n$st');
    }
  }

  // ================================================
  // ✅ [架构兼容] 订阅用户通知
  // ✅ 新增：过滤自己发给自己的通知
  // ================================================

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

        // ✅ 新增：过滤自己发给自己的通知
        final senderId = (data['sender_id'] ?? '').toString();
        final recipientId = (data['recipient_id'] ?? '').toString();

        if (senderId.isNotEmpty &&
            recipientId.isNotEmpty &&
            senderId == recipientId) {
          _debugPrint('⚠️ 跳过自己发送的通知: ${data['id']}');
          _debugPrint('  Sender: $senderId');
          _debugPrint('  Recipient: $recipientId');
          return;
        }

        final id = (data['id'] ?? '').toString();
        if (id.isNotEmpty) {
          if (_seenIds.contains(id)) return;
          _seenIds.add(id);
        }

        _debugPrint('New notification received: $data');

        // ✅ 更新本地列表
        _upsertLocal(data, bumpToTop: true);

        if (onEvent != null) onEvent(data);
        _controller.add(data);
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

        // ✅ 更新本地列表
        _upsertLocal(data, bumpToTop: false);

        _controller.add(data);
      },
    );

    ch.subscribe();
    _channel = ch;
    _debugPrint('Subscribed to notifications for user: $userId');

    await initializeFCM();
  }

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

    await removeFcmToken();
  }

  // ========== ✅ 安全 RPC：收藏后通知（命名参数版） ==========
  static Future<bool> notifyFavorite({
    required String sellerId,
    required String listingId,
    required String listingTitle,
    String? likerId,
    String? likerName,
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
            'payload': payload,
            'deep_link': payload,
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
    _debugPrint('createMessageNotification skipped (RPC not implemented)');
    return true;
  }

  /// ✅ [Offer消息修复] 实现createOfferNotification以在通知中显示message
  static Future<bool> createOfferNotification({
    required String sellerId,
    required String buyerId,
    required String offerId,
    required String listingId,
    required double offerAmount,
    required String listingTitle,
    String? buyerName,
    String? buyerPhone,
    String? message,
  }) async {
    try {
      // 自己给自己发offer就不发通知
      if (sellerId == buyerId) {
        _debugPrint('skip self offer notification');
        return true;
      }

      final displayName = (buyerName?.trim().isNotEmpty == true)
          ? buyerName!.trim()
          : 'A buyer';

      // ✅ 构建包含消息的通知内容
      String notificationMessage;
      if (message != null && message.isNotEmpty) {
        notificationMessage =
            '$displayName offered \$${offerAmount.toStringAsFixed(2)}\n\n"$message"';
      } else {
        notificationMessage =
            '$displayName offered \$${offerAmount.toStringAsFixed(2)}';
      }

      // 构建payload
      final String payload = buildOfferPayload(
        offerId: offerId,
        listingId: listingId,
      );

      // 插入通知
      await _client.from(_tableName).insert({
        'recipient_id': sellerId,
        'sender_id': buyerId,
        'type': 'offer',
        'title': 'New Offer Received',
        'message': notificationMessage,
        'offer_id': int.tryParse(offerId),
        'listing_id': listingId,
        'metadata': {
          'amount': offerAmount,
          'status': 'pending',
          'listing_title': listingTitle,
          'buyer_name': displayName,
          if (message != null && message.isNotEmpty) 'buyer_message': message,
          'payload': payload,
          'deep_link': payload,
        },
      });

      _debugPrint('✅ Offer notification created with message');
      return true;
    } catch (e, st) {
      _debugPrint('❌ Failed to create offer notification: $e\n$st');
      return false;
    }
  }

  static Future<bool> createWishlistNotification({
    required String sellerId,
    required String likerId,
    required String listingId,
    required String listingTitle,
    String? likerName,
  }) async {
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
          .or('is_deleted.is.null,is_deleted.eq.false');

      if (!includeRead) {
        query = query.eq('is_read', false);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // ✅ 新增：过滤查询结果中自己发给自己的通知
      final filtered = (data as List).where((item) {
        final senderId = (item['sender_id'] ?? '').toString();
        final recipientId = (item['recipient_id'] ?? '').toString();

        // 跳过自己发给自己的
        if (senderId.isNotEmpty &&
            recipientId.isNotEmpty &&
            senderId == recipientId) {
          return false;
        }
        return true;
      }).toList();

      return List<Map<String, dynamic>>.from(
        filtered.map((e) => Map<String, dynamic>.from(e)),
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
          .select('id, sender_id, recipient_id')
          .eq('recipient_id', targetUserId)
          .eq('is_read', false)
          .eq('is_deleted', false);

      // ✅ 新增：过滤自己发给自己的通知
      final filtered = (data as List).where((item) {
        final senderId = (item['sender_id'] ?? '').toString();
        final recipientId = (item['recipient_id'] ?? '').toString();

        if (senderId.isNotEmpty &&
            recipientId.isNotEmpty &&
            senderId == recipientId) {
          return false;
        }
        return true;
      }).toList();

      return filtered.length;
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

      _upsertLocal({
        'id': notificationId,
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      });

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

      final cur = List<Map<String, dynamic>>.from(listNotifier.value);
      for (var n in cur) {
        n['is_read'] = true;
        n['read_at'] = DateTime.now().toIso8601String();
      }
      _setList(cur);

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

      _removeLocalById(notificationId);

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

      _setList([]);

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
