import 'package:flutter/material.dart';

class RewardRulesPage extends StatelessWidget {
  final List<Map<String, dynamic>>? pool;

  const RewardRulesPage({super.key, this.pool});

  @override
  Widget build(BuildContext context) {
    final totalWeight = pool?.fold<int>(0, (sum, item) => sum + (item['weight'] as int? ?? 0)) ?? 0;

    return Scaffold(
      appBar: AppBar(
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
            'No purchase is necessary to participate. Spins are earned by publishing qualified listings in the app.',
          ),
          
          _buildSectionTitle('How to earn spins'),
          _buildCard(
            'Spins are granted when you publish qualified listings. Milestone rewards:\n'
            '• Listing #1: 1 spin\n'
            '• Listing #5: 1 spin\n' 
            '• Listing #10: 1 spin\n'
            '• Listing #20: 1 spin\n'
            '• Listing #30: 1 spin\n\n'
            'After 40 qualified listings, you will receive 1 spin for every 10 additional listings.',
          ),
          
          _buildSectionTitle('Prize types'),
          _buildCard(
            '• Airtime Points: Points cannot be withdrawn or transferred. They can only be redeemed for airtime within the app according to redemption rules.\n\n'
            '• Boost Coupons: Boost coupons can be used to promote listings in Category, Search, or Trending sections. They are valid for 3 days, non-transferable, and must be used before expiration.',
          ),
          
          _buildSectionTitle('Odds / Prize Pool'),
          _buildCard(
            'Prize probabilities are determined by backend pool weights and may be adjusted. Current probabilities are shown below.',
          ),
          
          if (pool != null && pool!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPrizePoolSection(pool!, totalWeight),
          ] else ...[
            _buildCard(
              'Prize pool is shown in the Spin & Win sheet. Open the spin wheel to view current prize probabilities.',
            ),
          ],
          
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
          _buildCard('2026-02-07'),
          
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

  Widget _buildPrizePoolSection(List<Map<String, dynamic>> pool, int totalWeight) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: const Text(
          'Prize Pool & Probability',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: pool.map((item) {
                final title = (item['title'] ?? item['id'] ?? 'Reward').toString();
                final weight = item['weight'] as int? ?? 0;
                final probability = totalWeight > 0 
                    ? '${(weight * 100 / totalWeight).toStringAsFixed(1)}%'
                    : '0.0%';
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          probability,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}