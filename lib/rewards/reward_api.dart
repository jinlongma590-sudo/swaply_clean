import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class RewardApi {
  RewardApi(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> rewardOnListingPublished({
    required String listingId,
    String? deviceId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    final resp = await _client.functions.invoke(
      'reward-on-listing-published',
      body: {
        'listing_id': listingId,
        if (deviceId != null) 'device_id': deviceId,
      },
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return {'ok': false, 'error': 'Unknown response type'};
  }

  /// ✅ 新增：spin
  Future<Map<String, dynamic>> spin({
    required String requestId,
    String campaignCode = 'launch_v1',
    String? listingId,
    String? deviceId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    final resp = await _client.functions.invoke(
      'reward-spin',
      body: {
        'request_id': requestId,
        'campaign_code': campaignCode,
        if (listingId != null) 'listing_id': listingId,
        if (deviceId != null) 'device_id': deviceId,
      },
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return {'ok': false, 'error': 'Unknown response type'};
  }
}
