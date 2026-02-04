import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/rewards/reward_api.dart';
import 'package:uuid/uuid.dart';

class RewardAfterPublish {
  RewardAfterPublish._();
  static final RewardAfterPublish I = RewardAfterPublish._();

  final Set<String> _pending = <String>{};
  final Set<String> _consumed = <String>{}; // 幂等：同一个 listing 只触发一次

  void markPending(String listingId) {
    _pending.add(listingId);
  }

  bool consumeIfPending(String listingId) {
    if (_consumed.contains(listingId)) return false;
    final ok = _pending.remove(listingId);
    if (ok) _consumed.add(listingId);
    return ok;
  }

  Future<Map<String, dynamic>> fetchReward(String listingId) async {
    final deviceFp = await _getOrCreateDeviceFingerprint();
    final api = RewardApi(Supabase.instance.client);
    return await api.rewardOnListingPublished(
      listingId: listingId,
      deviceId: deviceFp,
    );
  }

  Future<Map<String, dynamic>> spin({
    required String requestId,
    String campaignCode = 'launch_v1',
    String? listingId,
  }) async {
    final deviceFp = await _getOrCreateDeviceFingerprint();
    final api = RewardApi(Supabase.instance.client);
    return await api.spin(
      requestId: requestId,
      campaignCode: campaignCode,
      listingId: listingId,
      deviceId: deviceFp,
    );
  }

  Future<String> _getOrCreateDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'device_fingerprint_v1';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = const Uuid().v4();
    await prefs.setString(key, newId);
    return newId;
  }
}
