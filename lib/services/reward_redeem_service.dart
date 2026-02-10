import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/edge_functions_client.dart';

class RewardRedeemService {
  RewardRedeemService._();
  static final I = RewardRedeemService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// 调用 Edge Function：airtime-redeem(phone, points, campaign)
  /// 返回: { ok, request_id, new_points, points_spent }
  Future<Map<String, dynamic>> redeemAirtime({
    required String phone,
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
      // 获取用户手机号（如果未提供）
      String userPhone = phone;
      if (userPhone.isEmpty) {
        final profile = await _sb
            .from('profiles')
            .select('phone')
            .eq('id', userId)
            .maybeSingle();
        userPhone = profile?['phone'] as String? ?? '';
      }

      if (userPhone.isEmpty) {
        return {
          'ok': false,
          'error': 'phone_required',
          'message': 'Phone number required. Please set your phone number in profile.',
        };
      }

      // 调用 Edge Function（新格式）
      final resp = await EdgeFunctionsClient.instance.call('airtime-redeem', body: {
        'phone': userPhone,
        'points': points,
        'campaign': campaignCode,
      });

      // Edge Function 返回格式处理
      if (resp is List && resp.isNotEmpty) {
        final row = resp.first;
        if (row is Map) return Map<String, dynamic>.from(row);
      }
      if (resp is Map) return Map<String, dynamic>.from(resp);

      return {
        'ok': false,
        'error': 'unexpected_response',
        'message': 'Edge Function returned: ${resp.runtimeType}',
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
