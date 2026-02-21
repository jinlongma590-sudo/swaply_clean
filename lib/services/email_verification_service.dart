import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/edge_functions_client.dart';

class EmailVerificationService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ---------------- 工具：统一解析 ----------------
  bool _isOk(dynamic d) {
    if (d is Map) {
      final ok = d['ok'];
      final success = d['success'];
      return ok == true || success == true;
    }
    if (d is String) {
      try {
        final m = jsonDecode(d);
        if (m is Map) {
          final ok = m['ok'];
          final success = m['success'];
          return ok == true || success == true;
        }
      } catch (_) {}
    }
    return false;
  }

  Map<String, dynamic>? _asMap(dynamic d) {
    if (d == null) return null;
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String) {
      try {
        final m = jsonDecode(d);
        if (m is Map<String, dynamic>) return m;
        if (m is Map) return Map<String, dynamic>.from(m);
      } catch (_) {}
    }
    return null;
  }

  // ---------------- 发送验证码 ----------------
  /// 发送验证码（云函数：send-verification-email）
  Future<bool> sendVerificationCode(String email) async {
    final payload = {'email': email.trim()};
    try {
      // ignore: avoid_print
      print('[EV] send payload = ${jsonEncode(payload)}');

      final res = await _sb.functions.invoke(
        'send-verification-email',
        body: payload,
      );

      // ignore: avoid_print
      print('[EV] send status=${res.status} data=${res.data}');

      if (res.status != 200) return false;
      return _isOk(res.data);
    } catch (e) {
      // ignore: avoid_print
      print('[EV] send error: $e');
      return false;
    }
  }

  // ---------------- 校验验证码（详细版 + 兜底 RPC） ----------------
  /// 详细版：返回 ok/status/reason/raw，便于排障
  Future<VerifyResponse> verifyCodeDetailed({
    required String email,
    required String code,
  }) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        return const VerifyResponse(
          ok: false,
          status: 0,
          reason: 'no_user_id',
          raw: {'message': 'Not logged in or uid missing'},
        );
      }

      final payload = {
        'email': email.trim(),
        'code': code.trim(),
        'user_id': uid, // 关键：必须传
      };

      // ignore: avoid_print
      print('[EV] verify payload = ${jsonEncode(payload)}');

      final res = await _sb.functions.invoke(
        'verify-email-code',
        body: payload,
      );

      final rawMap = _asMap(res.data);
      final reason = rawMap?['reason']?.toString();

      // ignore: avoid_print
      print('[EV] verify status=${res.status} data=${res.data}');

      final ok = res.status == 200 && _isOk(res.data);

      // ✅ 兜底：如果云函数返回成功，立刻在客户端直呼 RPC 写入/更新 user_verifications
      if (ok) {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        try {
          final rpc = await EdgeFunctionsClient.instance.rpcProxy('upsert_user_verification', params: {
            'p_user_id': uid,
            'p_email': email.trim(),
            'p_verified_at': nowIso,
            'p_method': 'email_code',
            'p_badge': 'verified',
          });
          // ignore: avoid_print
          print('[EV] client RPC upsert result: $rpc');
        } catch (e) {
          // ignore: avoid_print
          print('[EV] client RPC upsert error: $e');
        }
      }

      return VerifyResponse(
        ok: ok,
        status: res.status,
        reason: reason,
        raw: rawMap ?? {'data': res.data},
      );
    } catch (e) {
      // ignore: avoid_print
      print('[EV] verify error: $e');
      return VerifyResponse(
        ok: false,
        status: -1,
        reason: 'exception',
        raw: {'error': e.toString()},
      );
    }
  }

  /// 兼容旧调用：仅返回 bool（内部委托 detailed）
  Future<bool> verifyCode({required String email, required String code}) async {
    final r = await verifyCodeDetailed(email: email, code: code);
    return r.ok;
  }

  // ---------------- 查询认证行 ----------------
  /// 读取"本人"的验证状态（优先 user_verifications，若无则回退到 profiles 表）
  Future<Map<String, dynamic>?> fetchVerificationRow() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      // 1. 优先查询 user_verifications 表
      final dynamic uvRow = await _sb
          .from('user_verifications')
          .select('email, email_verified_at, verification_type, updated_at')
          .eq('user_id', uid)
          .maybeSingle();

      // ignore: avoid_print
      print('[EV] fetchVerificationRow (user_verifications) -> $uvRow');

      if (uvRow != null) {
        return _asMap(uvRow);
      }

      // 2. user_verifications 无记录，回退到 profiles 表
      print('[EV] user_verifications empty, fallback to profiles');
      final dynamic profileRow = await _sb
          .from('profiles')
          .select('email, verification_type, is_verified, updated_at')
          .eq('id', uid)
          .maybeSingle();

      print('[EV] fetchVerificationRow (profiles) -> $profileRow');

      if (profileRow != null) {
        final Map<String, dynamic>? map = _asMap(profileRow);
        if (map != null) {
          // 转换 profiles 字段为兼容格式
          return {
            'email': map['email'],
            'verification_type': map['verification_type'],
            // profiles 表可能没有 email_verified_at，但如果有 verification_type='verified' 就足够
            'email_verified_at': null, // 明确设为 null
            'updated_at': map['updated_at'],
            '_source': 'profiles', // 标记来源
          };
        }
      }

      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[EV] fetchVerificationRow error: $e');
      return null;
    }
  }

  /// 公开读取"任意用户（卖家）"的认证展示字段（通过 Edge Function RPC 代理）
  Future<Map<String, dynamic>?> fetchPublicVerification(String userId) async {
    try {
      final dynamic result = await EdgeFunctionsClient.instance.rpcProxy('get_user_verification_public',
          params: {'target': userId});
      // rpcProxy 返回的是 RPC 的直接结果，可能是 null、Map 或 List
      return _asMap(result);
    } catch (e) {
      // ignore: avoid_print
      print('[EV] fetchPublicVerification error: $e');
      return null;
    }
  }

  // ---------- 兼容旧页面调用的别名 ----------
  Future<Map<String, dynamic>?> fetchMyVerificationRow() =>
      fetchVerificationRow();

  Future<bool> verifyWithCode({required String email, required String code}) =>
      verifyCode(email: email, code: code);

  Future<bool> sendCode(String email) => sendVerificationCode(email);
}

/// 用于详细返回的简单结构
class VerifyResponse {
  final bool ok;
  final int status;
  final String? reason;
  final Map<String, dynamic>? raw;

  const VerifyResponse({
    required this.ok,
    required this.status,
    this.reason,
    this.raw,
  });

  @override
  String toString() =>
      'VerifyResponse(ok=$ok, status=$status, reason=$reason, raw=$raw)';
}
