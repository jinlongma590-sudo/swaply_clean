// lib/auth/login_screen.dart
// ✅ 增强版：添加网络错误检测和友好提示
// ✅ 最终修复：使用 ValueListenableBuilder 监听 OAuthEntry.inFlightNotifier
// ✅ 解决按钮锁死问题：当用户点返回时，UI 会立即响应 inFlight 变化
// ✅ [修复] 登录页返回按钮跳转到 welcome 而不是 navPop（避免栈底页面无法返回）
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/router/root_nav.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:io'; // ✅ 新增：用于网络错误检测

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OAuthEntry.cancelIfInFlight();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ========== ✅ 新增：网络错误检测工具 ==========

  /// 判断是否为网络相关错误
  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Socket 异常
    if (error is SocketException) return true;

    // 超时异常
    if (error is TimeoutException) return true;

    // 常见网络错误关键词
    final networkKeywords = [
      'connection',
      'network',
      'socket',
      'timeout',
      'reset by peer',
      'connection refused',
      'connection reset',
      'failed host lookup',
      'no internet',
      'unreachable',
    ];

    return networkKeywords.any((keyword) => errorStr.contains(keyword));
  }

  /// 获取友好的网络错误提示
  String _getNetworkErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('timeout')) {
      return 'Connection timeout. Please check your network and try again.';
    }

    if (errorStr.contains('connection refused') ||
        errorStr.contains('connection reset')) {
      return 'Unable to connect to server. Please check your network.';
    }

    if (errorStr.contains('failed host lookup') ||
        errorStr.contains('no internet')) {
      return 'No internet connection. Please check your network settings.';
    }

    // 默认网络错误提示
    return 'Network error. Please check your connection and try again.';
  }

  /// 显示增强的网络错误提示 - 匹配您的UI风格
  void _showNetworkError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.r),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                color: Colors.white,
                size: 18.r,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network Error',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
        margin: EdgeInsets.all(16.r),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            // 用户可以点击重试
          },
        ),
      ),
    );
  }

  // ========== 原有方法增强版 ==========

  Future<void> _oauthSignIn(
      OAuthProvider provider, {
        Map<String, String>? queryParams,
      }) async {
    if (!mounted || _busy) return;

    if (!OAuthEntry.mayStartInteractive()) {
      OAuthEntry.forceCancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Canceled. Tap again to retry')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await OAuthEntry.signIn(
        provider,
        queryParams: {
          if (queryParams != null) ...queryParams,
          'display': 'popup',
        },
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      OAuthEntry.finish();
      debugPrint('[Login._oauthSignIn] timeout/canceled');
      if (mounted) {
        // ✅ 使用新的网络错误提示
        _showNetworkError('Login timeout. Please try again.');
      }
    } catch (e, st) {
      OAuthEntry.finish();
      debugPrint('[Login._oauthSignIn] error: $e');
      debugPrint(st.toString());

      if (mounted) {
        // ✅ 区分网络错误和其他错误
        if (_isNetworkError(e)) {
          _showNetworkError(_getNetworkErrorMessage(e));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sign-in failed: ${e.toString()}'),
              backgroundColor: Colors.red[400],
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginEmailPassword() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _busy || OAuthEntry.inFlight) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      // ✅ 检查是否为网络导致的认证错误
      if (_isNetworkError(e)) {
        _showNetworkError(_getNetworkErrorMessage(e));
      } else {
        _showError(e.message);
      }
    } on SocketException catch (e) {
      // ✅ 专门捕获 Socket 异常
      _showNetworkError('Unable to connect. Please check your network.');
      debugPrint('[Login] SocketException: $e');
    } on TimeoutException catch (e) {
      // ✅ 专门捕获超时异常
      _showNetworkError('Connection timeout. Please try again.');
      debugPrint('[Login] TimeoutException: $e');
    } catch (e) {
      // ✅ 其他错误的通用检查
      if (_isNetworkError(e)) {
        _showNetworkError(_getNetworkErrorMessage(e));
      } else {
        _showError('Login failed. Please try again.');
      }
      debugPrint('[Login] Generic error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.google,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> _handleFacebookLogin() async {
    if (OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.facebook,
      queryParams: const {'display': 'popup'},
    );
  }

  Future<void> _handleAppleLogin() async {
    if (OAuthEntry.inFlight) return;
    await _oauthSignIn(OAuthProvider.apple);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
        margin: EdgeInsets.all(16.r),
      ),
    );
  }

  void _goBack() {
    OAuthEntry.cancelIfInFlight();
    if (mounted) setState(() => _busy = false);
    navReplaceAll('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final bool showApple =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: Colors.grey[800],
              size: 20.r,
            ),
            onPressed: _goBack,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),
                  Text(
                    'Welcome Back!',
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'Sign in to continue to Swaply',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 28.h),

                  _input(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'Enter your email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 14.h),

                  _input(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscureText: !_isPasswordVisible,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (v.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey[600],
                        size: 18.r,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),

                  SizedBox(height: 10.h),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18.w,
                            height: 18.h,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: const Color(0xFF2196F3),
                              onChanged: (v) {
                                setState(() => _rememberMe = v ?? false);
                              },
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          // TODO: 忘记密码
                        },
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: const Color(0xFF2196F3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20.h),

                  ValueListenableBuilder<bool>(
                    valueListenable: OAuthEntry.inFlightNotifier,
                    builder: (context, isOAuthInFlight, child) {
                      return Container(
                        height: 44.h,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.r),
                          gradient: (_busy || isOAuthInFlight)
                              ? null
                              : const LinearGradient(
                            colors: [
                              Color(0xFF2196F3),
                              Color(0xFF1976D2),
                            ],
                          ),
                          color: (_busy || isOAuthInFlight)
                              ? Colors.grey[300]
                              : null,
                          boxShadow: (_busy || isOAuthInFlight)
                              ? null
                              : [
                            BoxShadow(
                              color: const Color(0xFF2196F3)
                                  .withOpacity(0.3),
                              blurRadius: 8.r,
                              offset: Offset(0, 4.h),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: _busy || isOAuthInFlight ? null : _loginEmailPassword,
                          child: Center(
                            child: _busy
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                              'Sign In',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: 18.h),

                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        child: Text(
                          'OR',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12.sp),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ],
                  ),

                  SizedBox(height: 18.h),

                  ValueListenableBuilder<bool>(
                    valueListenable: OAuthEntry.inFlightNotifier,
                    builder: (context, isOAuthInFlight, child) {
                      return Row(
                        children: [
                          Expanded(
                            child: _socialBtn(
                              'Google',
                              Colors.red[600]!,
                              Icons.g_mobiledata,
                              _handleGoogleLogin,
                              disabled: isOAuthInFlight,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _socialBtn(
                              'Facebook',
                              Colors.blue[800]!,
                              Icons.facebook,
                              _handleFacebookLogin,
                              disabled: isOAuthInFlight,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  if (showApple) SizedBox(height: 12.h),
                  if (showApple)
                    ValueListenableBuilder<bool>(
                      valueListenable: OAuthEntry.inFlightNotifier,
                      builder: (context, isOAuthInFlight, child) {
                        return _appleSignInButton(disabled: isOAuthInFlight);
                      },
                    ),

                  SizedBox(height: 22.h),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
                      ),
                      GestureDetector(
                        onTap: () => navPush('/register'),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: const Color(0xFF2196F3),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        style: TextStyle(fontSize: 14.sp),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
          prefixIcon: Padding(
            padding: EdgeInsets.all(10.r),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 18.r),
          ),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF2196F3), width: 1.5),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        ),
      ),
    );
  }

  Widget _socialBtn(
      String text,
      Color color,
      IconData icon,
      Future<void> Function() onTap, {
        bool disabled = false,
      }) {
    return SizedBox(
      height: 42.h,
      child: OutlinedButton(
        onPressed: disabled ? null : () => onTap(),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[200]!),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18.r),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appleSignInButton({bool disabled = false}) {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: ElevatedButton(
        onPressed: disabled ? null : _handleAppleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          padding: EdgeInsets.symmetric(horizontal: 12.w),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.apple, size: 20),
            SizedBox(width: 8),
            Text('Sign in with Apple', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
