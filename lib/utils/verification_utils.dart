import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/verification_types.dart';

/// 兼容写法：既支持传 verificationRow（推荐），也兼容老代码传 profileRow。
/// 我们只看两种字段：
/// - verification_type: text（非 'none' 即视为已认证）
/// - email_verified_at: timestamptz（非空即视为已认证）
bool computeIsVerified({
  Map<String, dynamic>? verificationRow,
  Map<String, dynamic>? profileRow, // 兼容旧调用
  User? user, // 保留签名，实际不用
}) {
  final row = verificationRow ?? profileRow;

  if (row?['email_verified_at'] != null) return true;

  final vt = VerificationBadgeUtil.fromRaw(
    row?['verification_type']?.toString(),
  );
  return VerificationBadgeUtil.isVerifiedType(vt);
}

/// 徽章类型计算：verification_type 优先；否则 email_verified_at 则返回 verified；否则 none
VerificationBadgeType computeBadgeType({
  Map<String, dynamic>? verificationRow,
  Map<String, dynamic>? profileRow, // 兼容旧调用
  User? user, // 保留签名，实际不用
}) {
  final row = verificationRow ?? profileRow;

  final vt = VerificationBadgeUtil.fromRaw(
    row?['verification_type']?.toString(),
  );
  if (vt != VerificationBadgeType.none) return vt;

  if (row?['email_verified_at'] != null) {
    return VerificationBadgeType.verified;
  }
  return VerificationBadgeType.none;
}
