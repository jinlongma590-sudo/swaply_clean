// lib/services/public_profile_service.dart
// 公开资料查询服务 - 用于读取脱敏的 public_profiles 视图
// 替代原有的公开读 profiles 表，避免权限错误 (401)

import 'package:supabase_flutter/supabase_flutter.dart';

class PublicProfileService {
  PublicProfileService._();
  static final PublicProfileService instance = PublicProfileService._();
  static final PublicProfileService i = instance;
  factory PublicProfileService() => instance;

  SupabaseClient get _sb => Supabase.instance.client;

  /// 获取单个公开资料（通过用户ID）
  /// 返回字段：id, full_name, avatar_url, created_at, updated_at,
  ///          is_official, verification_status, is_business, 
  ///          is_premium, verification_type
  Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    try {
      final response = await _sb
          .from('public_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response as Map<String, dynamic>?;
    } catch (e) {
      // 如果视图不存在或查询失败，返回null（UI层应处理）
      print('[PublicProfileService] Error fetching public profile: $e');
      return null;
    }
  }

  /// 批量获取公开资料（通过用户ID列表）
  Future<List<Map<String, dynamic>>> getPublicProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    try {
      final response = await _sb
          .from('public_profiles')
          .select()
          .in('id', userIds);
      return (response as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      print('[PublicProfileService] Error fetching public profiles: $e');
      return [];
    }
  }

  /// 搜索公开资料（按名称）
  Future<List<Map<String, dynamic>>> searchPublicProfiles(String query) async {
    try {
      final response = await _sb
          .from('public_profiles')
          .select()
          .ilike('full_name', '%$query%')
          .limit(20);
      return (response as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      print('[PublicProfileService] Error searching public profiles: $e');
      return [];
    }
  }

  /// 直接查询公开资料视图（原始查询，用于复杂筛选）
  /// 示例：.from('public_profiles').select().eq('is_business', true)
  SupabaseQueryBuilder fromPublicProfiles() {
    return _sb.from('public_profiles');
  }
}