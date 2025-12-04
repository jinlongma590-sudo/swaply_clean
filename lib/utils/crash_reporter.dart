// lib/utils/crash_reporter.dart - 崩溃报告系统
// 提供 PlatformDispatcher
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/utils/logger.dart';

/// 崩溃报告器
class CrashReporter {
  static bool _isInitialized = false;

  /// 初始化崩溃报告系统
  static void init() {
    if (_isInitialized) return;

    // 捕获 Flutter 错误
    FlutterError.onError = (FlutterErrorDetails details) {
      _handleFlutterError(details);
    };

    // 捕获平台错误
    PlatformDispatcher.instance.onError = (error, stack) {
      _handlePlatformError(error, stack);
      return true;
    };

    _isInitialized = true;
    AppLogger.info('崩溃报告系统初始化完成');
  }

  /// 处理 Flutter 错误
  static void _handleFlutterError(FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    }

    AppLogger.error(
      'Flutter错误: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
      data: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
      tag: 'FLUTTER_ERROR',
    );

    _sendCrashReport(
      type: 'flutter_error',
      error: details.exception,
      stackTrace: details.stack,
      additionalInfo: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
  }

  /// 处理平台错误
  static void _handlePlatformError(Object error, StackTrace stackTrace) {
    AppLogger.error(
      '平台错误: $error',
      error: error,
      stackTrace: stackTrace,
      tag: 'PLATFORM_ERROR',
    );

    _sendCrashReport(
      type: 'platform_error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 手动报告错误
  static void reportError(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    Map<String, dynamic>? additionalInfo,
  }) {
    AppLogger.error(
      '手动报告错误: ${reason ?? error.toString()}',
      error: error,
      stackTrace: stackTrace,
      data: additionalInfo,
      tag: 'MANUAL_REPORT',
    );

    _sendCrashReport(
      type: 'manual_report',
      error: error,
      stackTrace: stackTrace,
      reason: reason,
      additionalInfo: additionalInfo,
    );
  }

  /// 发送崩溃报告到远程服务
  static void _sendCrashReport({
    required String type,
    required dynamic error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, dynamic>? additionalInfo,
  }) {
    Future.microtask(() async {
      try {
        final user = Supabase.instance.client.auth.currentUser;

        await Supabase.instance.client.from('system_logs').insert({
          'log_type': 'crash_report',
          'log_level': 'error',
          'message': reason ?? 'Application crash: ${error.toString()}',
          'metadata': {
            'crash_type': type,
            'error': error.toString(),
            'stack_trace': stackTrace?.toString(),
            'additional_info': additionalInfo,
            'timestamp': DateTime.now().toIso8601String(),
            'platform': 'flutter',
          },
          'user_id': user?.id,
        });
      } catch (e) {
        if (kDebugMode) {
          print('发送崩溃报告失败: $e');
        }
      }
    });
  }
}
