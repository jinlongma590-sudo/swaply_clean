import 'package:supabase_flutter/supabase_flutter.dart';

class RewardRedeemService {
  RewardRedeemService._();
  static final I = RewardRedeemService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// 调用 RPC：public.reward_redeem_airtime(p_user, p_campaign, p_points)
  /// 返回: { ok, new_points, redemption_id, status }
  Future<Map<String, dynamic>> redeemAirtime({
    required String campaignCode,
    required int points,
  }) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return {
        'ok': false,
        'error': 'not_authenticated',
        'message': 'User not logged in.',
      };
    }

    try {
      final resp = await _sb.rpc('reward_redeem_airtime', params: {
        'p_user': userId,
        'p_campaign': campaignCode,
        'p_points': points,
      });

      // supabase rpc 可能返回 List 或 Map，做兼容
      if (resp is List && resp.isNotEmpty) {
        final row = resp.first;
        if (row is Map) return Map<String, dynamic>.from(row);
      }
      if (resp is Map) return Map<String, dynamic>.from(resp);

      return {
        'ok': false,
        'error': 'unexpected_response',
        'message': 'RPC returned: ${resp.runtimeType}',
      };
    } catch (e) {
      return {
        'ok': false,
        'error': 'exception',
        'message': e.toString(),
      };
    }
  }
}
