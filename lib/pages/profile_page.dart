// lib/pages/profile_page.dart
// ✅ [方案四] 使用 StreamBuilder 监听 Profile Stream
// ✅ 修复：iOS端使用更紧凑的UI比例，Android保持不变
// ✅ 修复：统一所有入口卡片的大小
// ✅ 修复：My Rewards 跳转到 RewardCenterPage
// ✅ [应用内认证] 删除账号链接强制在应用内打开

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/models/verification_types.dart' as vt;

import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;
import 'package:swaply/services/auth_service.dart';
import 'package:swaply/services/oauth_entry.dart';

import 'package:swaply/widgets/verified_avatar.dart';

import 'package:swaply/pages/my_listings_page.dart';
import 'package:swaply/pages/wishlist_page.dart';
import 'package:swaply/pages/invite_friends_page.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/account_settings_page.dart';
import 'package:swaply/pages/verification_page.dart';
import 'package:swaply/pages/reward_center_page.dart';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'package:swaply/core/l10n/app_localizations.dart';

const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl = 'https://www.swaply.cc/delete-account';

class _L10n {
  const _L10n();
  String get helpSupport => 'Help & Support';
  String get about => 'About';
  String get guestUser => 'Guest user';
  String get browseWithoutAccount => 'Browsing without an account';
  String get myListings => 'My Listings';
  String get wishlist => 'Wishlist';
  String get editProfile => 'Edit Profile';
  String get logout => 'Logout';
}

/* ---------------- Profile Page ---------------- */
class ProfilePage extends StatefulWidget {
  final bool isGuest;
  const ProfilePage({super.key, this.isGuest = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _dead = false;

  bool get _signedIn => Supabase.instance.client.auth.currentUser != null;

  final _svc = ProfileService();
  final _verifySvc = EmailVerificationService();
  bool _verified = false;
  vt.VerificationBadgeType _badge = vt.VerificationBadgeType.none;
  Map<String, dynamic>? _verificationRow;
  bool _verifyLoading = false;

  bool _uploadingAvatar = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _dead) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // ✅ [方案四] 启动动画
    _animationController.forward();

    // ✅ [方案四] 加载验证状态
    _reloadUserVerificationStatus();
  }

  @override
  void dispose() {
    _dead = true;
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _reloadUserVerificationStatus() async {
    _safeSetState(() => _verifyLoading = true);
    final row = await _verifySvc.fetchVerificationRow();
    if (!mounted || _dead) return;

    final user = Supabase.instance.client.auth.currentUser;
    final verified = vutils.computeIsVerified(verificationRow: row, user: user);
    final badge = vutils.computeBadgeType(verificationRow: row, user: user);

    _safeSetState(() {
      _verificationRow = row;
      _verified = verified;
      _badge = badge;
      _verifyLoading = false;
    });
  }

  Future<void> _editNamePhone() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    try {
      final p = await ProfileService.instance.getUserProfile();
      if (!mounted || _dead) {
        nameCtrl.dispose();
        phoneCtrl.dispose();
        return;
      }
      if (p != null) {
        nameCtrl.text = (p['display_name'] ?? p['full_name'] ?? '').toString();
        phoneCtrl.text = (p['phone'] ?? '').toString();
      }
    } catch (_) {}

    if (!mounted || _dead) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.grey.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: Theme.of(context).primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Edit Profile',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon:
                        const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Theme.of(context).primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Theme.of(context).primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).maybePop(false),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12)),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(width: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1E88E5)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogCtx).maybePop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save',
                            style:
                                TextStyle(fontSize: 15, color: Colors.white)),
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

    if (result == true && mounted && !_dead) {
      try {
        await ProfileService.instance.updateUserProfile(
          fullName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        );

        if (!mounted || _dead) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Profile updated successfully',
                    style: TextStyle(fontSize: 14)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );

        // ✅ [方案四] updateUserProfile 会自动重新加载并推送到 Stream
      } catch (e) {
        if (!mounted || _dead) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Update failed: $e',
                        style: const TextStyle(fontSize: 14))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }

    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _uploadAvatarSimple() async {
    if (!mounted || _dead) return;
    _safeSetState(() => _uploadingAvatar = true);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (!mounted || _dead) return;
      if (image == null) {
        _safeSetState(() => _uploadingAvatar = false);
        return;
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final bytes = await File(image.path).readAsBytes();
      if (!mounted || _dead) return;

      final ext = image.path.split('.').last;
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage.from('avatars').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(upsert: true));

      if (!mounted || _dead) return;

      final publicUrl =
          Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      await ProfileService.instance.updateUserProfile(avatarUrl: publicUrl);

      if (!mounted || _dead) return;

      // ✅ [方案四] updateUserProfile 会自动重新加载并推送到 Stream

      if (!mounted || _dead) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Avatar updated successfully',
                  style: TextStyle(fontSize: 14)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted || _dead) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Upload failed: $e',
                      style: const TextStyle(fontSize: 14))),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      _safeSetState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const l10n = _L10n();

    // ✅ 关键修复：强制禁用文本缩放 + 系统辅助功能缩放
    final media = MediaQuery.of(context);
    final clamp = media.copyWith(
      textScaler: const TextScaler.linear(1.0), // 禁用文本缩放
    );

    // Guest user
    if (!_signedIn) {
      return MediaQuery(
        data: clamp,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: ScrollConfiguration(
            behavior: const ScrollBehavior(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildEnhancedHeader(
                    isGuest: true,
                    name: l10n.guestUser,
                    email: l10n.browseWithoutAccount,
                    avatarUrl: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: _GuestSimpleOptions(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ [方案四] 核心修改：使用 StreamBuilder
    return MediaQuery(
      data: clamp,
      child: Scaffold(
        extendBody: true,
        backgroundColor: const Color(0xFFF8F9FA),
        body: StreamBuilder<Map<String, dynamic>?>(
          // 监听 Profile Stream
          stream: _svc.profileStream,
          // 使用缓存作为初始值（避免加载闪烁）
          initialData: _svc.currentProfile,
          builder: (context, snapshot) {
            // ✅ 加载状态
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3)),
                    SizedBox(height: 16),
                    Text('Loading profile...',
                        style:
                            TextStyle(color: Color(0xFF666666), fontSize: 15)),
                  ],
                ),
              );
            }

            // ✅ 未登录状态（不应该出现，因为上面已经处理了）
            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(
                child: Text('No profile data',
                    style: TextStyle(color: Color(0xFF666666), fontSize: 15)),
              );
            }

            // ✅ 显示用户资料
            final profile = snapshot.data!;
            final fullName = (profile['full_name'] ?? 'User').toString();
            final phone = (profile['phone'] ?? '').toString();
            final email =
                phone.isNotEmpty ? phone : (profile['email'] ?? '').toString();
            final avatarUrl = (profile['avatar_url'] ?? '') as String?;
            final memberSince = profile['created_at']?.toString();
            String? memberSinceText;
            if (memberSince != null && memberSince.isNotEmpty) {
              final cut = memberSince.length >= 10
                  ? memberSince.substring(0, 10)
                  : memberSince;
              memberSinceText = cut;
            }

            return Stack(
              children: [
                ScrollConfiguration(
                  behavior: const ScrollBehavior(),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildEnhancedHeader(
                          isGuest: false,
                          name: fullName,
                          email: email,
                          avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? avatarUrl
                              : null,
                          memberSince: memberSinceText,
                          verificationType: _verified
                              ? _badge
                              : vt.VerificationBadgeType.none,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Profile',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.edit_rounded,
                                  title: l10n.editProfile,
                                  color: Colors.blue,
                                  onTap: _editNamePhone,
                                ),
                                const SizedBox(height: 14),
                                _VerificationTileCard(
                                  isVerified: _verified,
                                  isLoading: _verifyLoading,
                                  onTap: () async {
                                    await SafeNavigator.push<bool>(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const VerificationPage()),
                                    );
                                    await _reloadUserVerificationStatus();
                                  },
                                ),
                                const SizedBox(height: 28),
                                const Text('Rewards & Activities',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.emoji_events_rounded,
                                  title: 'My Rewards',
                                  color: Colors.purple,
                                  onTap: () => SafeNavigator.push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const RewardCenterPage()),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.inventory_2_rounded,
                                  title: l10n.myListings,
                                  color: Colors.indigo,
                                  onTap: () => SafeNavigator.push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const MyListingsPage())),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.favorite_rounded,
                                  title: l10n.wishlist,
                                  color: Colors.pink,
                                  onTap: () {
                                    final user = Supabase
                                        .instance.client.auth.currentUser;
                                    if (user == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Please sign in to view Wishlist')),
                                      );
                                      return;
                                    }
                                    SafeNavigator.push(MaterialPageRoute(
                                        builder: (_) => const WishlistPage()));
                                  },
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.person_add_alt_1_rounded,
                                  title: 'Invite Friends',
                                  subtitle: 'Earn coupons by inviting friends',
                                  color: Colors.orange,
                                  onTap: () => SafeNavigator.push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const InviteFriendsPage()),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.local_activity_rounded,
                                  title: 'My Coupons',
                                  subtitle: 'View and manage your coupons',
                                  color: Colors.purple,
                                  onTap: () => SafeNavigator.push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const CouponManagementPage()),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                const Text('Support',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.manage_accounts,
                                  title: 'Account',
                                  subtitle: 'Password, devices, delete',
                                  color: Colors.cyan,
                                  onTap: () => SafeNavigator.push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const AccountSettingsPage()),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.privacy_tip_outlined,
                                  title: 'Privacy Policy',
                                  color: Colors.blueGrey,
                                  onTap: () => launchUrl(
                                    Uri.parse(_kPrivacyUrl),
                                    mode: LaunchMode.inAppWebView,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.delete_outline,
                                  title:
                                      'Data Deletion / How to delete my account',
                                  color: Colors.deepOrange,
                                  onTap: () => launchUrl(
                                    Uri.parse(_kDeleteUrl),
                                    mode: LaunchMode.inAppWebView,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.help_outline_rounded,
                                  title: l10n.helpSupport,
                                  color: Colors.teal,
                                  onTap: () => SafeNavigator.push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const HelpSupportPage())),
                                ),
                                const SizedBox(height: 14),
                                _ProfileOptionEnhanced(
                                  icon: Icons.info_outline_rounded,
                                  title: l10n.about,
                                  color: Colors.blueGrey,
                                  onTap: () => SafeNavigator.push(
                                      MaterialPageRoute(
                                          builder: (_) => const AboutPage())),
                                ),
                                const SizedBox(height: 28),
                                _ProfileOptionEnhanced(
                                  icon: Icons.logout_rounded,
                                  title: l10n.logout,
                                  color: Colors.red,
                                  onTap: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18)),
                                        title: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                  color: Colors.red
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: const Icon(
                                                  Icons.logout_rounded,
                                                  color: Colors.red,
                                                  size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text('Logout',
                                                style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ),
                                        content: const Text(
                                            'Are you sure you want to logout?',
                                            style: TextStyle(
                                                fontSize: 15, height: 1.4)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: Text('Cancel',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      color:
                                                          Colors.grey[600]))),
                                          Container(
                                            decoration: BoxDecoration(
                                                color: Colors.red,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: const Text('Logout',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(
                                              color: Colors.white),
                                        ),
                                      );

                                      try {
                                        AuthFlowObserver.I.markManualSignOut();
                                        RewardService.clearCache();
                                        OAuthEntry.forceCancel();
                                        await AuthService().signOut(
                                            global: true,
                                            reason: 'user-tap-profile-logout');

                                        if (mounted) {
                                          Navigator.of(context).pop();
                                          navReplaceAll('/welcome');
                                        }
                                      } catch (e) {
                                        AuthFlowObserver.I
                                            .clearManualSignOutFlag();
                                        if (mounted) {
                                          Navigator.of(context).pop();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content:
                                                    Text('Logout failed: $e'),
                                                backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_uploadingAvatar)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator()),
                            SizedBox(height: 16),
                            Text('Uploading avatar...',
                                style: TextStyle(
                                    color: Color(0xFF616161), fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ✅ iOS端使用更紧凑的比例，Android保持原样
  Widget _buildEnhancedHeader({
    required bool isGuest,
    required String name,
    required String email,
    String? avatarUrl,
    String? memberSince,
    vt.VerificationBadgeType verificationType = vt.VerificationBadgeType.none,
  }) {
    final double statusBar = MediaQuery.of(context).padding.top;

    // ✅ iOS使用更紧凑的尺寸，Android保持原尺寸
    final bool isIOS = Platform.isIOS;
    final double avatarRadius = isIOS ? 44.0 : 48.0;
    final double nameFontSize = isIOS ? 22.0 : 24.0;
    final double emailFontSize = isIOS ? 12.5 : 13.0;
    final double memberFontSize = isIOS ? 10.5 : 11.0;
    final double headerBottomPadding = isIOS ? 24.0 : 30.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(24, statusBar + 20, 24, headerBottomPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'profile_avatar',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0.3)
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      VerifiedAvatar(
                        avatarUrl: avatarUrl,
                        radius: avatarRadius,
                        verificationType: verificationType,
                        onTap: !isGuest ? _uploadAvatarSimple : null,
                        defaultIcon:
                            isGuest ? Icons.person_outline : Icons.person,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: nameFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  shadows: const [
                    Shadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Color(0x40000000))
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(email.contains('@') ? Icons.email : Icons.phone,
                        size: 14, color: Colors.white.withOpacity(0.95)),
                    const SizedBox(width: 6),
                    Text(email,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: emailFontSize,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              if (!isGuest && memberSince != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('Member since $memberSince',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: memberFontSize,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Verification Tile ---------------- */
class _VerificationTileCard extends StatelessWidget {
  final bool isVerified;
  final bool isLoading;
  final VoidCallback? onTap;

  const _VerificationTileCard({
    required this.isVerified,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = isVerified ? Colors.green : Colors.grey;

    // ✅ iOS使用更紧凑的尺寸
    final bool isIOS = Platform.isIOS;
    final double cardPadding = isIOS ? 12.0 : 16.0;
    final double iconPadding = isIOS ? 8.0 : 10.0;
    final double iconSize = isIOS ? 22.0 : 24.0;
    final double titleFontSize = isIOS ? 15.0 : 16.0;
    final double subtitleFontSize = isIOS ? 12.5 : 13.5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.verified, color: badgeColor, size: iconSize),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVerified ? 'Verified' : 'Verification',
                        style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                        isVerified
                            ? 'Status: Verified'
                            : 'Status: Not verified',
                        style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.arrow_forward_ios,
                      size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- 统一的列表项 ---------------- */
class _ProfileOptionEnhanced extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ProfileOptionEnhanced({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ iOS使用更紧凑的尺寸
    final bool isIOS = Platform.isIOS;
    final double cardPadding = isIOS ? 12.0 : 16.0;
    final double iconPadding = isIOS ? 8.0 : 10.0;
    final double iconSize = isIOS ? 22.0 : 24.0;
    final double titleFontSize = isIOS ? 15.0 : 16.0;
    final double subtitleFontSize = isIOS ? 12.5 : 13.5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: iconSize),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: subtitleFontSize,
                              color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Guest 简版菜单 ---------------- */
class _GuestSimpleOptions extends StatelessWidget {
  const _GuestSimpleOptions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ProfileOptionEnhanced(
          icon: Icons.help_outline_rounded,
          title: l10n.helpSupport,
          color: Colors.blue,
          onTap: () => SafeNavigator.push(
              MaterialPageRoute(builder: (_) => const HelpSupportPage())),
        ),
        const SizedBox(height: 12),
        _ProfileOptionEnhanced(
          icon: Icons.info_outline_rounded,
          title: l10n.about,
          color: Colors.indigo,
          onTap: () => SafeNavigator.push(
              MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
      ],
    );
  }
}

/* ---------------- Help & Support Page ---------------- */
class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(l10n.helpSupport),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 12))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Need Help?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text('Our support team is here to help you 24/7',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9), fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Contact Information',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800])),
            const SizedBox(height: 14),
            _buildContactCard(
              icon: Icons.email_outlined,
              title: 'Email Support',
              subtitle: 'swaply@swaply.cc',
              color: Colors.blue,
              onTap: () =>
                  launchUrl(Uri(scheme: 'mailto', path: 'swaply@swaply.cc')),
            ),
            const SizedBox(height: 12),
            _buildContactCard(
              icon: Icons.language,
              title: 'Website',
              subtitle: 'www.swaply.cc',
              color: Colors.green,
              onTap: () => launchUrl(
                Uri.parse('https://www.swaply.cc'),
                mode: LaunchMode.inAppWebView,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800])),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ]),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- About Page ---------------- */
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Column(
                children: [
                  Text('Trade What You Have\nFor What You Need',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2F2F2F),
                          height: 1.3)),
                  SizedBox(height: 14),
                  Text(
                    'Swaply is your community marketplace for trading items you no longer need for things you actually want.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copyright_rounded,
                      size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 5),
                  Text('2024 Swaply. All rights reserved.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
