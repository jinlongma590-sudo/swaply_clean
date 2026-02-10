import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AirtimeRedeemPage extends StatefulWidget {
  const AirtimeRedeemPage({super.key});

  @override
  State<AirtimeRedeemPage> createState() => _AirtimeRedeemPageState();
}

class _AirtimeRedeemPageState extends State<AirtimeRedeemPage> {
  final _phoneController = TextEditingController();
  int _availablePoints = 0;
  bool _loading = false;
  bool _loadingPoints = true;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadPoints() async {
    setState(() => _loadingPoints = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('user_reward_state')
          .select('airtime_points')
          .eq('user_id', userId)
          .eq('campaign_code', 'launch_v1')
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _availablePoints = response?['airtime_points'] ?? 0;
        _loadingPoints = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPoints = false);
      _showError('Failed to load points: $e');
    }
  }

  Future<void> _redeemAirtime() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showError('Please enter phone number');
      return;
    }
    if (_availablePoints < 100) {
      _showError('You need at least 100 points');
      return;
    }

    setState(() => _loading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not logged in');

      final response = await Supabase.instance.client.functions.invoke(
        'airtime-redeem',
        body: {'phone': phone, 'points': 100, 'campaign': 'launch_v1'},
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      final data = response.data;
      final ok = (data is Map && data['ok'] == true);

      if (ok) {
        if (!mounted) return;
        _showSuccess(data['message']?.toString() ?? 'Redemption submitted!');
        _phoneController.clear();
        await _loadPoints();
      } else {
        _showError((data is Map ? data['error'] : null)?.toString() ??
            'Redemption failed');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem Airtime'), elevation: 0),
      body: _loadingPoints
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[400]!, Colors.blue[600]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text('Available Points',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text('$_availablePoints',
                              style: const TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 8),
                          const Text('100 points = \$1 airtime',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('Redeem Airtime',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'Enter phone number',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading ? null : _redeemAirtime,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)),
                          )
                        : const Text('Redeem \$1 Airtime (100 points)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.grey[700], size: 20),
                            const SizedBox(width: 8),
                            Text('Important Notes',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800])),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _info('• One redemption per 30 days per phone'),
                        _info('• Usually completes within 24 hours'),
                        _info('• Minimum 100 points required'),
                        _info('• Points are non-refundable'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _info(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child:
          Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
    );
  }
}
