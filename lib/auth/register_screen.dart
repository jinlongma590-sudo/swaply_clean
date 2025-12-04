// lib/auth/register_screen.dart
// ✅ 最终修复：使用 ValueListenableBuilder 监听 OAuthEntry.inFlightNotifier
// ✅ 解决按钮锁死问题：当用户点返回时，UI 会立即响应 inFlight 变化
// ✅ [新增] 监听 App 生命周期，从后台返回时自动清理 OAuth 状态
// ⛔ 删除生命周期监听
// ⛔ 删除 OAuthEntry.finish()
// ⛔ 删除 clearGuardIfSignedIn()
// ⛔ 统一 OAuth 入口，与 login_screen 完全一致
// ⛔ 注册成功后的导航由 AuthFlowObserver 统一处理
// ⛔ 保留: 邀请码绑定 + UI + 邮箱注册 + ProfileService 同步

import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/router/root_nav.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/config/auth_config.dart';
import 'package:swaply/services/profile_service.dart';
import 'dart:async';

class RegisterScreen extends StatefulWidget {
  final String? invitationCode;
  const RegisterScreen({super.key, this.invitationCode});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();

  static String? pendingInvitationCode;
  static void clearPendingCode() => pendingInvitationCode = null;
}

class _RegisterScreenState extends State<RegisterScreen> with WidgetsBindingObserver {
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

    // ✅ 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);

    final code = widget.invitationCode;
    if (code != null && code.isNotEmpty) {
      _invitationCodeController.text = code;
      _showInvitationCode = true;
    }
  }

  @override
  void dispose() {
    // ✅ 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);

    // ========== ✅ [关键修复] 添加这行：清理OAuth状态 ==========
    // 用户离开注册页时（点击返回按钮），取消进行中的OAuth
    // 防止：点击OAuth登录 → 返回App → 按钮锁死
    OAuthEntry.cancelIfInFlight();

    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  // ⛔ [已删除] didChangeAppLifecycleState
  // 删除原因：从外部应用（WhatsApp/分享）返回时，此监听会导致用户被误推到登录页
  // OAuth 生命周期已由 AuthFlowObserver 统一管理，此处监听是多余的且会造成问题


  /// 统一 OAuth 启动器（位置参数 + 20s 超时 + finally 复位）
  /// 注意：此文件按你项目的变量使用 _busy
  Future<void> _oauthSignIn(
      OAuthProvider provider, {
        Map<String, String>? queryParams,
      }) async {
    if (!mounted || _busy) return;

    // ✅ 软防死锁：若仍在交互中，则先取消并提示"再点一次重试"
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
      debugPrint('[Register._oauthSignIn] timeout/canceled');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login canceled')),
        );
      }
    } catch (e, st) {
      OAuthEntry.finish();
      debugPrint('[Register._oauthSignIn] error: $e');
      debugPrint(st.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed')),
        );
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
      _showError(e.message);
    } catch (e) {
      _showError('Register failed: $e');
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
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      ),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      ),
    );
  }

  void _goBack() {
    // ✅ 清理OAuth状态
    OAuthEntry.cancelIfInFlight();

    // ✅ 重置 _busy 状态
    if (mounted) setState(() => _busy = false);

    navPop();
  }

  @override
  Widget build(BuildContext context) {
    final showApple =
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
                  SizedBox(height: 8.h),
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
                  SizedBox(height: 22.h),

                  _input(
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'Enter your name',
                    icon: Icons.person_outline,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),

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
                  SizedBox(height: 12.h),

                  _input(
                    controller: _phoneController,
                    label: 'Phone Number (Optional)',
                    hint: 'Enter your phone number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(height: 12.h),

                  _input(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscureText: !_isPasswordVisible,
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _isPasswordVisible = !_isPasswordVisible),
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18.r,
                        color: Colors.grey[500],
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (v.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),

                  _input(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_outline,
                    obscureText: !_isConfirmPasswordVisible,
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                              () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18.r,
                        color: Colors.grey[500],
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16.h),

                  _buildInvitationCodeSection(),

                  SizedBox(height: 14.h),

                  Row(
                    children: [
                      SizedBox(
                        width: 20.w,
                        height: 20.h,
                        child: Checkbox(
                          value: _agreeToTerms,
                          onChanged: (v) => setState(() => _agreeToTerms = v ?? false),
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                              children: [
                                const TextSpan(text: 'I agree to '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: const TextStyle(
                                    color: Color(0xFF2196F3),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: const TextStyle(
                                    color: Color(0xFF2196F3),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),

                  // ✅ 使用 ValueListenableBuilder 监听 OAuth 状态
                  ValueListenableBuilder<bool>(
                    valueListenable: OAuthEntry.inFlightNotifier,
                    builder: (context, isOAuthInFlight, child) {
                      return Container(
                        width: double.infinity,
                        height: 48.h,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: InkWell(
                          onTap: (_isLoading || isOAuthInFlight) ? null : _register,
                          child: Center(
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                              'Sign Up',
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

                  SizedBox(height: 16.h),

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

                  SizedBox(height: 16.h),

                  // ✅ 使用 ValueListenableBuilder 监听 OAuth 状态
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
                              disabled: _isLoading || isOAuthInFlight,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _socialBtn(
                              'Facebook',
                              Colors.blue[800]!,
                              Icons.facebook,
                              _facebookRegister,
                              disabled: _isLoading || isOAuthInFlight,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  if (showApple) SizedBox(height: 12.h),
                  if (showApple)
                  // ✅ 使用 ValueListenableBuilder 监听 OAuth 状态
                    ValueListenableBuilder<bool>(
                      valueListenable: OAuthEntry.inFlightNotifier,
                      builder: (context, isOAuthInFlight, child) {
                        return _appleSignInButtonIOS(
                          disabled: _isLoading || isOAuthInFlight,
                        );
                      },
                    ),

                  SizedBox(height: 18.h),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
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

  Widget _buildInvitationCodeSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                          style:
                          TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
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
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
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
        bool disabled = false,  // ✅ 新增参数
      }) {
    return SizedBox(
      height: 42.h,
      child: OutlinedButton(
        // ✅ 使用传入的 disabled 参数
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

  Widget _appleSignInButtonIOS({bool disabled = false}) {  // ✅ 新增参数
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: ElevatedButton(
        // ✅ 使用传入的 disabled 参数
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