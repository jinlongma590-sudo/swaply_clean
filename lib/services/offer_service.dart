// lib/services/offer_service.dart
// 报价服务 + 举报/屏蔽支持（对齐 reports/blocks 表结构）

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:swaply/models/offer.dart';

/// ===== 顶层声明：屏蔽状态 =====
class BlockStatus {
  final bool iBlockedOther; // 我是否屏蔽了对方
  final bool otherBlockedMe; // 对方是否屏蔽了我
  const BlockStatus(
      {required this.iBlockedOther, required this.otherBlockedMe});
}

/// 报价服务类（附：举报/屏蔽）
class OfferService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _tableName = 'offers';

  // 举报/屏蔽相关表
  static const String _blocksTable = 'blocks';
  static const String _reportsTable = 'reports';

  /// 获取当前用户ID
  static String? get _currentUserId => _client.auth.currentUser?.id;

  /// 调试打印
  static void _debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[OfferService] $message');
    }
  }

  // ====== 查询双方屏蔽状态 ======
  static Future<BlockStatus> getBlockStatusBetween({
    required String a,
    required String b,
  }) async {
    try {
      // 自己和自己：永远不视为拉黑
      if (a == b) {
        _debugPrint(
            'Checking block status for same user ($a). Always unblocked.');
        return const BlockStatus(iBlockedOther: false, otherBlockedMe: false);
      }

      _debugPrint('Checking block status between $a and $b');

      final rows = await _client
          .from(_blocksTable)
          .select('blocker_id, blocked_id')
          .or('and(blocker_id.eq.$a,blocked_id.eq.$b),and(blocker_id.eq.$b,blocked_id.eq.$a)');

      bool aBlockedB = false;
      bool bBlockedA = false;
      for (final row in rows) {
        final blocker = row['blocker_id'] as String?;
        final blocked = row['blocked_id'] as String?;
        if (blocker == a && blocked == b) aBlockedB = true;
        if (blocker == b && blocked == a) bBlockedA = true;
      }

      final me = _currentUserId;
      final iBlockedOther = (me == a) ? aBlockedB : bBlockedA;
      final otherBlockedMe = (me == a) ? bBlockedA : aBlockedB;

      return BlockStatus(
          iBlockedOther: iBlockedOther, otherBlockedMe: otherBlockedMe);
    } catch (e) {
      _debugPrint('Error checking block status: $e');
      return const BlockStatus(iBlockedOther: false, otherBlockedMe: false);
    }
  }

  // ====== 屏蔽 / 取消屏蔽 ======
  static Future<bool> blockUser({required String blockedId}) async {
    try {
      final me = _currentUserId;
      if (me == null) return false;

      // 禁止自我拉黑
      if (blockedId == me) {
        _debugPrint('Cannot block yourself');
        return false;
      }

      _debugPrint('Blocking user: $blockedId');

      final exists = await _client
          .from(_blocksTable)
          .select('blocker_id')
          .eq('blocker_id', me)
          .eq('blocked_id', blockedId)
          .maybeSingle();
      if (exists != null) {
        _debugPrint('Already blocked');
        return true;
      }

      await _client.from(_blocksTable).insert({
        'blocker_id': me,
        'blocked_id': blockedId,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      _debugPrint('Error blocking user: $e');
      return false;
    }
  }

  static Future<bool> unblockUser({required String blockedId}) async {
    try {
      final me = _currentUserId;
      if (me == null) return false;

      // 自己无需解锁
      if (blockedId == me) {
        _debugPrint('No need to unblock yourself');
        return false;
      }

      _debugPrint('Unblocking user: $blockedId');
      await _client
          .from(_blocksTable)
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_id', blockedId);
      return true;
    } catch (e) {
      _debugPrint('Error unblocking user: $e');
      return false;
    }
  }

  // ====== 提交举报 ======
  /// 注意：为兼容你的 reports 表，**同时**写入 `reported_user_id` 与 `reported_id`，
  /// 且使用字段名 `report_type`。`offer_id` 为 bigint，需要传 int。
  static Future<bool> submitReport({
    required String reportedId, // 被举报用户 id（uuid）
    required String type, // Spam/Scam/Harassment/Other
    String? description,
    String? offerId, // 可能是字符串，这里会安全转换成 int?
    String? listingId, // uuid
  }) async {
    try {
      final me = _currentUserId;
      if (me == null) return false;

      // 禁止自我举报
      if (reportedId == me) {
        _debugPrint('Skip self-report');
        return false;
      }

      _debugPrint(
          'Submitting report: type=$type reported=$reportedId offer=$offerId listing=$listingId');

      final int? offerInt =
          (offerId == null || offerId.isEmpty) ? null : int.tryParse(offerId);

      final payload = {
        'reporter_id': me,
        // 同时写入两个列名，向后/向前兼容
        'reported_user_id': reportedId,
        'reported_id': reportedId,
        'report_type': type,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (offerInt != null) 'offer_id': offerInt, // reports.offer_id 为 bigint
        if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      };

      await _client.from(_reportsTable).insert(payload);
      return true;
    } catch (e) {
      _debugPrint('Error submitting report: $e');
      return false;
    }
  }

  // ================== 下面维持你原有的报价逻辑 ==================

  /// 创建新报价
  static Future<Map<String, dynamic>?> createOffer({
    required String listingId,
    required String sellerId,
    required double offerAmount,
    double? originalPrice,
    String? message,
    String? buyerPhone,
    String? buyerName,
    int expiryDays = 7,
  }) async {
    try {
      final buyerId = _currentUserId;
      if (buyerId == null) {
        _debugPrint('No authenticated user found');
        return null;
      }

      // 检查是否已有未处理的报价
      final existingOffer = await _client
          .from(_tableName)
          .select('id')
          .eq('listing_id', listingId)
          .eq('buyer_id', buyerId)
          .eq('status', OfferStatus.pending.value)
          .maybeSingle();

      if (existingOffer != null) {
        _debugPrint('User already has a pending offer for this listing');
        throw Exception('You already have a pending offer for this item');
      }

      _debugPrint('Creating offer: \$$offerAmount for listing $listingId');

      final data = {
        'listing_id': listingId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'offer_amount': offerAmount,
        'original_price': originalPrice,
        'message': message,
        'buyer_phone': buyerPhone,
        'buyer_name': buyerName ?? 'Anonymous',
        'status': OfferStatus.pending.value,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at':
            DateTime.now().add(Duration(days: expiryDays)).toIso8601String(),
      };

      final result =
          await _client.from(_tableName).insert(data).select().single();

      _debugPrint('Offer created successfully: ${result['id']}');
      return result;
    } catch (e) {
      _debugPrint('Error creating offer: $e');
      rethrow;
    }
  }

  /// 更新报价状态
  static Future<bool> updateOfferStatus({
    required String offerId,
    required OfferStatus status,
    String? responseMessage,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        _debugPrint('No authenticated user found');
        return false;
      }

      _debugPrint('Updating offer $offerId status to ${status.value}');

      final updateData = <String, dynamic>{
        'status': status.value,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (responseMessage != null && responseMessage.isNotEmpty) {
        updateData['response_message'] = responseMessage;
      }

      if (status == OfferStatus.accepted || status == OfferStatus.declined) {
        updateData['responded_at'] = DateTime.now().toIso8601String();
      }

      await _client
          .from(_tableName)
          .update(updateData)
          .eq('id', offerId)
          .eq('seller_id', userId); // 只有卖家可以更新状态

      _debugPrint('Offer status updated successfully');
      return true;
    } catch (e) {
      _debugPrint('Error updating offer status: $e');
      return false;
    }
  }

  static Future<bool> acceptOffer(String offerId, {String? message}) async {
    try {
      final success = await updateOfferStatus(
        offerId: offerId,
        status: OfferStatus.accepted,
        responseMessage: message,
      );
      if (success) {
        await _rejectOtherOffers(offerId);
      }
      return success;
    } catch (e) {
      _debugPrint('Error accepting offer: $e');
      return false;
    }
  }

  static Future<bool> declineOffer(String offerId, {String? message}) async {
    return rejectOffer(offerId, reason: message);
  }

  static Future<bool> rejectOffer(String offerId, {String? reason}) async {
    return updateOfferStatus(
      offerId: offerId,
      status: OfferStatus.declined,
      responseMessage: reason,
    );
  }

  static Future<bool> withdrawOffer(String offerId, {String? reason}) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        _debugPrint('No authenticated user found');
        return false;
      }

      _debugPrint('Withdrawing offer: $offerId');

      final updateData = <String, dynamic>{
        'status': OfferStatus.withdrawn.value,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (reason != null && reason.isNotEmpty) {
        updateData['response_message'] = reason;
      }

      await _client
          .from(_tableName)
          .update(updateData)
          .eq('id', offerId)
          .eq('buyer_id', userId);

      _debugPrint('Offer withdrawn successfully');
      return true;
    } catch (e) {
      _debugPrint('Error withdrawing offer: $e');
      return false;
    }
  }

  static Future<void> _rejectOtherOffers(String acceptedOfferId) async {
    try {
      final acceptedOffer = await _client
          .from(_tableName)
          .select('listing_id')
          .eq('id', acceptedOfferId)
          .single();

      final listingId = acceptedOffer['listing_id'];

      await _client
          .from(_tableName)
          .update({
            'status': OfferStatus.declined.value,
            'updated_at': DateTime.now().toIso8601String(),
            'response_message': 'This item has been sold to another buyer.',
          })
          .eq('listing_id', listingId)
          .eq('status', OfferStatus.pending.value)
          .neq('id', acceptedOfferId);

      _debugPrint('Rejected other pending offers for listing: $listingId');
    } catch (e) {
      _debugPrint('Error rejecting other offers: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getListingOffers({
    required String listingId,
    List<OfferStatus>? statusFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        _debugPrint('No authenticated user found');
        return [];
      }

      _debugPrint('Fetching offers for listing: $listingId');

      var query =
          _client.from(_tableName).select('*').eq('listing_id', listingId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        final statusValues = statusFilter.map((s) => s.value).toList();
        query = query.filter('status', 'in', '(${statusValues.join(',')})');
      }

      final List<dynamic> offers =
          await query.order('created_at', ascending: false).range(
                offset,
                offset + limit - 1,
              );

      final enrichedOffers = <Map<String, dynamic>>[];

      for (final offer in offers) {
        final offerMap = Map<String, dynamic>.from(offer);

        try {
          final listing = await _client
              .from('listings')
              .select('id, title, price, images, city')
              .eq('id', listingId)
              .maybeSingle();
          if (listing != null) {
            offerMap['listings'] = listing;
          }
        } catch (e) {
          _debugPrint('Error fetching listing: $e');
        }

        try {
          final buyerId = offerMap['buyer_id'];
          if (buyerId != null) {
            final profile = await _client
                .from('profiles')
                .select('full_name, avatar_url, phone')
                .eq('id', buyerId)
                .maybeSingle();
            if (profile != null) {
              offerMap['buyer_profiles'] = profile;
            }
          }
        } catch (e) {
          _debugPrint('Error fetching buyer profile: $e');
        }

        enrichedOffers.add(offerMap);
      }

      return enrichedOffers;
    } catch (e) {
      _debugPrint('Error fetching listing offers: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserOffers({
    String? userId,
    List<OfferStatus>? statusFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final targetUserId = userId ?? _currentUserId;
      if (targetUserId == null) {
        _debugPrint('No user ID provided');
        return [];
      }

      _debugPrint('Fetching offers for user: $targetUserId');

      var query =
          _client.from(_tableName).select('*').eq('buyer_id', targetUserId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        final statusValues = statusFilter.map((s) => s.value).toList();
        query = query.filter('status', 'in', '(${statusValues.join(',')})');
      }

      final List<dynamic> offers =
          await query.order('created_at', ascending: false).range(
                offset,
                offset + limit - 1,
              );

      final enrichedOffers = <Map<String, dynamic>>[];

      for (final offer in offers) {
        final offerMap = Map<String, dynamic>.from(offer);

        try {
          final listingId = offerMap['listing_id'];
          if (listingId != null) {
            final listing = await _client
                .from('listings')
                .select('id, title, price, images, city')
                .eq('id', listingId)
                .maybeSingle();
            if (listing != null) {
              offerMap['listings'] = listing;
            }
          }
        } catch (e) {
          _debugPrint('Error fetching listing: $e');
        }

        try {
          final sellerId = offerMap['seller_id'];
          if (sellerId != null) {
            final profile = await _client
                .from('profiles')
                .select('full_name, avatar_url, phone')
                .eq('id', sellerId)
                .maybeSingle();
            if (profile != null) {
              offerMap['seller_profiles'] = profile;
            }
          }
        } catch (e) {
          _debugPrint('Error fetching seller profile: $e');
        }

        enrichedOffers.add(offerMap);
      }

      return enrichedOffers;
    } catch (e) {
      _debugPrint('Error fetching user offers: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getReceivedOffers({
    String? userId,
    List<OfferStatus>? statusFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final targetUserId = userId ?? _currentUserId;
      if (targetUserId == null) {
        _debugPrint('No user ID provided');
        return [];
      }

      _debugPrint('Fetching received offers for user: $targetUserId');

      var query =
          _client.from(_tableName).select('*').eq('seller_id', targetUserId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        final statusValues = statusFilter.map((s) => s.value).toList();
        query = query.filter('status', 'in', '(${statusValues.join(',')})');
      }

      final List<dynamic> data =
          await query.order('created_at', ascending: false).range(
                offset,
                offset + limit - 1,
              );

      final enrichedData = <Map<String, dynamic>>[];

      for (final offer in data) {
        final offerMap = Map<String, dynamic>.from(offer);

        try {
          final listingId = offerMap['listing_id'];
          if (listingId != null) {
            final listing = await _client
                .from('listings')
                .select('id, title, price, images, city')
                .eq('id', listingId)
                .maybeSingle();
            if (listing != null) {
              offerMap['listings'] = listing;
            }
          }
        } catch (e) {
          _debugPrint('Error fetching listing for offer ${offerMap['id']}: $e');
        }

        try {
          final buyerId = offerMap['buyer_id'];
          if (buyerId != null) {
            final profile = await _client
                .from('profiles')
                .select('full_name, avatar_url, phone')
                .eq('id', buyerId)
                .maybeSingle();
            if (profile != null) {
              offerMap['buyer_profiles'] = profile;
            }
          }
        } catch (e) {
          _debugPrint(
              'Error fetching buyer profile for offer ${offerMap['id']}: $e');
        }

        enrichedData.add(offerMap);
      }

      return enrichedData;
    } catch (e) {
      _debugPrint('Error fetching received offers: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getOfferDetails(String offerId) async {
    try {
      _debugPrint('Fetching offer details: $offerId');

      final offerData = await _client
          .from(_tableName)
          .select('*')
          .eq('id', offerId)
          .maybeSingle();

      if (offerData == null) {
        _debugPrint('Offer not found: $offerId');
        return null;
      }

      final result = Map<String, dynamic>.from(offerData);

      try {
        final listingId = result['listing_id'];
        if (listingId != null) {
          final listing = await _client
              .from('listings')
              .select('id, title, price, images, city, description')
              .eq('id', listingId)
              .maybeSingle();
          if (listing != null) {
            result['listings'] = listing;
          }
        }
      } catch (e) {
        _debugPrint('Error fetching listing details: $e');
      }

      try {
        final buyerId = result['buyer_id'];
        if (buyerId != null) {
          final buyerProfile = await _client
              .from('profiles')
              .select('full_name, avatar_url, phone')
              .eq('id', buyerId)
              .maybeSingle();
          if (buyerProfile != null) {
            result['buyer_profiles'] = buyerProfile;
          }
        }
      } catch (e) {
        _debugPrint('Error fetching buyer profile: $e');
      }

      try {
        final sellerId = result['seller_id'];
        if (sellerId != null) {
          final sellerProfile = await _client
              .from('profiles')
              .select('full_name, avatar_url, phone')
              .eq('id', sellerId)
              .maybeSingle();
          if (sellerProfile != null) {
            result['seller_profiles'] = sellerProfile;
          }
        }
      } catch (e) {
        _debugPrint('Error fetching seller profile: $e');
      }

      _debugPrint('Fetched offer details successfully');
      return result;
    } catch (e) {
      _debugPrint('Error fetching offer details: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUserPendingOffer({
    required String listingId,
    String? userId,
  }) async {
    try {
      final targetUserId = userId ?? _currentUserId;
      if (targetUserId == null) return null;

      _debugPrint('Checking pending offer for listing: $listingId');

      final data = await _client
          .from(_tableName)
          .select('*')
          .eq('listing_id', listingId)
          .eq('buyer_id', targetUserId)
          .eq('status', OfferStatus.pending.value)
          .maybeSingle();

      if (data != null) {
        _debugPrint('Found pending offer: ${data['id']}');
        return Map<String, dynamic>.from(data);
      }

      return null;
    } catch (e) {
      _debugPrint('Error checking pending offer: $e');
      return null;
    }
  }

  static Future<Map<String, int>> getOfferStats({String? userId}) async {
    try {
      final targetUserId = userId ?? _currentUserId;
      if (targetUserId == null) {
        return {
          'sent_offers': 0,
          'received_offers': 0,
          'pending_sent': 0,
          'pending_received': 0,
          'accepted': 0,
          'declined': 0,
          'expired': 0,
          'withdrawn': 0,
        };
      }

      _debugPrint('Fetching offer stats for user: $targetUserId');

      final sentOffers = await _client
          .from(_tableName)
          .select('status')
          .eq('buyer_id', targetUserId);

      final receivedOffers = await _client
          .from(_tableName)
          .select('status')
          .eq('seller_id', targetUserId);

      final stats = {
        'sent_offers': sentOffers.length,
        'received_offers': receivedOffers.length,
        'pending_sent':
            sentOffers.where((o) => o['status'] == 'pending').length,
        'pending_received':
            receivedOffers.where((o) => o['status'] == 'pending').length,
        'accepted': sentOffers.where((o) => o['status'] == 'accepted').length,
        'declined': sentOffers.where((o) => o['status'] == 'declined').length +
            receivedOffers.where((o) => o['status'] == 'declined').length,
        'expired': sentOffers.where((o) => o['status'] == 'expired').length +
            receivedOffers.where((o) => o['status'] == 'expired').length,
        'withdrawn': sentOffers.where((o) => o['status'] == 'withdrawn').length,
      };

      _debugPrint('Offer stats: $stats');
      return stats;
    } catch (e) {
      _debugPrint('Error fetching offer stats: $e');
      return {};
    }
  }

  static Future<int> markExpiredOffers() async {
    try {
      _debugPrint('Marking expired offers...');

      final result = await _client
          .from(_tableName)
          .update({
            'status': OfferStatus.expired.value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('status', OfferStatus.pending.value)
          .lt('expires_at', DateTime.now().toIso8601String())
          .select('id');

      final expiredCount = (result as List).length;
      _debugPrint('Marked $expiredCount offers as expired');
      return expiredCount;
    } catch (e) {
      _debugPrint('Error marking expired offers: $e');
      return 0;
    }
  }

  static Future<bool> deleteOffer(String offerId) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return false;

      _debugPrint('Deleting offer: $offerId');

      await _client
          .from(_tableName)
          .delete()
          .eq('id', offerId)
          .eq('buyer_id', userId);

      _debugPrint('Offer deleted successfully');
      return true;
    } catch (e) {
      _debugPrint('Error deleting offer: $e');
      return false;
    }
  }

  // ============ 兼容性方法 ============

  static String getStatusDisplayText(String status) =>
      OfferStatus.fromString(status).displayText;

  static int getStatusColor(String status) =>
      OfferStatus.fromString(status).color;

  static String formatOfferTime(String createdAt) {
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

  static double calculateOfferPercentage(
      double offerAmount, double originalPrice) {
    if (originalPrice <= 0) return 0;
    return (offerAmount / originalPrice) * 100;
  }

  static String formatOfferAmount(double amount) {
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(1)}K';
    return '\$${amount.toStringAsFixed(0)}';
  }

  static Future<bool> testConnection() async {
    try {
      _debugPrint('Testing offer service connection...');
      final userId = _currentUserId;
      if (userId == null) {
        _debugPrint('No current user for connection test');
        return false;
      }
      await getOfferStats(userId: userId);
      _debugPrint('Offer service connection test successful');
      return true;
    } catch (e) {
      _debugPrint('Offer service connection test failed: $e');
      return false;
    }
  }
}
