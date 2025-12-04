// lib/pages/verification_page.dart
// ✅ 不刷新会话；不对 profiles 做任何写操作
// ✅ 最小可用流程：输入验证码 → 调服务 → 读表 → 刷新本页 UI → Navigator.pop(true)
// ✅ 判定是否已认证 / 徽章类型：统一走 utils（基于 user_verifications 行）
// ✅ 本次改动：方案A（三态）：_verified 改为 bool?，null=检查中 → 不再闪“未认证”
// ✅ 成功后：先 VerificationGuard.invalidateCache()，再 Navigator.pop(true)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;
import '../models/verification_types.dart' as vt;
import '../widgets/verification_badge.dart' as vb;
import 'package:swaply/services/verification_guard.dart';
import 'package:swaply/router/root_nav.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  // —— 状态 —— //
  late final EmailVerificationService _svc;

  // A 方案：三态。null=检查中，true/false=已确定
  bool? _verified;
  vt.VerificationBadgeType _badge = vt.VerificationBadgeType.none;

  bool _isLoading = false;
  String? _message;
  bool _isError = false;

  String? _sentToEmail;
  int _resendCountdown = 0;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _svc = EmailVerificationService();

    _animationController =
        AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    final u = Supabase.instance.client.auth.currentUser;
    if (u?.email != null) {
      _emailController.text = u!.email!;
    }

    // 初始即进入“检查中”
    _verified = null;
    _loadUserVerificationStatus();
    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // === 统一读取 & 计算（只读 user_verifications，不碰 profiles） ===
  Future<void> _loadUserVerificationStatus() async {
    final row = await _svc.fetchVerificationRow();
    final verified = vutils.computeIsVerified(verificationRow: row, user: null);
    final badge = vutils.computeBadgeType(verificationRow: row, user: null);

    if (!mounted) return;
    setState(() {
      _verified = verified; // true/false
      _badge = badge;
    });

    if (kDebugMode) {
      debugPrint(
        '[VerificationPage] _loadUserVerificationStatus(): '
            'verified=$_verified badge=$_badge vt=${_badge.name}',
      );
    }
  }

  // === 发送验证码 ===
  Future<void> _sendVerificationCode() async {
    try {
      setState(() {
        _isLoading = true;
        _message = null;
      });
      final email = _emailController.text.trim().toLowerCase();
      if (email.isEmpty) {
        throw Exception('Please enter your email address');
      }

      final okSend = await _svc.sendVerificationCode(email);
      if (!okSend) throw Exception('Failed to send verification code');

      setState(() {
        _sentToEmail = email;
        _resendCountdown = 60;
      });
      _startResendCountdown();

      _showMessage('Verification code sent to $email', isError: false);
    } catch (e) {
      _showMessage('Failed to send verification code', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ✅ 提交验证码
  Future<void> _verifyCode() async {
    try {
      setState(() {
        _isLoading = true;
        _message = null;
      });

      final email = _emailController.text.trim().toLowerCase();
      final code = _codeController.text.trim();
      if (email.isEmpty || code.isEmpty) {
        throw Exception('Please enter email and the 6-digit code');
      }

      final ok = await _svc.verifyCode(email: email, code: code);
      if (!ok) throw Exception('Invalid or expired verification code');

      // 验证成功后重新读取实时状态
      final row = await _svc.fetchVerificationRow();
      final verified =
      vutils.computeIsVerified(verificationRow: row, user: null);
      final badge = vutils.computeBadgeType(verificationRow: row, user: null);

      if (!mounted) return;
      setState(() {
        _verified = verified;
        _badge = badge;
      });

      // ✅ 成功后：失效守卫缓存 -> 提示 -> 返回 true
      VerificationGuard.invalidateCache();
      VerificationGuard.notifyVerifiedChanged(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verification successful')),
      );
      navPop(true);
    } catch (e) {
      _showMessage('Verification failed', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
        return true;
      }
      return false;
    });
  }

  void _showMessage(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  Future<void> _refreshStatus() async {
    // 刷新时也进入“检查中”，避免旧值闪烁
    setState(() {
      _isLoading = true;
      _verified = null;
    });
    await _loadUserVerificationStatus();
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 16.sp),
            SizedBox(width: 8.w),
            Text('Verification status refreshed', style: TextStyle(fontSize: 13.sp)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        margin: EdgeInsets.all(12.w),
      ),
    );
  }

  // —— UI —— //
  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      // ============== iOS：使用自定义头部，匹配标准间距 ==============
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Column(
          children: [
            _buildHeaderIOS(),
            Expanded(child: _buildPageBody()),
          ],
        ),
      );
    }

    // ============== Android & 其他：保持原 AppBar 不变 ==============
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'Account Verification',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20.w),
          onPressed: () => navPop(),
        ),
      ),
      body: _buildPageBody(),
    );
  }

  // ================= iOS 头部（44pt Row 布局） =================
  Widget _buildHeaderIOS() {
    final double statusBar = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(top: statusBar),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () => navPop(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Account Verification',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const SizedBox(width: 32, height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 页面主体 =================
  Widget _buildPageBody() {
    final badge = _badge;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVerificationStatusCard(badge),
            SizedBox(height: 16.h),
            if (_verified == false) _buildEmailVerificationCard(),
            SizedBox(height: 16.h),
            if (_verified == true) _buildOfficialVerificationCard(),
            SizedBox(height: 16.h),
            _buildHelpCard(),
            if (_message != null) ...[
              SizedBox(height: 16.h),
              _buildMsg(),
            ],
          ],
        ),
      ),
    );
  }

  // ✅ 三态状态卡片：null=Checking…；true=Verified；false=Not Verified
  Widget _buildVerificationStatusCard(vt.VerificationBadgeType badge) {
    final bool isUnknown = _verified == null;
    final bool isVerified = _verified == true;

    Color kStatusColor;
    Color kTextColor;
    if (isUnknown) {
      kStatusColor = Colors.blueGrey;
      kTextColor = Colors.blueGrey.shade700;
    } else if (isVerified) {
      kStatusColor = Colors.green;
      kTextColor = Colors.green.shade800;
    } else {
      kStatusColor = Colors.orange;
      kTextColor = Colors.orange.shade800;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kStatusColor.withOpacity(0.05), kStatusColor.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: kStatusColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: kStatusColor.withOpacity(0.05),
            blurRadius: 16.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kStatusColor,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: isUnknown
                    ? SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
                    : Icon(
                  isVerified ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 22.w,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUnknown
                          ? 'Checking verification status…'
                          : (isVerified ? 'Verified Account' : 'Account Not Verified'),
                      style: TextStyle(fontSize: 16.5.sp, fontWeight: FontWeight.w700, color: kTextColor),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      isUnknown
                          ? 'Please wait while we confirm your verification status.'
                          : (isVerified
                          ? 'Your email address has been successfully verified.'
                          : 'Please verify your email to access all features.'),
                      style: TextStyle(fontSize: 12.5.sp, color: Colors.grey.shade700, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              if (!isUnknown && badge != vt.VerificationBadgeType.none)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 3.r,
                        offset: Offset(0, 1.h),
                      ),
                    ],
                  ),
                  child: vb.VerificationStatusChip(type: badge, showIcon: true),
                )
              else
                const Spacer(),
              const Spacer(),
              TextButton.icon(
                onPressed: isUnknown ? null : _refreshStatus,
                icon: Icon(Icons.refresh_rounded, size: 16.w),
                label: Text('Refresh Status', style: TextStyle(fontSize: 12.sp)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF667EEA),
                  backgroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmailVerificationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: Icon(Icons.email_rounded, color: Colors.white, size: 20.w),
              ),
              SizedBox(width: 14.w),
              Text('Email Verification', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 20.h),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email Address',
              hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined, color: const Color(0xFF667EEA), size: 18.w),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(color: const Color(0xFF667EEA), width: 2.w),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            ),
            style: TextStyle(fontSize: 14.sp),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _isLoading || _resendCountdown > 0 ? null : _sendVerificationCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
              ),
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: _isLoading
                      ? SizedBox(
                    height: 20.h,
                    width: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                      : Text(
                    _resendCountdown > 0
                        ? 'Resend Code (${_resendCountdown}s)'
                        : _sentToEmail != null
                        ? 'Resend Verification Code'
                        : 'Send Verification Code',
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold, letterSpacing: 6.w),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Verification Code',
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(color: const Color(0xFF667EEA), width: 2.w),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.green.shade400, Colors.green.shade600]),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: _isLoading
                      ? SizedBox(
                    height: 20.h,
                    width: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                      : Text('Verify Code', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 官方蓝卡片
  Widget _buildOfficialVerificationCard() {
    const Color kOfficialBlue = Color(0xFF1877F2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16.r, offset: Offset(0, 6.h)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kOfficialBlue, borderRadius: BorderRadius.circular(12.r)),
                child: Icon(Icons.verified_rounded, color: Colors.white, size: 22.w),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Official Verification', style: TextStyle(fontSize: 16.5.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4.h),
                    Text(
                      'Apply if you represent a business, organization, or public figure.',
                      style: TextStyle(fontSize: 12.5.sp, color: Colors.grey.shade700, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: kOfficialBlue.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: kOfficialBlue.withOpacity(0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBenefitItem('Higher visibility in search results'),
                _buildBenefitItem('Blue verified badge on your profile'),
                _buildBenefitItem('Priority customer support'),
                _buildBenefitItem('Enhanced trust from users'),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                    title: Text('Coming Soon', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                    content: Text(
                      'Official verification applications are coming soon. We\'ll notify you when this feature becomes available.',
                      style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700, height: 1.35),
                    ),
                    actions: [
                      TextButton(onPressed: () => navPop(), child: Text('OK', style: TextStyle(fontSize: 13.sp))),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.arrow_forward_rounded, size: 18.w, color: Colors.white),
              label: Text('Apply for Official Status', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: kOfficialBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: const Color(0xFF1877F2), size: 16.w),
          SizedBox(width: 10.w),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.sp, height: 1.3))),
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16.r, offset: Offset(0, 6.h)),
        ],
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14.r)),
                child: Icon(Icons.help_outline_rounded, color: Colors.grey.shade600, size: 20.w),
              ),
              SizedBox(width: 14.w),
              Text('Need Help?', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 16.h),
          Column(
            children: [
              _buildHelpItem('Check your spam/junk folder'),
              _buildHelpItem('Make sure your email address is correct'),
              _buildHelpItem('Wait a few minutes and try again'),
              _buildHelpItem('Contact support if the issue persists'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 3.h),
            width: 5.w,
            height: 5.h,
            decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.sp, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMsg() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: _isError ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: _isError ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: _isError ? Colors.red : Colors.green,
            size: 20.w,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                color: _isError ? Colors.red.shade700 : Colors.green.shade700,
                fontSize: 12.sp,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
