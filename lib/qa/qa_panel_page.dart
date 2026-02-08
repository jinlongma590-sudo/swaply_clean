import 'package:flutter/material.dart';
import 'package:swaply/pages/reward_center_page.dart';
import 'package:swaply/pages/reward_rules_page.dart';
import 'package:swaply/rewards/reward_bottom_sheet.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/core/qa_keys.dart'; // QaKeys
// ===== 全功能导航页面导入 =====
import 'package:swaply/pages/home_page.dart';
import 'package:swaply/pages/search_results_page.dart';
import 'package:swaply/pages/category_products_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/saved_page.dart';
import 'package:swaply/pages/notification_page.dart';
import 'package:swaply/pages/profile_page.dart';
import 'package:swaply/pages/sell_page.dart';

class QaPanelPage extends StatelessWidget {
  const QaPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QA Panel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'QA Automation Panel',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildSection('Navigation'),
          _buildButton(
            key: const Key(QaKeys.qaNavRewardCenter),
            text: 'Open Reward Center',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const RewardCenterPage()),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavRules),
            text: 'Open Reward Rules Page',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const RewardRulesPage()),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSection('Reward BottomSheet'),
          _buildButton(
            key: const Key(QaKeys.qaOpenRewardBottomSheet),
            text: 'Open Reward BottomSheet (Mock)',
            onPressed: () {
              _showMockRewardBottomSheet(context);
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaSeedPoolMock),
            text: 'Seed Pool Mock Data',
            onPressed: () {
              // This would typically set some global mock data
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mock pool data seeded (placeholder)')),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSection('Quick Publish (Placeholder)'),
          _buildButton(
            key: const Key(QaKeys.qaQuickPublish),
            text: 'Quick Publish & Trigger Reward',
            onPressed: () {
              // TODO: Implement quick publish that triggers real reward flow
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Quick publish not implemented yet')),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSection('Smoke Tests'),
          _buildButton(
            key: const Key(QaKeys.qaSmokeOpenTabs),
            text: 'Smoke: Open all tabs',
            onPressed: () {
              // TODO: Implement tab switching
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tab switching not implemented yet')),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSection('Functional Navigation (Full Coverage)'),
          _buildButton(
            key: const Key(QaKeys.qaNavHome),
            text: 'Open Home',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavSearchResults),
            text: 'Open Search Results',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => SearchResultsPage(keyword: 'test')),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavCategoryProducts),
            text: 'Open Category Products',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => CategoryProductsPage(categoryId: 'vehicles', categoryName: 'Vehicles')),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavProductDetail),
            text: 'Open Product Detail (Mock)',
            onPressed: () {
              // TODO: Implement mock listing for QA_MODE
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Product Detail mock not implemented yet')),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavFavoriteToggle),
            text: 'Toggle Favorite (Mock)',
            onPressed: () {
              // TODO: Implement favorite toggle on mock listing
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Favorite toggle mock not implemented yet')),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavSavedList),
            text: 'Open Saved List',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const SavedPage()),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavSellMockPublish),
            text: 'Sell Mock Publish',
            onPressed: () {
              // This will trigger the existing qaMockPublishButton in SellPage
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const SellPage()),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavNotifications),
            text: 'Open Notifications',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              );
            },
          ),
          _buildButton(
            key: const Key(QaKeys.qaNavProfile),
            text: 'Open Profile',
            onPressed: () {
              SafeNavigator.push(
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
          // Reward Center already has a button above
          const SizedBox(height: 24),
          _buildSection('Debug'),
          _buildButton(
            key: const Key(QaKeys.qaDebugLog),
            text: 'Print Debug Log',
            onPressed: () {
              debugPrint('[QA] Debug log printed');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Debug log printed to console')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildButton({
    required Key key,
    required String text,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ElevatedButton(
        key: key,
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  void _showMockRewardBottomSheet(BuildContext context) {
    final mockData = {
      'ok': true,
      'reward': null,
      'spins': 5,
      'qualified': 10,
      'points': 100,
      'pool': [
        {'id': '1', 'title': '5 Points', 'weight': 35},
        {'id': '2', 'title': '10 Points', 'weight': 15},
        {'id': '3', 'title': '3‑day Category Boost', 'weight': 8},
        {'id': '4', 'title': '3‑day Trending Boost', 'weight': 2},
        {'id': '5', 'title': 'Better luck next time', 'weight': 40},
      ],
      'milestone': 'Next spin at 20 qualified listings',
      'loop': 'After 40 listings, earn 1 spin every 10 listings',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RewardBottomSheet(
        data: mockData,
        campaignCode: 'launch_v1',
        listingId: 'mock-listing-id',
      ),
    );
  }
}