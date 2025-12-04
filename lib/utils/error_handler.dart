// lib/utils/error_handler.dart - 统一错误处理系统
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/utils/logger.dart';

/// 错误类型枚举
enum ErrorType {
  network, // 网络错误
  auth, // 认证错误
  validation, // 验证错误
  business, // 业务逻辑错误
  system, // 系统错误
  unknown, // 未知错误
}

/// 自定义应用异常类
class AppException implements Exception {
  final String message;
  final ErrorType type;
  final String? code;
  final Map<String, dynamic>? details;
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    required this.type,
    this.code,
    this.details,
    this.stackTrace,
  });

  factory AppException.network(String message, {String? code}) =>
      AppException(message: message, type: ErrorType.network, code: code);

  factory AppException.auth(String message, {String? code}) =>
      AppException(message: message, type: ErrorType.auth, code: code);

  factory AppException.validation(String message, {String? code}) =>
      AppException(message: message, type: ErrorType.validation, code: code);

  factory AppException.business(String message,
          {String? code, Map<String, dynamic>? details}) =>
      AppException(
          message: message,
          type: ErrorType.business,
          code: code,
          details: details);

  factory AppException.system(String message,
          {String? code, StackTrace? stackTrace}) =>
      AppException(
          message: message,
          type: ErrorType.system,
          code: code,
          stackTrace: stackTrace);

  @override
  String toString() =>
      'AppException(type: $type, message: $message, code: $code)';
}

/// 全局错误处理器
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  /// 处理异常并返回用户友好的错误信息
  static AppException handleError(dynamic error, {StackTrace? stackTrace}) {
    AppLogger.error('处理异常', error: error, stackTrace: stackTrace);

    if (error is AppException) return error;
    if (error is AuthException) return _handleAuthException(error);
    if (error is PostgrestException) return _handlePostgrestException(error);
    if (error is StorageException) return _handleStorageException(error);

    // 其他类型的错误
    return AppException.system(
      _getGenericErrorMessage(error),
      stackTrace: stackTrace,
    );
  }

  /// 处理认证异常
  static AppException _handleAuthException(AuthException error) {
    final code = error.statusCode;
    final msg = error.message.toLowerCase();

    String message;
    switch (msg) {
      case 'invalid login credentials':
        message = '登录凭证无效，请检查邮箱和密码';
        break;
      case 'email not confirmed':
        message = '请先验证邮箱后再登录';
        break;
      case 'signup disabled':
        message = '注册功能暂时关闭，请稍后再试';
        break;
      case 'user not found':
        message = '用户不存在';
        break;
      case 'weak password':
        message = '密码强度不够，请使用更复杂的密码';
        break;
      case 'email already exists':
        message = '该邮箱已被注册';
        break;
      default:
        message = '认证失败: ${error.message}';
    }
    return AppException.auth(message, code: code);
  }

  /// 处理数据库异常
  static AppException _handlePostgrestException(PostgrestException error) {
    final code = error.code;
    String message;
    switch (code) {
      case '23505': // 唯一性约束违反
        message = error.message.contains('duplicate key')
            ? '数据已存在，请勿重复操作'
            : '数据冲突，请重试';
        break;
      case '23503': // 外键约束违反
        message = '相关数据不存在，操作失败';
        break;
      case '42501': // 权限不足
        message = '权限不足，无法执行此操作';
        break;
      case 'PGRST116': // 行级安全策略违反
        message = '安全策略限制，无法访问此数据';
        break;
      default:
        message = '数据操作失败: ${error.message}';
    }
    return AppException.business(message, code: code);
  }

  /// 处理存储异常
  static AppException _handleStorageException(StorageException error) {
    final code = error.statusCode;
    final msg = error.message.toLowerCase();

    String message;
    switch (msg) {
      case 'bucket not found':
        message = '存储桶不存在';
        break;
      case 'object not found':
        message = '文件不存在';
        break;
      case 'upload failed':
        message = '文件上传失败，请重试';
        break;
      case 'file too large':
        message = '文件过大，请选择更小的文件';
        break;
      default:
        message = '文件操作失败: ${error.message}';
    }
    return AppException.system(message, code: code);
  }

  /// 获取通用错误信息
  static String _getGenericErrorMessage(dynamic error) {
    final s = error.toString();
    if (s.contains('SocketException')) return '网络连接失败，请检查网络设置';
    if (s.contains('TimeoutException')) return '操作超时，请重试';
    if (s.contains('FormatException')) return '数据格式错误';
    return '系统错误，请稍后重试';
  }

  /// 在 UI 中显示错误
  static void showError(BuildContext context, dynamic error,
      {VoidCallback? onRetry}) {
    final appError = handleError(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _buildErrorSnackBar(appError),
        backgroundColor: _getErrorColor(appError.type),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(16.r),
        duration: Duration(seconds: appError.type == ErrorType.system ? 5 : 3),
        action: onRetry != null
            ? SnackBarAction(
                label: '重试',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// 构建错误显示内容
  static Widget _buildErrorSnackBar(AppException error) {
    return Row(
      children: [
        Icon(_getErrorIcon(error.type), color: Colors.white, size: 20.r),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getErrorTitle(error.type),
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              Text(
                error.message,
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withValues(alpha: 0.9)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Color _getErrorColor(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return Colors.orange[600]!;
      case ErrorType.auth:
        return Colors.red[600]!;
      case ErrorType.validation:
        return Colors.amber[600]!;
      case ErrorType.business:
        return Colors.blue[600]!;
      case ErrorType.system:
        return Colors.red[700]!;
      case ErrorType.unknown:
        return Colors.grey[600]!;
    }
  }

  static IconData _getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.auth:
        return Icons.lock;
      case ErrorType.validation:
        return Icons.warning;
      case ErrorType.business:
        return Icons.info;
      case ErrorType.system:
        return Icons.error;
      case ErrorType.unknown:
        return Icons.help;
    }
  }

  static String _getErrorTitle(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return '网络错误';
      case ErrorType.auth:
        return '认证错误';
      case ErrorType.validation:
        return '输入错误';
      case ErrorType.business:
        return '业务错误';
      case ErrorType.system:
        return '系统错误';
      case ErrorType.unknown:
        return '未知错误';
    }
  }
}
