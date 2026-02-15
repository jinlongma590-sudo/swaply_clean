import 'package:flutter/material.dart';

class RewardRulesPage extends StatelessWidget {
  final List<Map<String, dynamic>>? pool;

  const RewardRulesPage({super.key, this.pool});

  @override
  Widget build(BuildContext context) {
    final totalWeight = pool?.fold<int>(0, (sum, item) => sum + (item['weight'] as int? ?? 0)) ?? 0;

    return Scaffold(
      appBar: AppBar(
        key: const Key('reward_rules_title'),
        title: const Text('Rewards Rules & Odds'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionTitle('Apple Disclaimer'),
          _buildCard(
            'This promotion is sponsored by Swaply. Apple is not a sponsor and is not involved in any way with this promotion.',
          ),
          
          _buildSectionTitle('No purchase necessary'),
          _buildCard(
            'No purchase is necessary to participate. Spins are earned by:\n'
            '• Publishing qualified listings in the app\n'
            '• Inviting friends to join Swaply',
          ),
          
          _buildSectionTitle('How to earn spins'),
          _buildCard(
            'Spins are earned through two main ways:\n\n'
            '📱 Publish Qualified Listings\n'
            'Spins are granted when you publish qualified listings. Milestone rewards:\n'
            '• Listing #1: 1 spin\n'
            '• Listing #5: 1 spin\n' 
            '• Listing #10: 1 spin\n'
            '• Listing #20: 1 spin\n'
            '• Listing #30: 1 spin\n\n'
            'After 40 qualified listings, you will receive 1 spin for every 10 additional listings.\n\n'
            '👥 Invite Friends (New!)\n'
            'Get FREE spins for inviting friends to Swaply:\n'
            '• Instant Reward: 1 Free Spin for EVERY friend who posts their first listing\n'
            '• Milestone Reward: Boost Cards when you reach 1, 5, 10 successful referrals\n\n'
            '🎉 No Empty Spins: Every spin wins a prize!',
          ),
          
          _buildSectionTitle('Prize types'),
          _buildCard(
            '💰 Airtime Points\n'
            '• 5 Points: Small airtime reward\n'
            '• 10 Points: Medium airtime reward\n'
            '• 100 Points: Major airtime jackpot (New!)\n'
            'Points cannot be withdrawn or transferred. They can only be redeemed for airtime within the app according to redemption rules.\n\n'
            '🚀 Boost Coupons\n'
            '• Category Boost: Promote your listing in the category section for 3 days\n'
            '• Search Boost: Make your listing appear higher in search results for 3 days\n'
            '• Trending Boost: Feature your listing in the trending section for 3 days\n'
            'Boost coupons are valid for 3 days, non-transferable, and must be used before expiration.',
          ),
          

          

          
          _buildSectionTitle('Limits & abuse'),
          _buildCard(
            '• One spin per qualified listing milestone\n'
            '• Only one account per user\n'
            '• Fraudulent activity will result in account suspension\n'
            '• Spin rewards must be claimed within 30 days\n'
            '• Swaply reserves the right to modify or cancel this promotion',
          ),
          
          _buildSectionTitle('Contact'),
          _buildCard(
            'For questions about rewards, contact support@swaply.com',
          ),
          
          _buildSectionTitle('Last updated'),
          _buildCard('2026-02-14'),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCard(String content) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }


}