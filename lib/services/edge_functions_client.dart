// lib/services/edge_functions_client.dart
// Edge Functions 统一调用封装
// 替代原有的 rpc() 直调，避免权限错误 (42501)
// ✅ 兼容不支持 InvokeFunctionOptions / options: 的 supabase_flutter 版本

import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class EdgeFunctionsClient {
  EdgeFunctionsClient._();
  static final EdgeFunctionsClient instance = EdgeFunctionsClient._();
  static final EdgeFunctionsClient i = instance;
  factory EdgeFunctionsClient() => instance;

  SupabaseClient get _sb => Supabase.instance.client;

  /// 调用 Edge Function
  /// [functionName] 函数名（不含路径，如 'reward-redeem'）
  /// [body] 请求体（Map/List/基础类型）
  /// [requireAuth] 是否要求 JWT（默认 true）
  /// [timeoutSeconds] 超时时间（默认 30 秒）
  /// [retryCount] 重试次数（默认 1 次）
  Future<dynamic> call(
      String functionName, {
        dynamic body = const {},
        bool requireAuth = true,
        int timeoutSeconds = 30,
        int retryCount = 1,
      }) async {
    final stopwatch = Stopwatch()..start();
    int attempt = 0;
    Object? lastError;

    while (attempt <= retryCount) {
      attempt++;
      try {
        final session = _sb.auth.currentSession;
        final accessToken = session?.accessToken;

        if (requireAuth && (accessToken == null || accessToken.isEmpty)) {
          throw Exception('用户未登录，无法调用 Edge Function: $functionName');
        }

        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (accessToken != null && accessToken.isNotEmpty)
            'Authorization': 'Bearer $accessToken',
        };

        // supabase_flutter 的 invoke 在不同版本中：
        // - 有的 body 接受 String
        // - 有的可接受 Map，但为兼容性统一用 jsonEncode
        final encodedBody = jsonEncode(body);

        final response = await _sb.functions
            .invoke(
          functionName,
          body: encodedBody,
          headers: headers,
        )
            .timeout(Duration(seconds: timeoutSeconds));

        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;

        // ✅ 兼容不同版本的 response 结构：用 dynamic 读取 status（若存在）
        int? status;
        try {
          status = (response as dynamic).status as int?;
        } catch (_) {
          status = null;
        }

        // data 可能是 Map / List / String / null
        dynamic data = response.data;

        // 如果 data 是 String，尽量 jsonDecode 成 Map/List
        if (data is String && data.isNotEmpty) {
          try {
            data = jsonDecode(data);
          } catch (_) {
            // 保留原字符串
          }
        }

        // 如果能取到 status，就做一次更严格的 2xx 检查；取不到就直接认为成功（由后端返回 ok 字段兜底）
        if (status != null && (status < 200 || status >= 300)) {
          final errorMsg =
              'Edge Function $functionName 返回 $status: ${response.data}';
          print('[EdgeFunctionsClient] ❌ $errorMsg');
          throw Exception(errorMsg);
        }

        print('[EdgeFunctionsClient] ✅ $functionName (${elapsedMs}ms)');
        return data;
      } on TimeoutException catch (e) {
        lastError = e;
        print('[EdgeFunctionsClient] ⏰ $functionName 超时 (尝试 $attempt/${retryCount + 1})');
        if (attempt > retryCount) {
          throw Exception('Edge Function $functionName 调用超时');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        lastError = e;
        print('[EdgeFunctionsClient] ❌ $functionName 错误: $e');
        if (attempt > retryCount) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    throw Exception('Edge Function $functionName 调用失败: ${lastError ?? '未知错误'}');
  }

  /// 批量调用（顺序执行）
  Future<List<dynamic>> callBatch(
      List<Map<String, dynamic>> calls, {
        bool requireAuth = true,
      }) async {
    final results = <dynamic>[];
    for (final call in calls) {
      final result = await this.call(
        call['function'] as String,
        body: call['body'] ?? {},
        requireAuth: requireAuth,
      );
      results.add(result);
    }
    return results;
  }

  /// 调用 RPC 代理（统一入口）
  /// [action] RPC 函数名
  /// [params] RPC 参数
  /// [requireAuth] 是否需要认证（默认 true）
  Future<dynamic> rpcProxy(
      String action, {
        Map<String, dynamic> params = const {},
        bool requireAuth = true,
      }) async {
    final response = await call(
      'rpc-proxy',
      body: {
        'action': action,
        'params': params,
      },
      requireAuth: requireAuth,
    );

    // rpc-proxy 返回格式: { ok: true, data: ... } 或 { ok: false, error: ... }
    if (response is Map && response['ok'] == true) {
      return response['data'];
    } else if (response is Map && response['ok'] == false) {
      final error = response['error'];
      final msg = (error is Map) ? (error['message'] ?? '未知错误') : '未知错误';
      throw Exception('RPC代理错误: $msg');
    }

    return response;
  }
}

// 快捷访问
EdgeFunctionsClient get edgeFunctions => EdgeFunctionsClient.instance;