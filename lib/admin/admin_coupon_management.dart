// lib/admin/admin_coupon_management.dart - Fixed English version with 3 core coupon types
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/services/coupon_service.dart';

class AdminCouponManagement extends StatefulWidget {
  const AdminCouponManagement({super.key});

  @override
  State<AdminCouponManagement> createState() => _AdminCouponManagementState();
}

class _AdminCouponManagementState extends State<AdminCouponManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _batchUserController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();

  CouponType _selectedType = CouponType.category; // Updated to use new enum
  int _selectedDuration = 7;
  bool _processing = false;

  List<Map<String, dynamic>> _recentUsers = [];
  List<CouponModel> _allCoupons = [];
  Map<String, int> _systemStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _batchUserController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([
        _loadRecentUsers(),
        _loadSystemStats(),
        _loadAllCoupons(),
      ]);
    } catch (e) {
      _showError('Failed to load initial data: $e');
    }
  }

  Future<void> _loadRecentUsers() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, email, created_at')
          .order('created_at', ascending: false)
          .limit(20);

      setState(() {
        _recentUsers = response
            .map<Map<String, dynamic>>((user) => {
                  'id': user['id'],
                  'email': user['email'] ?? 'No email',
                  'created_at': user['created_at'],
                })
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
      setState(() {
        _recentUsers = [];
      });
    }
  }

  Future<void> _loadAllCoupons() async {
    try {
      final response = await Supabase.instance.client
          .from('coupons')
          .select('*')
          .order('created_at', ascending: false)
          .limit(100);

      final coupons = response.map<CouponModel>((data) {
        return CouponModel.fromMap(Map<String, dynamic>.from(data));
      }).toList();

      setState(() {
        _allCoupons = coupons;
      });
    } catch (e) {
      debugPrint('Error loading coupons: $e');
    }
  }

  Future<void> _loadSystemStats() async {
    try {
      final couponsResponse =
          await Supabase.instance.client.from('coupons').select('type, status');

      final pinnedResponse =
          await Supabase.instance.client.from('pinned_ads').select('status');

      final usersResponse =
          await Supabase.instance.client.from('profiles').select('id');

      final coupons = couponsResponse
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
      final pinnedAds = pinnedResponse
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _systemStats = {
          'total_users': usersResponse.length,
          'total_coupons': coupons.length,
          'active_coupons':
              coupons.where((c) => c['status'] == 'active').length,
          'used_coupons': coupons.where((c) => c['status'] == 'used').length,
          'category_coupons': coupons
              .where((c) => ['category', 'pinned', 'featured', 'premium']
                  .contains(c['type']))
              .length,
          'trending_coupons': coupons
              .where((c) => ['trending', 'trending_pin'].contains(c['type']))
              .length,
          'boost_coupons': coupons.where((c) => c['type'] == 'boost').length,
          'reward_coupons': coupons
              .where((c) => [
                    'register_bonus',
                    'activity_bonus',
                    'referral_bonus',
                    'welcome'
                  ].contains(c['type']))
              .length,
          'total_pinned_ads': pinnedAds.length,
          'active_pinned_ads':
              pinnedAds.where((p) => p['status'] == 'active').length,
        };
      });
    } catch (e) {
      debugPrint('Error loading system stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Coupon Management'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle), text: 'Create'),
            Tab(icon: Icon(Icons.list), text: 'Coupons'),
            Tab(icon: Icon(Icons.analytics), text: 'Stats'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(),
          _buildCouponsTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick send
          _buildQuickSendCard(),
          const SizedBox(height: 16),

          // Batch send
          _buildBatchSendCard(),
          const SizedBox(height: 16),

          // Custom coupon
          _buildCustomCouponCard(),
          const SizedBox(height: 16),

          // User list
          if (_recentUsers.isNotEmpty) _buildUserListCard(),
        ],
      ),
    );
  }

  Widget _buildQuickSendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎯 Quick Send to All Users',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedDuration,
                    decoration: const InputDecoration(
                      labelText: 'Duration (days)',
                      border: OutlineInputBorder(),
                    ),
                    items: [3, 7, 14, 30].map((days) {
                      return DropdownMenuItem(
                        value: days,
                        child: Text('$days days'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedDuration = value ?? 7);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _processing ? null : _sendToAllUsers,
                  icon: _processing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(_processing ? 'Sending...' : 'Send to All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchSendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '👥 Batch Send',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _batchUserController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'User emails (one per line)',
                hintText: 'user1@example.com\nuser2@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _sendToBatchUsers,
                icon: _processing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Send to Selected Users'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCouponCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✨ Create Custom Coupon',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CouponType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                // Only show actual coupon types for admin creation
                CouponType.trending,
                CouponType.category,
                CouponType.boost,
                CouponType.welcome, // 新增欢迎券选项
              ].map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayNameEn),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedType = value ?? CouponType.category);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (days)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _createCustomCoupon,
                icon: const Icon(Icons.create),
                label: const Text('Create Custom Coupon'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserListCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Recent Users',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _loadRecentUsers,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _recentUsers.length,
                itemBuilder: (context, index) {
                  final user = _recentUsers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text((user['email'] ?? '?')
                          .toString()
                          .substring(0, 1)
                          .toUpperCase()),
                    ),
                    title: Text(user['email'] ?? 'No email'),
                    subtitle: Text(user['id'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.send, color: Colors.orange),
                      onPressed: () => _sendToSingleUser(user['id']),
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

  Widget _buildCouponsTab() {
    return RefreshIndicator(
      onRefresh: _loadAllCoupons,
      child: _allCoupons.isEmpty
          ? const Center(child: Text('No coupons found'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allCoupons.length,
              itemBuilder: (context, index) {
                final coupon = _allCoupons[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _getCouponIcon(coupon.type),
                    title: Text(coupon.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Code: ${coupon.code}'),
                        Text('Status: ${coupon.statusDescription}'),
                        Text('User: ${coupon.userId}'),
                        Text('Type: ${coupon.type.displayNameEn}'),
                        Text('Expires: ${coupon.formattedExpiryDate}'),
                      ],
                    ),
                    trailing: coupon.status == CouponStatus.active
                        ? IconButton(
                            icon: const Icon(Icons.block, color: Colors.red),
                            onPressed: () => _revokeCoupon(coupon),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatsTab() {
    return RefreshIndicator(
      onRefresh: _loadSystemStats,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Statistics',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildStatRow(
                        'Total Users', _systemStats['total_users'] ?? 0),
                    _buildStatRow(
                        'Total Coupons', _systemStats['total_coupons'] ?? 0),
                    _buildStatRow(
                        'Active Coupons', _systemStats['active_coupons'] ?? 0),
                    _buildStatRow(
                        'Used Coupons', _systemStats['used_coupons'] ?? 0),
                    _buildStatRow('Category Coupons',
                        _systemStats['category_coupons'] ?? 0),
                    _buildStatRow('Trending Coupons',
                        _systemStats['trending_coupons'] ?? 0),
                    _buildStatRow(
                        'Boost Coupons', _systemStats['boost_coupons'] ?? 0),
                    _buildStatRow(
                        'Reward Coupons', _systemStats['reward_coupons'] ?? 0),
                    _buildStatRow('Total Pinned Ads',
                        _systemStats['total_pinned_ads'] ?? 0),
                    _buildStatRow('Active Pinned Ads',
                        _systemStats['active_pinned_ads'] ?? 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Quick Actions',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _cleanupExpiredData,
                        icon: const Icon(Icons.cleaning_services),
                        label: const Text('Cleanup Expired Data'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _getCouponIcon(CouponType type) {
    IconData icon;
    Color color;

    // 修复编译错误：添加所有枚举值的 case
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin: // Legacy support
        icon = Icons.local_fire_department;
        color = Colors.orange[700]!;
        break;
      case CouponType.category:
      case CouponType.pinned: // Legacy support
      case CouponType.featured: // Legacy support
      case CouponType.premium: // Legacy support
        icon = Icons.push_pin;
        color = Colors.blue;
        break;
      case CouponType.boost:
        icon = Icons.rocket_launch;
        color = Colors.purple;
        break;
      case CouponType.registerBonus:
        icon = Icons.card_giftcard;
        color = Colors.green;
        break;
      case CouponType.activityBonus:
        icon = Icons.task_alt;
        color = Colors.blue;
        break;
      case CouponType.referralBonus:
        icon = Icons.group_add;
        color = Colors.pink;
        break;
      case CouponType.welcome: // ★ 新增欢迎券的处理
        icon = Icons.waving_hand;
        color = Colors.green[600]!;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  // Business logic methods
  Future<void> _sendToAllUsers() async {
    if (!await _showConfirmDialog(
      'Send to All Users',
      'This will send coupons to ALL users. Continue?',
    )) {
      return;
    }

    setState(() => _processing = true);
    try {
      final usersResponse =
          await Supabase.instance.client.from('profiles').select('id');

      final userIds =
          usersResponse.map<String>((u) => u['id'] as String).toList();

      if (userIds.isEmpty) {
        _showError('No users found');
        return;
      }

      // Create category coupons by default for bulk send
      final results = <CouponModel>[];
      for (final userId in userIds) {
        try {
          final coupon = await CouponService.createCoupon(
            userId: userId,
            type: CouponType.category,
            title: 'Admin Bulk Reward',
            description:
                'Special reward from admin - Pin your item in category page',
            durationDays: _selectedDuration,
          );
          if (coupon != null) {
            results.add(coupon);
          }
        } catch (e) {
          debugPrint('Failed to create coupon for user $userId: $e');
        }
      }

      _showSuccess(
          'Sent ${results.length} coupons to ${userIds.length} users!');
      await _loadAllCoupons();
      await _loadSystemStats();
    } catch (e) {
      _showError('Failed to send coupons: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _sendToBatchUsers() async {
    final input = _batchUserController.text.trim();
    if (input.isEmpty) {
      _showError('Please enter user emails');
      return;
    }

    final emails = input
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() => _processing = true);
    try {
      final userIds = <String>[];

      for (final email in emails) {
        final userResponse = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .eq('email', email)
            .maybeSingle();

        if (userResponse != null) {
          userIds.add(userResponse['id'] as String);
        }
      }

      if (userIds.isEmpty) {
        _showError('No valid users found');
        return;
      }

      final results = <CouponModel>[];
      for (final userId in userIds) {
        try {
          final coupon = await CouponService.createCoupon(
            userId: userId,
            type: CouponType.category,
            title: 'Admin Batch Reward',
            description:
                'Special reward from admin - Pin your item in category page',
            durationDays: _selectedDuration,
          );
          if (coupon != null) {
            results.add(coupon);
          }
        } catch (e) {
          debugPrint('Failed to create coupon for user $userId: $e');
        }
      }

      _showSuccess(
          'Sent ${results.length} coupons to ${userIds.length} users!');
      _batchUserController.clear();
      await _loadAllCoupons();
      await _loadSystemStats();
    } catch (e) {
      _showError('Failed to send coupons: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _sendToSingleUser(String userId) async {
    try {
      final coupon = await CouponService.createCoupon(
        userId: userId,
        type: CouponType.category,
        title: 'Admin Single Reward',
        description:
            'Special reward from admin - Pin your item in category page',
        durationDays: _selectedDuration,
      );

      if (coupon != null) {
        _showSuccess('Coupon sent successfully!');
        await _loadAllCoupons();
        await _loadSystemStats();
      } else {
        _showError('Failed to send coupon');
      }
    } catch (e) {
      _showError('Failed to send coupon: $e');
    }
  }

  Future<void> _createCustomCoupon() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final durationText = _durationController.text.trim();

    if (title.isEmpty || description.isEmpty || durationText.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    final duration = int.tryParse(durationText);
    if (duration == null || duration <= 0) {
      _showError('Please enter a valid duration');
      return;
    }

    final userId = await _showUserSelectionDialog();
    if (userId == null) return;

    setState(() => _processing = true);
    try {
      final coupon = await CouponService.createCoupon(
        userId: userId,
        type: _selectedType,
        title: title,
        description: description,
        durationDays: duration,
      );

      if (coupon != null) {
        _showSuccess('Custom coupon created successfully!');
        _titleController.clear();
        _descriptionController.clear();
        _durationController.clear();
        await _loadAllCoupons();
        await _loadSystemStats();
      } else {
        _showError('Failed to create coupon');
      }
    } catch (e) {
      _showError('Failed to create coupon: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _revokeCoupon(CouponModel coupon) async {
    if (!await _showConfirmDialog(
      'Revoke Coupon',
      'Are you sure you want to revoke this coupon?\n\nCode: ${coupon.code}',
    )) {
      return;
    }

    try {
      final success = await CouponService.revokeCoupon(coupon.id);
      if (success) {
        _showSuccess('Coupon revoked successfully');
        await _loadAllCoupons();
        await _loadSystemStats();
      } else {
        _showError('Failed to revoke coupon');
      }
    } catch (e) {
      _showError('Failed to revoke coupon: $e');
    }
  }

  Future<void> _cleanupExpiredData() async {
    if (!await _showConfirmDialog(
      'Cleanup Expired Data',
      'This will mark all expired data as expired. Continue?',
    )) {
      return;
    }

    try {
      // 直接清理过期的优惠券
      final now = DateTime.now().toIso8601String();

      // 更新过期的优惠券状态
      final expiredCoupons = await Supabase.instance.client
          .from('coupons')
          .update({'status': 'expired'})
          .lt('expires_at', now)
          .eq('status', 'active')
          .select('id');

      final expiredCount = expiredCoupons.length;

      _showSuccess('Cleaned up $expiredCount expired coupons');
      await _loadSystemStats();
    } catch (e) {
      _showError('Failed to cleanup: $e');
    }
  }

  Future<String?> _showUserSelectionDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select User'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _recentUsers.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: _recentUsers.length,
                  itemBuilder: (context, index) {
                    final user = _recentUsers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text((user['email'] ?? '?')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase()),
                      ),
                      title: Text(user['email'] ?? 'No email'),
                      subtitle: Text(user['id'] ?? ''),
                      onTap: () => Navigator.of(ctx).pop(user['id']),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
