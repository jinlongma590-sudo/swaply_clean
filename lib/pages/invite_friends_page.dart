// lib/pages/invite_friends_page.dart - 现代化设计 + 正确处理 link_referral 返回状态
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:swaply/services/reward_service.dart';

class InviteFriendsPage extends StatefulWidget {
  const InviteFriendsPage({super.key});

  @override
  State<InviteFriendsPage> createState() => _InviteFriendsPageState();
}

class _InviteFriendsPageState extends State<InviteFriendsPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _loading = true;
  bool _regenerating = false;
  bool _isRefreshing = false;
  bool _binding = false; // 绑定状态

  String? _inviteCode;
  List<Map<String, dynamic>> _invitations = [];
  Map<String, dynamic> _rewardStats = {};

  final _inviteInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadAll();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _inviteInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        RewardService.generateInvitationCode(user.id),
        RewardService.getUserInvitations(user.id),
        RewardService.getUserRewardStats(user.id),
      ]);

      if (!mounted) return;

      setState(() {
        _inviteCode = results[0] as String?;

        final rawInvitations = results[1];
        if (rawInvitations is List) {
          _invitations = rawInvitations
              .where((item) => item != null)
              .map((item) => Map<String, dynamic>.from(item))
              .where((invitation) {
            final inviterId = invitation['inviter_id']?.toString();
            final inviteeId = invitation['invitee_id']?.toString();

            if (inviterId == user.id && inviteeId == user.id) return false;
            if (inviterId == user.id &&
                (inviteeId == null || inviteeId.isEmpty)) {
              return false;
            }
            return inviterId == user.id &&
                inviteeId != null &&
                inviteeId.isNotEmpty &&
                inviteeId != user.id;
          }).toList();
        } else {
          _invitations = [];
        }

        _rewardStats = (results[2] as Map<String, dynamic>?) ?? {};
        _loading = false;
      });

      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Failed to load data: $e', isError: true);
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _loadAll();
    setState(() => _isRefreshing = false);
  }

  Future<void> _refreshCode() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _regenerating = true);
    try {
      // 返回已有或新建的 code（非强制重生成）
      final code = await RewardService.generateInvitationCode(user.id);
      if (!mounted) return;
      setState(() => _inviteCode = code);
      _showSnack('Code refreshed successfully');
    } catch (e) {
      _showSnack('Failed to refresh code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _shareInvite() async {
    if (_inviteCode == null) return;

    final deepLink = 'swaply://register?code=$_inviteCode';
    final shareText = '''
🎉 Join Swaply - Trade what you have for what you need!

Use my invitation code: $_inviteCode
$deepLink

⭐ Highlights:
- Category Pin (3d)
- Search/Popular Pin (3d)
- Trending (3d)

Download: https://www.swaply.cc
#Swaply #InviteRewards
''';
    try {
      await Share.share(shareText, subject: 'Join Swaply with my invitation');
    } catch (_) {
      await _copyText(shareText);
    }
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copied to clipboard');
  }

  // ====== 修复点：在页面内直接调用 RPC，并根据返回值分别提示 ======
  Future<void> _bindInviteCode() async {
    final code = _inviteInputCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showSnack('Please enter an invitation code', isError: true);
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnack('Please sign in first', isError: true);
      return;
    }

    setState(() => _binding = true);
    try {
      final status = await RewardService.submitInviteCode(code);

      switch (status) {
        case 'ok':
          _showSnack(
              'Invitation linked! Reward will be granted after you publish your first listing.');
          _inviteInputCtrl.clear();
          await _refreshData();
          break;
        case 'self_not_allowed':
          _showSnack("You can't use your own code", isError: true);
          break;
        case 'already_linked':
          _showSnack('You have already linked an invitation', isError: true);
          break;
        case 'code_not_found':
        case 'invalid_code':
          _showSnack('Invalid invitation code', isError: true);
          break;
        case 'not_authenticated':
          _showSnack('Please sign in first', isError: true);
          break;
        default:
          _showSnack('Link failed. Please try again later.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _binding = false);
    }
  }

  void _showSnack(String msg, {bool isError = false, Color? color}) {
    if (!mounted) return;
    final bg = color ?? (isError ? Colors.red[600] : const Color(0xFF4CAF50));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        margin: EdgeInsets.all(12.r),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  int get _completedCount {
    return _invitations.where((e) {
      final status = (e['status'] ?? '').toString();
      return status == 'completed';
    }).length;
  }

  int get _pendingCount {
    return _invitations.where((e) {
      final status = (e['status'] ?? '').toString();
      return status == 'pending' || status == 'accepted';
    }).length;
  }

  int get _totalCount => _completedCount + _pendingCount;

  @override
  Widget build(BuildContext context) {
    // 状态栏设置 (确保浅色图标)
    // 理论上这应该在路由切换或 main.dart 中全局设置
    // 为确保此页面正确显示，在此处调用
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // iOS 浅色内容 (for dark bg)
      statusBarBrightness: Brightness.dark, // Android 浅色内容 (for dark bg)
    ));

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return _buildNotLoggedInView();
    }

    // ✅ [MODIFIED] 提取平台变量
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    // ✅ [MODIFIED] 提取刷新按钮逻辑，以便在 iOS 和 Android 之间共享
    final refreshBtnWidget = _isRefreshing
        ? SizedBox(
      width: 20.r,
      height: 20.r,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white,
      ),
    )
        : Icon(Icons.refresh, size: 20.r);

    // ✅ [REMOVED] 移除旧的 36x36 刷新按钮定义
    // final iosRefreshBtn = ... (old 36x36 definition removed)

    if (isIOS) {
      // ===== ✅ iOS: 使用自定义 Stack 头部 =====
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            // ✅ [MODIFIED] 'trailing' 参数现在用于判断是否显示刷新按钮
            _buildHeaderIOS(context, trailing: true),
            Expanded(child: _buildBodyContent()),
          ],
        ),
      );
    } else {
      // ===== ✅ Android: 保持原有 AppBar =====
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          toolbarHeight: null, // Android 默认
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_new, size: 20.r),
          ),
          title: Text(
            'Invite Friends',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _isRefreshing ? null : _refreshData,
              icon: refreshBtnWidget,
            ),
          ],
        ),
        body: _buildBodyContent(),
      );
    }
  }

  /// ✅ [REBUILT] iOS 头部 (基于 verification_page.dart 标准 44pt Row 布局)
  Widget _buildHeaderIOS(BuildContext context, {bool trailing = false}) {
    final double statusBar = MediaQuery.of(context).padding.top;

    // 2. 采用新的标准布局 (来自 verification_page.dart)
    return Container(
      // 保持邀请页的绿色
      decoration: const BoxDecoration(
        color: Color(0xFF4CAF50),
      ),
      padding: EdgeInsets.only(top: statusBar), // 让出状态栏
      child: SizedBox(
        height: 44, // 标准导航条高度
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16), // 左右边距 16
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // 保证垂直居中
            children: [
              // 左侧 32×32 返回 (标准)
              SizedBox(
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10), // 匹配圆角
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_back_ios_new,
                        size: 18, color: Colors.white), // 匹配图标
                  ),
                ),
              ),
              const SizedBox(width: 12), // 标准间距

              // 标题：与左右按钮同一基线 (标准)
              Expanded(
                child: Text(
                  'Invite Friends',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, // 保持居中
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 18.sp, // ✅ 匹配 verification_page.dart 标准
                  ),
                ),
              ),
              const SizedBox(width: 12), // 标准间距

              // 右侧 32×32 刷新或占位 (标准)
              SizedBox(
                width: 32,
                height: 32,
                child: trailing // (trailing == true)
                    ? GestureDetector(
                  onTap: _isRefreshing ? null : _refreshData,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10), // 匹配圆角
                    ),
                    alignment: Alignment.center,
                    child: _isRefreshing
                        ? const SizedBox(
                      width: 18, // 匹配图标大小
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.refresh,
                        color: Colors.white, size: 18), // 匹配图标
                  ),
                )
                    : null, // (trailing == false)
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ [NEW] 提取的主体内容
  Widget _buildBodyContent() {
    return _loading
        ? _buildLoadingState()
        : FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _refreshData,
        color: const Color(0xFF4CAF50),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModernStatsCard(),
              SizedBox(height: 20.h),
              _buildRewardsInfoCard(),
              SizedBox(height: 20.h),
              _buildInviteCodeCard(),
              SizedBox(height: 20.h),
              _buildBindInviteCard(),
              SizedBox(height: 20.h),
              _buildProgressCard(),
              SizedBox(height: 20.h),
              _buildHistoryCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ [MODIFIED] 未登录视图也使用新标准
  Widget _buildNotLoggedInView() {
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      // ===== iOS Guest: 使用自定义 Stack 头部 (无刷新按钮) =====
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            _buildHeaderIOS(context, trailing: false), // ✅ 无刷新按钮 (占位符)
            Expanded(child: _buildGuestBodyContent()),
          ],
        ),
      );
    } else {
      // ===== Android Guest: 保持原有 AppBar =====
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          toolbarHeight: null, // Android 默认
          title: Text(
            'Invite Friends',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          automaticallyImplyLeading: true,
        ),
        body: _buildGuestBodyContent(),
      );
    }
  }

  /// ✅ [NEW] 提取的未登录主体内容
  Widget _buildGuestBodyContent() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(40.r),
              ),
              child: Icon(Icons.login, size: 40.r, color: Colors.white),
            ),
            SizedBox(height: 20.h),
            Text(
              'Please Sign In',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Sign in to use the invite feature and earn rewards',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStatsCard() {
    final successRate =
    _totalCount > 0 ? (_completedCount / _totalCount * 100).toInt() : 0;

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.analytics, color: Colors.white, size: 20.r),
              ),
              SizedBox(width: 12.w),
              Text(
                'Your Invitation Stats',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total Invites',
                  _totalCount.toString(),
                  Icons.group_add,
                  const Color(0xFF4CAF50),
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Success Rate',
                  '$successRate%',
                  Icons.trending_up,
                  const Color(0xFF2196F3),
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Rewards Earned',
                  _completedCount.toString(),
                  Icons.card_giftcard,
                  const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(icon, color: color, size: 24.r),
        ),
        SizedBox(height: 8.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRewardsInfoCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withOpacity(0.3),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.white, size: 28.r),
              SizedBox(width: 12.w),
              Text(
                'Invite & Earn Rewards',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            'Invite friends to join Swaply and earn valuable pin coupons when they publish their first listing.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 14.sp,
              height: 1.5,
            ),
          ),
          SizedBox(height: 16.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _buildRewardChip('1', 'Category Pin (3d)', _completedCount >= 1),
              _buildRewardChip(
                  '5', 'Search/Popular Pin (3d)', _completedCount >= 5),
              _buildRewardChip('10', 'Trending (3d)', _completedCount >= 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRewardChip(String count, String label, bool achieved) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(achieved ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(achieved ? 0.6 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20.w,
            height: 20.h,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Center(
              child: Text(
                count,
                style: TextStyle(
                  color: const Color(0xFF4CAF50),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (achieved) ...[
            SizedBox(width: 4.w),
            Icon(Icons.check, color: Colors.white, size: 16.r),
          ],
        ],
      ),
    );
  }

  Widget _buildInviteCodeCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.qr_code, color: Colors.white, size: 20.r),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Invitation Code',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Share this code to earn rewards',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 20.h),
          if (_inviteCode == null)
            SizedBox(
              height: 100.h,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF4CAF50),
                ),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                    color: const Color(0xFF4CAF50).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    _inviteCode!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 28.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF4CAF50),
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (_inviteCode != null) _copyText(_inviteCode!);
                          },
                          icon: Icon(Icons.copy, size: 18.r),
                          label: const Text('Copy Code'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4CAF50),
                            side: const BorderSide(color: Color(0xFF4CAF50)),
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _shareInvite,
                          icon: Icon(Icons.share, size: 18.r),
                          label: const Text('Share'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Center(
              child: TextButton.icon(
                onPressed: _regenerating ? null : _refreshCode,
                icon: _regenerating
                    ? SizedBox(
                  width: 16.r,
                  height: 16.r,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.refresh, size: 16),
                // 文案改为 Refresh，避免误导
                label: Text(_regenerating ? 'Refreshing...' : 'Refresh Code'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBindInviteCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.link, color: Colors.white, size: 20.r),
              ),
              SizedBox(width: 12.w),
              Text(
                'Have an Invitation Code?',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: _inviteInputCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Enter code (e.g. INVABC123)',
              prefixIcon: Icon(Icons.qr_code_scanner, color: Colors.grey[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                const BorderSide(color: Color(0xFFFF9800), width: 2),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _binding ? null : _bindInviteCode,
              icon: _binding
                  ? SizedBox(
                width: 16.r,
                height: 16.r,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.link, size: 18),
              label: Text(_binding ? 'Binding...' : 'Bind Invitation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFFFF9800), size: 16),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'After binding, rewards will be granted to your friend once you publish your first listing.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.brown[700],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    if (_totalCount == 0) return const SizedBox.shrink();

    final rate = _completedCount / _totalCount;

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invitation Progress',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildProgressItem('Total', _totalCount, const Color(0xFF4CAF50)),
              _buildProgressItem(
                  'Completed', _completedCount, const Color(0xFF2E7D32)),
              _buildProgressItem(
                  'Pending', _pendingCount, const Color(0xFFFF9800)),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            'Success Rate: ${(rate * 100).toInt()}%',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8.h),
          LinearProgressIndicator(
            value: rate,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
            minHeight: 8.h,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressItem(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          width: 50.w,
          height: 50.w,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.history, color: Colors.white, size: 20.r),
              ),
              SizedBox(width: 12.w),
              Text(
                'Invitation History',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          if (_invitations.isEmpty)
            SizedBox(
              height: 100.h,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_add_outlined,
                        size: 32.r, color: Colors.grey[400]),
                    SizedBox(height: 8.h),
                    Text(
                      'No invitations yet',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._invitations
                .take(5)
                .map((invitation) => _buildHistoryItem(invitation)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> invitation) {
    final status = invitation['status']?.toString() ?? 'pending';
    // 同时兼容 referrals 里的不同字段名
    final code =
        (invitation['code'] ?? invitation['invitation_code'])?.toString() ??
            'N/A';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = const Color(0xFF4CAF50);
        statusText = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'accepted':
        statusColor = const Color(0xFFFF9800);
        statusText = 'Registered';
        statusIcon = Icons.account_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Pending';
        statusIcon = Icons.schedule;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20.r),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code: $code',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF4CAF50),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading invite data...',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}