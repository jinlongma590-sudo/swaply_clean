// lib/auth/reset_password_page.dart
// ✅ [修复] 使用统一的回调 URL 配置
// ✅ 完整修复版本：
//    1. 添加 code 参数处理（iOS/Android 统一）
//    2. 修复 _goBack() 无限loading问题
//    3. 优化密码更新后的跳转（直接到首页，无卡顿）

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/root_nav.dart';

// ✅ 引入统一配置
import 'package:swaply/config/auth_config.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? token;
  const ResetPasswordPage({super.key, this.token});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _pwd = TextEditingController();
  final _pwd2 = TextEditingController();

  bool _busy = false;
  bool _show1 = false;
  bool _show2 = false;
  bool _hasSession = false;
  bool _checkingSession = true;

  String? _code;
  String? _token;
  String? _type;
  String? _error;
  String? _refreshToken;
  String? _errorDescription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extractArgumentsAndCheckSession();
    });
  }

  @override
  void dispose() {
    _pwd.dispose();
    _pwd2.dispose();
    super.dispose();
  }

  Future<void> _extractArgumentsAndCheckSession() async {
    if (!mounted) return;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (kDebugMode) {
      debugPrint('[ResetPassword] 📋 Route arguments: $args');
      debugPrint(
          '[ResetPassword] 📋 Widget token: ${widget.token != null ? "***" : "null"}');
    }

    setState(() {
      _code = args?['code'] as String?;
      _token = (args?['token'] as String?) ?? widget.token;
      _type = args?['type'] as String? ?? 'recovery';
      _error = args?['error'] as String?;
      _errorDescription = args?['error_description'] as String?;
      _refreshToken = args?['refresh_token'] as String?;
    });

    if (kDebugMode) {
      debugPrint('[ResetPassword] 🔐 Code: ${_code != null ? "***" : "NULL"}');
      debugPrint(
          '[ResetPassword] 🔑 Token: ${_token != null ? "***${_token!.length > 10 ? _token!.substring(_token!.length - 10) : _token!}" : "NULL"}');
      debugPrint('[ResetPassword] 📝 Type: $_type');
      debugPrint('[ResetPassword] ❌ Error: $_error');
      debugPrint('[ResetPassword] 📄 Error Desc: $_errorDescription');
      debugPrint(
          '[ResetPassword] 🔄 Refresh: ${_refreshToken != null ? "***" : "null"}');
    }

    if (_error != null && _error!.isNotEmpty) {
      setState(() {
        _hasSession = false;
        _checkingSession = false;
      });

      Future.delayed(Duration.zero, () {
        if (mounted) {
          _toast(_errorDescription ?? _error ?? 'This reset link is invalid');
        }
      });
      return;
    }

    if (_code != null && _code!.isNotEmpty) {
      await _restoreSessionFromCode();
    } else if (_token != null && _token!.isNotEmpty) {
      await _restoreSessionFromToken();
    } else {
      await _checkExistingSession();
    }
  }

  Future<void> _restoreSessionFromCode() async {
    if (kDebugMode) {
      debugPrint(
          '[ResetPassword] 🔐 Using code parameter (Supabase SDK will handle)...');
    }

    try {
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      final currentSession = Supabase.instance.client.auth.currentSession;
      final hasSession = currentSession != null;

      setState(() {
        _hasSession = hasSession;
        _checkingSession = false;
      });

      if (kDebugMode) {
        debugPrint(
            '[ResetPassword] ${hasSession ? "✅" : "❌"} Code auto-recovery: $hasSession');
      }

      if (hasSession) {
        _toast('Reset link verified! Please enter your new password.',
            isError: false);
      } else {
        _toast(
          'Unable to verify reset link. It may have expired.\n\n'
          'Please request a new reset link from the login page.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[ResetPassword] ❌ Code recovery error: $e');
      }

      setState(() {
        _hasSession = false;
        _checkingSession = false;
      });

      _toast(
        'An error occurred while verifying the reset link.\n\n'
        'Please try again or request a new reset link.',
      );
    }
  }

  Future<void> _restoreSessionFromToken() async {
    if (kDebugMode) {
      debugPrint(
          '[ResetPassword] 🔐 Starting session restoration from token...');
    }

    try {
      final auth = Supabase.instance.client.auth;
      bool sessionRestored = false;

      if (_refreshToken != null &&
          _refreshToken!.isNotEmpty &&
          _token != null) {
        if (kDebugMode) {
          debugPrint('[ResetPassword] 🔄 Method 1: setSession with tokens...');
        }

        try {
          final response = await auth.setSession(_refreshToken!);
          sessionRestored = response.session != null;

          if (kDebugMode) {
            debugPrint(
                '[ResetPassword] ${sessionRestored ? "✅" : "❌"} setSession: $sessionRestored');
          }

          if (sessionRestored) {
            if (!mounted) return;
            setState(() {
              _hasSession = true;
              _checkingSession = false;
            });
            _toast('Reset link verified! Please enter your new password.',
                isError: false);
            return;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[ResetPassword] ⚠️ Method 1 failed: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[ResetPassword] 🔄 Method 2: getSessionFromUrl...');
      }

      try {
        // ✅ 使用统一配置
        String recoveryUrl;
        if (_refreshToken != null && _refreshToken!.isNotEmpty) {
          recoveryUrl =
              '$kResetPasswordRedirectUri#access_token=$_token&refresh_token=$_refreshToken&type=${_type ?? "recovery"}';
        } else {
          recoveryUrl =
              '$kResetPasswordRedirectUri#access_token=$_token&type=${_type ?? "recovery"}';
        }

        if (kDebugMode) {
          debugPrint(
              '[ResetPassword] 🔗 Recovery URL: ${recoveryUrl.replaceAll(_token!, "***")}');
        }

        final response = await auth.getSessionFromUrl(Uri.parse(recoveryUrl));
        sessionRestored = response.session != null;

        if (kDebugMode) {
          debugPrint(
              '[ResetPassword] ${sessionRestored ? "✅" : "❌"} getSessionFromUrl: $sessionRestored');
        }

        if (sessionRestored) {
          if (!mounted) return;
          setState(() {
            _hasSession = true;
            _checkingSession = false;
          });
          _toast('Reset link verified! Please enter your new password.',
              isError: false);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ResetPassword] ⚠️ Method 2 failed: $e');
        }
      }

      if (kDebugMode) {
        debugPrint('[ResetPassword] 🔄 Method 3: Waiting for auto-recovery...');
      }

      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      final currentSession = auth.currentSession;
      sessionRestored = currentSession != null;

      if (kDebugMode) {
        debugPrint(
            '[ResetPassword] ${sessionRestored ? "✅" : "❌"} Auto-recovery: $sessionRestored');
      }

      setState(() {
        _hasSession = sessionRestored;
        _checkingSession = false;
      });

      if (!sessionRestored) {
        _toast(
          'Unable to verify reset link. It may have expired.\n\n'
          'Please request a new reset link from the login page.',
        );
      } else {
        _toast('Reset link verified! Please enter your new password.',
            isError: false);
      }
    } on AuthException catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[ResetPassword] ❌ AuthException: ${e.message}');
      }

      setState(() {
        _hasSession = false;
        _checkingSession = false;
      });

      String errorMsg;
      if (e.message.toLowerCase().contains('expired')) {
        errorMsg =
            'This reset link has expired.\n\nPlease request a new one from the login page.';
      } else if (e.message.toLowerCase().contains('invalid')) {
        errorMsg =
            'This reset link is invalid.\n\nPlease request a new one from the login page.';
      } else if (e.message.toLowerCase().contains('used')) {
        errorMsg =
            'This reset link has already been used.\n\nPlease request a new one if needed.';
      } else {
        errorMsg =
            'Failed to verify reset link: ${e.message}\n\nPlease request a new one.';
      }

      _toast(errorMsg);
    } catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[ResetPassword] ❌ Unknown error: $e');
      }

      setState(() {
        _hasSession = false;
        _checkingSession = false;
      });

      _toast(
        'An error occurred while verifying the reset link.\n\n'
        'Please try again or request a new reset link.',
      );
    }
  }

  Future<void> _checkExistingSession() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final hasSession = Supabase.instance.client.auth.currentSession != null;

    setState(() {
      _hasSession = hasSession;
      _checkingSession = false;
    });

    if (kDebugMode) {
      debugPrint('[ResetPassword] 🔍 Existing session check: $hasSession');
    }

    if (!hasSession) {
      _toast(
          'No active reset session found.\n\nPlease click "Forgot Password" to get a new reset link.');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasSession) {
      _toast('Cannot update password: No valid session');
      return;
    }

    setState(() => _busy = true);

    try {
      final newPassword = _pwd.text.trim();

      if (kDebugMode) {
        debugPrint('[ResetPassword] 🔒 Updating password...');
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (kDebugMode) {
        debugPrint('[ResetPassword] ✅ Password updated successfully');
      }

      if (!mounted) return;

      setState(() => _busy = false);

      _toast(
        'Password updated successfully! Redirecting to home...',
        isError: false,
      );

      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      navReplaceAll('/home');
    } on AuthException catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[ResetPassword] ❌ Update failed: ${e.message}');
      }

      setState(() => _busy = false);

      _toast('Failed to update password: ${e.message}');
    } catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[ResetPassword] ❌ Unknown error: $e');
      }

      setState(() => _busy = false);

      _toast('An error occurred. Please try again.');
    }
  }

  void _toast(String msg, {bool isError = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 3),
        margin: EdgeInsets.all(16.w),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    } else {
      navReplaceAll('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Reset Password'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: _checkingSession
            ? _buildLoadingView()
            : SingleChildScrollView(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_hasSession) _buildErrorCard(),
                    if (_hasSession) _buildSuccessCard(),
                    SizedBox(height: 24.h),
                    _buildPasswordForm(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: 20.h),
          Text(
            'Verifying reset link...',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Please wait while we validate your password reset request',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.red[700],
                size: 28.r,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Reset Link Invalid or Expired',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.red[900],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            'This password reset link is no longer valid.',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'To reset your password:\n'
            '1. Return to the login screen\n'
            '2. Tap "Forgot Password"\n'
            '3. Enter your email address\n'
            '4. Check your email for a new reset link\n'
            '5. Open the new link on this device',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Return to Login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.green.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.green[700],
            size: 28.r,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Reset link verified!\nEnter your new password below.',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                color: Colors.green[900],
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _passwordField(
            controller: _pwd,
            label: 'New Password',
            hint: 'Enter your new password',
            show: _show1,
            onToggle: () => setState(() => _show1 = !_show1),
          ),
          SizedBox(height: 16.h),
          _passwordField(
            controller: _pwd2,
            label: 'Confirm New Password',
            hint: 'Re-enter your new password',
            show: _show2,
            onToggle: () => setState(() => _show2 = !_show2),
            confirmOf: _pwd,
          ),
          SizedBox(height: 32.h),
          SizedBox(
            width: double.infinity,
            height: 54.h,
            child: ElevatedButton(
              onPressed: (_busy || !_hasSession) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          if (!_hasSession) ...[
            SizedBox(height: 16.h),
            Text(
              'The "Update Password" button will be enabled once\na valid reset link is verified.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool show,
    required VoidCallback onToggle,
    TextEditingController? confirmOf,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !show,
      enabled: _hasSession && !_busy,
      style: TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: _hasSession && !_busy ? Colors.white : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.red[400]!, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey[600],
          ),
          onPressed: _hasSession ? onToggle : null,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
      validator: (v) {
        if (!_hasSession) return null;
        if (v == null || v.isEmpty) return 'Please enter a password';
        if (v.length < 6) return 'Password must be at least 6 characters';
        if (confirmOf != null && v != confirmOf.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }
}
