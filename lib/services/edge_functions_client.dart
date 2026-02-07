// lib/services/edge_functions_client.dart
// Edge Functions 统一调用封装
// 替代原有的 rpc() 直调，避免权限错误 (42501)

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class EdgeFunctionsClient {
  EdgeFunctionsClient._();
  static final EdgeFunctionsClient instance = EdgeFunctionsClient._();
  static final EdgeFunctionsClient i = instance;
  factory EdgeFunctionsClient() => instance;

  SupabaseClient get _sb => Supabase.instance.client;

  /// 调用 Edge Function
  /// [functionName] 函数名（不含路径，如 'reward-redeem'）
  /// [body] 请求体（Map 或 List）
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
    Exception? lastException;

    while (attempt <= retryCount) {
      attempt++;
      try {
        if (requireAuth && _sb.auth.currentSession == null) {
          throw Exception('用户未登录，无法调用 Edge Function: $functionName');
        }

        final options = InvokeFunctionOptions(
          body: body,
          headers: {'Content-Type': 'application/json'},
        );

        final response = await _sb.functions
            .invoke(functionName, options: options)
            .timeout(Duration(seconds: timeoutSeconds));

        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;

        // 检查响应状态
        if (response.status >= 200 && response.status < 300) {
          final data = response.data;
          print('[EdgeFunctionsClient] ✅ $functionName (${elapsedMs}ms)');
          return data;
        } else {
          final errorMsg = 'Edge Function $functionName 返回 ${response.status}: ${response.data}';
          print('[EdgeFunctionsClient] ❌ $errorMsg');
          throw Exception(errorMsg);
        }
      } on TimeoutException catch (e) {
        lastException = e;
        print('[EdgeFunctionsClient] ⏰ $functionName 超时 (尝试 $attempt/$retryCount)');
        if (attempt > retryCount) {
          throw Exception('Edge Function $functionName 调用超时');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        lastException = e as Exception?;
        print('[EdgeFunctionsClient] ❌ $functionName 错误: $e');
        if (attempt > retryCount) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 所有重试失败
    throw lastException ?? Exception('Edge Function $functionName 调用失败');
  }

  /// 批量调用（顺序执行）
  Future<List<dynamic>> callBatch(
    List<Map<String, dynamic>> calls, {
    bool requireAuth = true,
  }) async {
    final results = <dynamic>[];
    for (final call in calls) {
      final result = await this.call(
        call['function'],
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
      throw Exception('RPC代理错误: ${error['message'] ?? '未知错误'}');
    }
    
    return response;
  }
}

// 快捷访问
EdgeFunctionsClient get edgeFunctions => EdgeFunctionsClient.instance;