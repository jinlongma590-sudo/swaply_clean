// lib/auth/register_screen.dart
// ✅ 增强版：添加网络错误检测和友好提示
// ✅ 最终修复：使用 ValueListenableBuilder 监听 OAuthEntry.inFlightNotifier
// ✅ 解决按钮锁死问题：当用户点返回时，UI 会立即响应 inFlight 变化
// ✅ [新增] 监听 App 生命周期，从后台返回时自动清理 OAuth 状态
// ✅ [关键修复] 移除 OAuth 超时限制 - OAuth 是用户交互流程，不应强制超时
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/router/root_nav.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/config/auth_config.dart';
import 'dart:async';
import 'dart:io'; // ✅ 用于网络错误检测

class RegisterScreen extends StatefulWidget {
  final String? invitationCode;
  const RegisterScreen({super.key, this.invitationCode});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();

  static String? pendingInvitationCode;
  static void clearPendingCode() => pendingInvitationCode = null;
}

class _RegisterScreenState extends State<RegisterScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _busy = false;
  bool _agreeToTerms = false;
  bool _showInvitationCode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final code = widget.invitationCode;
    if (code != null && code.isNotEmpty) {
      _invitationCodeController.text = code;
      _showInvitationCode = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OAuthEntry.cancelIfInFlight();

    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  // ========== ✅ 网络错误检测工具（与登录页相同） ==========

  /// 判断是否为网络相关错误
  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (error is SocketException) return true;
    if (error is TimeoutException) return true;

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

    return 'Network error. Please check your connection and try again.';
  }

  /// 显示增强的网络错误提示 - 匹配UI风格
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

  // ========== ✅ 核心修复：移除 OAuth 超时限制 ==========

  /// 统一 OAuth 启动器（移除超时限制）
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
      // ✅ 移除超时限制 - OAuth 是用户交互流程，不应强制超时
      await OAuthEntry.signIn(
        provider,
        queryParams: {
          if (queryParams != null) ...queryParams,
          'display': 'popup',
        },
      );
    } catch (e, st) {
      OAuthEntry.finish();
      debugPrint('[Register._oauthSignIn] error: $e');
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

  Future<void> _maybeBindInviteCode(String? code) async {
    if (code == null || code.trim().isEmpty) return;
    final normalized = code.trim().toUpperCase();
    RegisterScreen.pendingInvitationCode = normalized;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await RewardService.submitInviteCode(normalized);
        RegisterScreen.clearPendingCode();
      } catch (_) {
        // ignore
      }
    }
  }

  String? _pickCodeFromUI() {
    final fromRoute = widget.invitationCode?.trim().toUpperCase();
    if (fromRoute != null && fromRoute.isNotEmpty) return fromRoute;

    final fromField = _invitationCodeController.text.trim().toUpperCase();
    if (fromField.isNotEmpty) return fromField;

    return null;
  }

  Future<void> _register() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || !_agreeToTerms) {
      if (!_agreeToTerms) {
        _showError('Please agree to Terms of Service and Privacy Policy');
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final code = _pickCodeFromUI();
      if (code != null) RegisterScreen.pendingInvitationCode = code;

      final fullName = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final supa = Supabase.instance.client;

      final res = await supa.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kAuthRedirectUri,
        data: {
          'full_name': fullName,
          'phone': phone,
        },
      );

      if (res.session == null) {
        _showInfo('Verification email sent. Please check your inbox.');
      } else {
        _showInfo('Account created.');
      }
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
      debugPrint('[Register] SocketException: $e');
    } on TimeoutException catch (e) {
      // ✅ 专门捕获超时异常
      _showNetworkError('Connection timeout. Please try again.');
      debugPrint('[Register] TimeoutException: $e');
    } catch (e) {
      // ✅ 其他错误的通用检查
      if (_isNetworkError(e)) {
        _showNetworkError(_getNetworkErrorMessage(e));
      } else {
        _showError('Register failed: $e');
      }
      debugPrint('[Register] Generic error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleRegister() async {
    if (OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.google,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> _facebookRegister() async {
    if (OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.facebook,
      queryParams: const {'display': 'popup'},
    );
  }

  Future<void> _appleRegister() async {
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

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
        margin: EdgeInsets.all(16.r),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showApple =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        navPop();
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
            onPressed: () => navPop(),
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
                    'Create Account',
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'Sign up to get started with Swaply',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 28.h),
                  _input(
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    icon: Icons.person_outline,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 14.h),
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
                    controller: _phoneController,
                    label: 'Phone Number',
                    hint: 'Enter your phone number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your phone number';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 14.h),
                  _input(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Create a password',
                    icon: Icons.lock_outline,
                    obscureText: !_isPasswordVisible,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter a password';
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
                  SizedBox(height: 14.h),
                  _input(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_outline,
                    obscureText: !_isConfirmPasswordVisible,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey[600],
                        size: 18.r,
                      ),
                      onPressed: () {
                        setState(() {
                          _isConfirmPasswordVisible =
                              !_isConfirmPasswordVisible;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 14.h),
                  _invitationCodeCard(),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      SizedBox(
                        width: 18.w,
                        height: 18.h,
                        child: Checkbox(
                          value: _agreeToTerms,
                          activeColor: const Color(0xFF2196F3),
                          onChanged: (v) {
                            setState(() => _agreeToTerms = v ?? false);
                          },
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Wrap(
                          children: [
                            Text(
                              'I agree to the ',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey[700],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                // TODO: 显示服务条款
                              },
                              child: Text(
                                'Terms of Service',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: const Color(0xFF2196F3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              ' and ',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey[700],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                // TODO: 显示隐私政策
                              },
                              child: Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: const Color(0xFF2196F3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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
                          gradient: (_isLoading || isOAuthInFlight)
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF2196F3),
                                    Color(0xFF1976D2),
                                  ],
                                ),
                          color: (_isLoading || isOAuthInFlight)
                              ? Colors.grey[300]
                              : null,
                          boxShadow: (_isLoading || isOAuthInFlight)
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
                          onTap:
                              _isLoading || isOAuthInFlight ? null : _register,
                          child: Center(
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : Text(
                                    'Create Account',
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
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12.sp),
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
                              _googleRegister,
                              disabled: isOAuthInFlight,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _socialBtn(
                              'Facebook',
                              Colors.blue[800]!,
                              Icons.facebook,
                              _facebookRegister,
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
                        return _appleSignInButtonIOS(disabled: isOAuthInFlight);
                      },
                    ),
                  SizedBox(height: 22.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12.sp),
                      ),
                      GestureDetector(
                        onTap: () => navPop(),
                        child: Text(
                          'Sign In',
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

  Widget _invitationCodeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _showInvitationCode = !_showInvitationCode),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(12.r),
              bottom: _showInvitationCode ? Radius.zero : Radius.circular(12.r),
            ),
            child: Padding(
              padding: EdgeInsets.all(12.r),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Icon(
                      Icons.card_giftcard,
                      color: const Color(0xFF2196F3),
                      size: 18.r,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Have an invitation code?',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          "Get extra rewards with friend's invitation",
                          style: TextStyle(
                              fontSize: 11.sp, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showInvitationCode ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                    size: 20.r,
                  ),
                ],
              ),
            ),
          ),
          if (_showInvitationCode)
            Column(
              children: [
                Divider(height: 1, color: Colors.grey[200]),
                Padding(
                  padding: EdgeInsets.all(12.r),
                  child: TextFormField(
                    controller: _invitationCodeController,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter invitation code',
                      hintStyle:
                          TextStyle(fontSize: 12.sp, color: Colors.grey[400]),
                      prefixIcon: Icon(
                        Icons.vpn_key,
                        size: 18.r,
                        color: const Color(0xFF2196F3),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2196F3).withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                    ),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) {
                        return 'Invalid invitation code format';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
        ],
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
            child: Icon(
              icon,
              color: const Color(0xFF2196F3),
              size: 18.r,
            ),
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
          contentPadding:
              EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
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

  Widget _appleSignInButtonIOS({bool disabled = false}) {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: ElevatedButton(
        onPressed: disabled ? null : _appleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          padding: EdgeInsets.symmetric(horizontal: 12.w),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.apple, size: 20),
            SizedBox(width: 8),
            const Text(
              'Sign in with Apple',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
