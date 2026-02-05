import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CouponPinningApi {
  CouponPinningApi(this._client);

  final SupabaseClient _client;

  static const Set<String> _allowedScopes = {'category', 'search', 'trending'};

  /// ✅ 兼容 Supabase RPC 可能返回 Map 或 List<Map>
  Map<String, dynamic> _normalizeRpcResponse(dynamic res) {
    if (res is Map<String, dynamic>) return res;

    if (res is List && res.isNotEmpty) {
      final first = res.first;
      if (first is Map) {
        return Map<String, dynamic>.from(first as Map);
      }
    }

    throw Exception('Unexpected response format: ${res.runtimeType} => $res');
  }

  Future<Map<String, dynamic>> useCouponForPinning({
    required String couponId,
    required String listingId,
    String note = 'app',
  }) async {
    try {
      final res = await _client.rpc(
        'use_coupon_for_pinning',
        params: {
          'in_coupon_id': couponId,
          'in_listing_id': listingId,
          'in_note': note,
        },
      );

      return _normalizeRpcResponse(res);
    } catch (e, st) {
      debugPrint('[CouponPinningApi] useCouponForPinning failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// ✅ 查询用户可用于“置顶/boost”的券（不限制来源）
  /// - 降级：查询失败返回 []
  /// - 更严格：类型检查 + pin_scope 统一小写
  Future<List<Map<String, dynamic>>> getUserPinningCoupons() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final response = await _client
          .from('coupons')
          .select('''
        id,
        code,
        type,
        pin_scope,
        pin_days,
        status,
        expires_at,
        used_count,
        max_uses,
        created_at,
        source
      ''')
          .eq('user_id', userId)
          .eq('status', 'active')
          // ✅ 不限制 source：抽奖/活动/邀请/运营发的券都能用
          .gte('expires_at', now)
          .order('created_at', ascending: false);

      if (response is! List) return [];

      final valid = <Map<String, dynamic>>[];

      for (final coupon in response) {
        if (coupon is! Map) continue; // ✅ 类型保护
        final m = Map<String, dynamic>.from(coupon);

        final usedCount = (m['used_count'] as int?) ?? 0;
        final maxUses = (m['max_uses'] as int?) ?? 1;

        final pinScope =
            (m['pin_scope']?.toString() ?? '').trim().toLowerCase(); // ✅ 统一小写
        final pinDays = (m['pin_days'] as num?)?.toInt() ?? 0;

        final scopeOk = _allowedScopes.contains(pinScope);

        if (usedCount < maxUses && scopeOk && pinDays > 0) {
          valid.add(m);
        }
      }

      return valid;
    } catch (e, st) {
      debugPrint('[CouponPinningApi] getUserPinningCoupons failed: $e');
      debugPrint('$st');
      return []; // ✅ 优雅降级，避免页面崩
    }
  }
}
