// lib/auth/welcome_screen.dart
// ✅ 页面级 onAuthStateChange 已移除：并发导航统一交由 AuthFlowObserver 处理
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ✅ [P0 修复] 移除 flutter_native_splash 导入（已不再需要）

// 使用 root nav（全局唯一导航）
import 'package:swaply/router/root_nav.dart';

// ✅ 通过 Service 统一处理欢迎优惠券弹窗（内部会构造 couponData / 去重等）
import 'package:swaply/services/welcome_dialog_service.dart';

import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  late AnimationController _floatController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _floatAnimation;

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // ✅ [P0 修复] 删除此处的 FlutterNativeSplash.remove()
    // Splash 移除已统一在 app.dart 中处理

    // ✅ [P2 修复] 删除此处的 _maybeShowWelcomeDialog() 调用
    // 弹窗逻辑已统一在 MainNavigationPage 中处理，避免多点调用

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _floatAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _animationController.forward();

    // ✅ 不在页面层监听鉴权变化，导航交由全局 AuthFlowObserver
    _bootAuth();
  }

  void _maybeShowWelcomeDialog() {
    // ✅ 统一入口：内部会校验是否应弹、构造 couponData，并处理“已展示去重”
    WelcomeDialogService.maybeShow(context);
  }

  Future<void> _bootAuth() async {
    final s = Supabase.instance.client.auth.currentSession;
    if (!mounted) return;
    if (s != null) {
      debugPrint('[Welcome] session exists; initialRoute should be /home');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _continueAsGuest() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.r),
          ),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Container(
            padding: EdgeInsets.all(24.r),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24.r),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.blue.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 32.r,
                    color: const Color(0xFF1565C0),
                  ),
                ),
                SizedBox(height: 20.h),
                Text(
                  'Guest Mode',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D47A1),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'You can explore the app with limited features:',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                Container(
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.amber.shade200, width: 1),
                  ),
                  child: Column(
                    children: [
                      _buildLimitationItem('Post listings', false),
                      _buildLimitationItem('Save favorites', false),
                      _buildLimitationItem('Contact sellers', false),
                      _buildLimitationItem('Browse items', true),
                    ],
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'Create an account anytime from Profile',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.h),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            if (!mounted) return;
                            // ✅ 最小修复：直接清栈跳转到 /home（游客态由 MainNavigationPage 基于 session==null 判定）
                            try {
                              debugPrint(
                                  '[Welcome] guest -> navReplaceAll(/home)');
                              await navReplaceAll('/home',
                                  arguments: const {'isGuest': true});
                            } catch (e, st) {
                              debugPrint('[Welcome] guest nav error: $e');
                              debugPrint(st.toString());
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Failed to enter guest mode')),
                                );
                              }
                            }
                          },
                          child: Text(
                            'Continue',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLimitationItem(String text, bool isAvailable) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.cancel,
            size: 18.r,
            color: isAvailable ? Colors.green : Colors.red[400],
          ),
          SizedBox(width: 8.w),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.grey[800],
              decoration: isAvailable ? null : TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ 首帧兜底白底（不影响视觉，但能掩护极短空窗）
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E88E5), Color(0xFF1565C0), Color(0xFF0D47A1)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100.h,
              left: -100.w,
              child: Container(
                width: 250.r,
                height: 250.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -80.h,
              right: -80.w,
              child: Container(
                width: 200.r,
                height: 200.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24.w),
                          child: Column(
                            children: [
                              SizedBox(height: constraints.maxHeight * 0.08),
                              AnimatedBuilder(
                                animation: _floatAnimation,
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(0, _floatAnimation.value),
                                    child: child,
                                  );
                                },
                                child: ScaleTransition(
                                  scale: _scaleAnimation,
                                  child: FadeTransition(
                                    opacity: _fadeAnimation,
                                    child: Column(
                                      children: [
                                        // ✅【暂时替换】Logo 文字（去掉 ShaderMask，纯色）
                                        Container(
                                          width: 90.r,
                                          height: 90.r,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(24.r),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                blurRadius: 20.r,
                                                offset: Offset(0, 10.h),
                                              ),
                                              BoxShadow(
                                                color: Colors.white
                                                    .withOpacity(0.1),
                                                blurRadius: 10.r,
                                                offset: Offset(-5.w, -5.h),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              'S',
                                              style: TextStyle(
                                                fontSize: 48.sp,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(
                                                    0xFF1565C0), // 纯色
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: 24.h),
                                        // ✅【暂时替换】标题文字（去掉 ShaderMask，纯白）
                                        Text(
                                          'Swaply',
                                          style: TextStyle(
                                            fontSize: 40.sp,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white, // 纯白
                                            letterSpacing: 1.5,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black
                                                    .withOpacity(0.1),
                                                offset: const Offset(0, 2),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 8.h),
                                        Text(
                                          'Buy. Sell. Swap. Locally.',
                                          style: TextStyle(
                                            fontSize: 16.sp,
                                            color:
                                                Colors.white.withOpacity(0.95),
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: constraints.maxHeight * 0.06),
                              SlideTransition(
                                position: _slideAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildFeature(Icons.shopping_cart_rounded,
                                          'Shop Smart'),
                                      _buildFeature(
                                          Icons.near_me_rounded, 'Near You'),
                                      _buildFeature(
                                          Icons.security_rounded, 'Safe Trade'),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              SlideTransition(
                                position: _slideAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Column(
                                    children: [
                                      // -------- Register Button --------
                                      Container(
                                        width: double.infinity,
                                        height: 52.h,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.white,
                                              Color(0xFFF8F9FA)
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(16.r),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.15),
                                              blurRadius: 12.r,
                                              offset: Offset(0, 6.h),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _busy
                                                ? null
                                                : () {
                                                    setState(
                                                        () => _busy = true);
                                                    navPush('/register')
                                                        .whenComplete(() {
                                                      if (mounted) {
                                                        setState(() =>
                                                            _busy = false);
                                                      }
                                                    });
                                                  },
                                            borderRadius:
                                                BorderRadius.circular(16.r),
                                            child: Center(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .rocket_launch_rounded,
                                                      color: const Color(
                                                          0xFF1565C0),
                                                      size: 20.r),
                                                  SizedBox(width: 8.w),
                                                  Text(
                                                    'Get Started',
                                                    style: TextStyle(
                                                      color: const Color(
                                                          0xFF1565C0),
                                                      fontSize: 16.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      SizedBox(height: 12.h),

                                      // -------- Login Button --------
                                      Container(
                                        width: double.infinity,
                                        height: 52.h,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(16.r),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.3),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _busy
                                                ? null
                                                : () {
                                                    setState(
                                                        () => _busy = true);
                                                    navPush('/login')
                                                        .whenComplete(() {
                                                      if (mounted) {
                                                        setState(() =>
                                                            _busy = false);
                                                      }
                                                    });
                                                  },
                                            borderRadius:
                                                BorderRadius.circular(16.r),
                                            child: Center(
                                              child: Text(
                                                'Sign In',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      SizedBox(height: 16.h),

                                      // -------- Browse as Guest --------
                                      TextButton(
                                        onPressed:
                                            _busy ? null : _continueAsGuest,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 20.w, vertical: 12.h),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.visibility_outlined,
                                                color: Colors.white70,
                                                size: 18.r),
                                            SizedBox(width: 6.w),
                                            Text(
                                              'Browse as Guest',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.w500,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor: Colors.white30,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 20.h),
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 20.w),
                                  child: Text(
                                    'By continuing, you agree to our\nTerms of Service and Privacy Policy',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11.sp,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 20.h),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1 * _fadeAnimation.value),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22.r),
              ),
              SizedBox(height: 6.h),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
