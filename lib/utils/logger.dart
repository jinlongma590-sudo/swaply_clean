// lib/utils/logger.dart - 日志系统
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 日志级别
enum LogLevel { debug, info, warn, error }

/// 应用日志器
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  static const String _logTag = 'SWAPLY';
  static bool _enableRemoteLogging = false;

  /// 初始化日志系统
  static void init({bool enableRemoteLogging = false}) {
    _enableRemoteLogging = enableRemoteLogging;
    info('日志系统初始化完成', data: {'remote_logging': enableRemoteLogging});
  }

  static void debug(String message,
          {Map<String, dynamic>? data, String? tag}) =>
      _log(LogLevel.debug, message, data: data, tag: tag);

  static void info(String message, {Map<String, dynamic>? data, String? tag}) =>
      _log(LogLevel.info, message, data: data, tag: tag);

  static void warn(String message, {Map<String, dynamic>? data, String? tag}) =>
      _log(LogLevel.warn, message, data: data, tag: tag);

  static void error(String message,
      {dynamic error,
      StackTrace? stackTrace,
      Map<String, dynamic>? data,
      String? tag}) {
    final errorData = {
      ...?data,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };
    _log(LogLevel.error, message, data: errorData, tag: tag);
  }

  static void userAction(String action,
      {String? userId, Map<String, dynamic>? data}) {
    info('用户行为: $action',
        data: {
          'user_id': userId,
          'action': action,
          'timestamp': DateTime.now().toIso8601String(),
          ...?data,
        },
        tag: 'USER_ACTION');
  }

  static void businessEvent(String event,
      {String? userId, Map<String, dynamic>? data}) {
    info('业务事件: $event',
        data: {
          'user_id': userId,
          'event': event,
          'timestamp': DateTime.now().toIso8601String(),
          ...?data,
        },
        tag: 'BUSINESS');
  }

  static void performance(String operation,
      {required Duration duration, Map<String, dynamic>? data}) {
    info('性能监控: $operation',
        data: {
          'operation': operation,
          'duration_ms': duration.inMilliseconds,
          'timestamp': DateTime.now().toIso8601String(),
          ...?data,
        },
        tag: 'PERFORMANCE');
  }

  static void _log(LogLevel level, String message,
      {Map<String, dynamic>? data, String? tag}) {
    final timestamp = DateTime.now().toIso8601String();
    final logTag = tag ?? _logTag;
    final levelStr = level.toString().split('.').last.toUpperCase();

    final logInfo = {
      'timestamp': timestamp,
      'level': levelStr,
      'tag': logTag,
      'message': message,
      if (data != null && data.isNotEmpty) 'data': data,
    };

    if (kDebugMode) {
      final logStr = _formatLogForConsole(logInfo, level);
      print(logStr);
    }

    if (_enableRemoteLogging && !kDebugMode) {
      _sendLogToRemote(logInfo, level);
    }
  }

  static String _formatLogForConsole(
      Map<String, dynamic> logInfo, LogLevel level) {
    final timestamp = logInfo['timestamp'];
    final tag = logInfo['tag'];
    final levelStr = logInfo['level'];
    final message = logInfo['message'];
    final data = logInfo['data'];

    final buffer = StringBuffer();

    switch (level) {
      case LogLevel.debug:
        buffer.write('\x1B[36m'); // 青
        break;
      case LogLevel.info:
        buffer.write('\x1B[32m'); // 绿
        break;
      case LogLevel.warn:
        buffer.write('\x1B[33m'); // 黄
        break;
      case LogLevel.error:
        buffer.write('\x1B[31m'); // 红
        break;
    }

    buffer.write('[$timestamp] [$levelStr] [$tag] $message');

    if (data != null) {
      try {
        final dataStr = const JsonEncoder.withIndent('  ').convert(data);
        buffer.write('\n  Data: $dataStr');
      } catch (_) {
        buffer.write('\n  Data: ${data.toString()}');
      }
    }

    buffer.write('\x1B[0m'); // 重置颜色
    return buffer.toString();
  }

  static void _sendLogToRemote(Map<String, dynamic> logInfo, LogLevel level) {
    try {
      if (level.index < LogLevel.warn.index) return;

      final user = Supabase.instance.client.auth.currentUser;

      Future.microtask(() async {
        try {
          await Supabase.instance.client.from('system_logs').insert({
            'log_type': 'client_log',
            'log_level': logInfo['level'].toString().toLowerCase(),
            'message': logInfo['message'],
            'metadata': {
              'tag': logInfo['tag'],
              'data': logInfo['data'],
              'platform': 'flutter',
              'timestamp': logInfo['timestamp'],
            },
            'user_id': user?.id,
          });
        } catch (e) {
          if (kDebugMode) {
            print('远程日志记录失败: $e');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('日志系统内部错误: $e');
      }
    }
  }

  static Future<void> clearLogs() async {
    info('清理本地日志');
  }

  static Map<String, int> getLogStats() {
    return {'total_logs': 0, 'error_logs': 0, 'warn_logs': 0};
  }
}
